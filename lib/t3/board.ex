defmodule T3.Board do
  @moduledoc """
  Pure board projection for ordinary orchestration shell/thread streams.

  Fold chunk arrays and catch-up results with `apply/3`. The returned map is
  keyed by `{host, thread_id}`, so IDs from different environments cannot collide.
  A full shell snapshot replaces only that host's rows. Project-enrichment-only
  snapshots do not clear rows. Sparse thread events preserve fields they do not
  carry. Unknown event types are ignored.

      rows = T3.Board.apply(%{}, chunk_values, host: "local")
      rows = T3.Board.apply(rows, next_chunk_values, host: "local")

  `normalize/2` exposes individual upserts/removals for callers keeping their own
  cache. Its upserts can be partial (nil fields mean unavailable); use `apply/3`
  when retaining prior fields and authoritative snapshot replacement matters.

  Inputs must use ordinary, uncompressed projection bodies. Do not opt into
  `acceptCompactIds`, `acceptDedupedBodies`, `acceptCompactTurnItems`, or deferred
  work without restoring T3's projection format first. Timestamps and statuses
  are wire strings. Snippets collapse whitespace and default to 160 graphemes.
  """
  alias T3.Board.Thread
  @type key :: {term(), String.t()}

  @doc "Fold a chunk, shell snapshot, or thread projection into a board cache."
  @spec apply(%{optional(key()) => Thread.t()}, map() | [map()], keyword()) :: map()
  def apply(rows, values, opts \\ []) when is_map(rows) do
    host = Keyword.fetch!(opts, :host)
    Enum.reduce(List.wrap(values), rows, &apply_item(&2, &1, host, opts))
  end

  @doc "Return `{:upsert, row}` / `{:delete, thread_id}` operations for wire items."
  def normalize(values, opts \\ []) do
    host = Keyword.fetch!(opts, :host)

    Enum.flat_map(List.wrap(values), fn item ->
      item
      |> operations(opts)
      |> Enum.map(fn
        {:upsert, patch} -> {:upsert, struct(Thread, Map.put(patch, :host, host))}
        removal -> removal
      end)
    end)
  end

  defp apply_item(rows, item, host, opts) do
    rows =
      if authoritative_shell?(item),
        do: Map.reject(rows, fn {{row_host, _}, _} -> row_host == host end),
        else: rows

    Enum.reduce(operations(item, opts), rows, fn
      {:delete, id}, acc ->
        Map.delete(acc, {host, id})

      {:upsert, %{thread_id: id} = patch}, acc ->
        key = {host, id}
        existing = Map.get(acc, key, %Thread{thread_id: id, host: host})
        Map.put(acc, key, merge_patch(existing, patch))
    end)
  end

  defp authoritative_shell?(%{"kind" => "snapshot", "snapshot" => _} = item),
    do: not Map.has_key?(item, "resolvedRepositoryIdentityRoots")

  defp authoritative_shell?(%{"threads" => _}), do: true
  defp authoritative_shell?(_), do: false

  defp operations(%{"resolvedRepositoryIdentityRoots" => _, "snapshot" => _}, _opts), do: []

  defp operations(%{"kind" => "snapshot", "snapshot" => snapshot}, opts),
    do: operations(snapshot, opts)

  defp operations(%{"threads" => threads} = snapshot, opts) do
    Enum.flat_map(threads ++ Map.get(snapshot, "archivedThreads", []), &shell_row(&1, opts))
  end

  defp operations(%{"kind" => "thread.updated", "thread" => thread}, opts),
    do: shell_row(thread, opts)

  defp operations(%{"kind" => "thread.removed", "threadId" => id}, _opts),
    do: [{:delete, id}]

  defp operations(%{"kind" => "snapshot", "projection" => projection}, opts),
    do: operations(projection, opts)

  defp operations(%{"thread" => thread} = projection, opts) do
    case thread_patch(thread) do
      {:delete, id} ->
        [{:delete, id}]

      {:upsert, patch} ->
        runs = Map.get(projection, "runs", [])
        newest_run = Enum.max_by(runs, &Map.get(&1, "ordinal", 0), fn -> %{} end)

        message =
          Enum.max_by(Map.get(projection, "messages", []), &message_order/1, fn -> %{} end)

        times = Enum.map(runs ++ Map.get(projection, "providerTurns", []), &turn_time/1)

        patch =
          patch
          |> Map.put(
            :state,
            if(thread["archivedAt"], do: "archived", else: newest_run["status"] || "idle")
          )
          |> Map.put(:__replace__, true)
          |> Map.put(:__meta__, %{
            run: run_meta(newest_run),
            message: message_meta(message),
            archived: not is_nil(thread["archivedAt"])
          })
          |> Map.put(:last_turn_at, latest(times))
          |> Map.put(:last_message_snippet, snippet(message["text"], opts))

        [{:upsert, patch}]
    end
  end

  defp operations(%{"kind" => "event", "event" => event}, opts), do: event(event, opts)
  defp operations(_, _opts), do: []

  defp shell_row(%{"id" => _} = thread, opts) do
    case thread_patch(thread) do
      {:delete, id} ->
        [{:delete, id}]

      {:upsert, patch} ->
        patch =
          patch
          |> Map.put(
            :state,
            if(thread["archivedAt"], do: "archived", else: thread["status"] || "idle")
          )
          |> Map.put(
            :last_turn_at,
            latest(
              Enum.map(
                ~w(latestRunRequestedAt latestRunStartedAt latestRunCompletedAt activityRunStartedAt),
                &thread[&1]
              )
            )
          )
          |> Map.put(
            :last_message_snippet,
            snippet(get_in(thread, ["latestVisibleMessage", "text"]), opts)
          )
          |> Map.put(:__replace__, true)
          |> Map.put(:__meta__, %{
            run: %{
              id: thread["latestRunId"],
              ordinal: nil,
              requested_at: thread["latestRunRequestedAt"],
              status: thread["status"]
            },
            message: message_meta(thread["latestVisibleMessage"] || %{}),
            archived: not is_nil(thread["archivedAt"])
          })

        [{:upsert, patch}]
    end
  end

  defp shell_row(_, _opts), do: []

  defp thread_patch(%{"id" => id, "deletedAt" => deleted}) when not is_nil(deleted),
    do: {:delete, id}

  defp thread_patch(%{"id" => id} = thread) do
    patch = %{thread_id: id}

    patch =
      if Map.has_key?(thread, "title"), do: Map.put(patch, :title, thread["title"]), else: patch

    {:upsert, patch}
  end

  defp event(%{"type" => "thread.deleted", "threadId" => id}, _opts), do: [{:delete, id}]

  defp event(%{"type" => "thread." <> _, "payload" => %{"id" => _} = thread} = event, _opts) do
    case thread_patch(thread) do
      {:delete, id} ->
        [{:delete, id}]

      {:upsert, patch} ->
        patch =
          case event["type"] do
            "thread.archived" ->
              patch |> Map.put(:state, "archived") |> Map.put(:__meta__, %{archived: true})

            "thread.unarchived" ->
              patch |> Map.put(:state, "idle") |> Map.put(:__meta__, %{archived: false})

            _ ->
              patch
          end

        [{:upsert, patch}]
    end
  end

  defp event(%{"type" => type, "threadId" => id, "payload" => payload}, _opts)
       when type in ["run.created", "run.updated"] do
    [
      {:upsert,
       %{
         thread_id: id,
         state: payload["status"],
         last_turn_at: turn_time(payload),
         __meta__: %{run: run_meta(payload)}
       }}
    ]
  end

  defp event(%{"type" => "provider-turn.updated", "threadId" => id, "payload" => payload}, _opts),
    do: [{:upsert, %{thread_id: id, last_turn_at: turn_time(payload)}}]

  defp event(%{"type" => "message.updated", "threadId" => id, "payload" => payload}, opts),
    do: [
      {:upsert,
       %{
         thread_id: id,
         last_message_snippet: snippet(payload["text"], opts),
         __meta__: %{message: message_meta(payload)}
       }}
    ]

  defp event(_, _opts), do: []

  defp snippet(nil, _opts), do: nil

  defp snippet(text, opts) when is_binary(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, Keyword.get(opts, :snippet_length, 160))
  end

  defp turn_time(value),
    do: latest(Enum.map(~w(requestedAt workStartedAt startedAt completedAt), &value[&1]))

  defp run_meta(run),
    do: %{
      id: run["id"],
      ordinal: run["ordinal"],
      requested_at: run["requestedAt"],
      status: run["status"]
    }

  defp message_meta(message),
    do: %{id: message["id"], created_at: message["createdAt"], updated_at: message["updatedAt"]}

  defp message_order(message), do: {timestamp_key(message["createdAt"]), message["id"] || ""}

  defp merge_patch(existing, patch) do
    {replace?, patch} = Map.pop(patch, :__replace__, false)

    if replace? do
      struct(existing, patch)
    else
      candidate = Map.get(patch, :__meta__, %{})
      old = existing.__meta__

      {patch, candidate} =
        if Map.has_key?(candidate, :run) and not newer_run?(candidate.run, Map.get(old, :run)) do
          {Map.delete(patch, :state), Map.delete(candidate, :run)}
        else
          {patch, candidate}
        end

      {patch, candidate} =
        if Map.has_key?(candidate, :message) and
             not newer_message?(candidate.message, Map.get(old, :message)) do
          {Map.delete(patch, :last_message_snippet), Map.delete(candidate, :message)}
        else
          {patch, candidate}
        end

      meta = Map.merge(old, candidate)

      patch =
        cond do
          Map.get(meta, :archived) == true ->
            Map.put(patch, :state, "archived")

          Map.get(candidate, :archived) == false ->
            Map.put(patch, :state, get_in(meta, [:run, :status]) || "idle")

          true ->
            patch
        end

      patch =
        if Map.has_key?(patch, :last_turn_at),
          do: Map.update!(patch, :last_turn_at, &latest([&1, existing.last_turn_at])),
          else: patch

      struct(existing, Map.put(patch, :__meta__, meta))
    end
  end

  defp newer_run?(_new, nil), do: true
  defp newer_run?(%{id: id}, %{id: id}) when not is_nil(id), do: true

  defp newer_run?(%{ordinal: new}, %{ordinal: old}) when is_integer(new) and is_integer(old),
    do: new > old

  defp newer_run?(%{requested_at: new}, %{requested_at: old})
       when is_binary(new) and is_binary(old), do: timestamp_key(new) > timestamp_key(old)

  defp newer_run?(_new, %{id: nil}), do: true
  defp newer_run?(_new, _old), do: false

  defp newer_message?(_new, nil), do: true

  defp newer_message?(%{id: id} = new, %{id: id} = old) when not is_nil(id),
    do: timestamp_key(new.updated_at) >= timestamp_key(old.updated_at)

  defp newer_message?(new, old) do
    new_time = new.created_at
    old_time = old.created_at || old.updated_at

    cond do
      is_binary(new_time) and is_binary(old_time) ->
        {timestamp_key(new_time), new.id || ""} > {timestamp_key(old_time), old.id || ""}

      old.id == nil ->
        true

      true ->
        false
    end
  end

  defp latest(times),
    do: times |> Enum.reject(&is_nil/1) |> Enum.max_by(&timestamp_key/1, fn -> nil end)

  defp timestamp_key(nil), do: {0, ""}

  defp timestamp_key(time) do
    case DateTime.from_iso8601(time) do
      {:ok, date, _offset} -> {1, DateTime.to_unix(date, :microsecond)}
      {:error, _} -> {0, time}
    end
  end
end
