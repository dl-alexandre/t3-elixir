defmodule T3.RPC.Reader do
  @moduledoc """
  Supervised owner of reconnecting, read-only RPC subscriptions.

  Add this child to your application's supervisor. `:connect` is a zero-arity
  function returning `{:ok, rpc_options}` and is called on every connection
  attempt, so tickets can be freshly minted and local credentials renewed.
  `:streams` contains maps with `:key`, `:method`, optional `:payload`, and optional
  `:catch_up` (`{method, payload}`). Only explicitly configured catch-up reads are
  repeated; arbitrary RPC commands are never replayed.

  `:on_event` is a synchronous function receiving `{:snapshot, key, value}`,
  `{:chunk, key, values}`, or `{:status, status}`. It must return `:ok` after the
  data is consumed; only then is the chunk acknowledged. A callback failure stops
  this child so its supervisor can restart it. Do not block indefinitely or send
  unbounded messages to a slower consumer from this callback.

  Catch-up reads run before subscriptions on each connection. Without a resume
  cursor, T3's shell/thread streams start with an authoritative snapshot,
  covering changes between the read and subscription. Other protocols need their own cursor/snapshot strategy.
  Snapshots/events can repeat across reconnects; reducers must tolerate duplicates.
  Opt in to best-effort server replay with `resume: true` on shell/thread stream
  maps. Committed sequences are injected as `afterSequence` on reconnect.
  `:load_cursor` (`fn key -> integer_or_nil end`) and `:save_cursor`
  (`fn key, sequence -> :ok end`) can persist checkpoints across process restarts.
  Checkpoints advance after consumption and before ACK; storage/callback failure
  stops this child. Replay may coalesce or fall back to a snapshot: this is not
  durable audit/billing history. `payload` and catch-up payloads may also be
  functions of the last committed sequence, preserving arbitrary supported wire
  options without inventing cursor fields on snapshot-only reads.

  A chunk callback may return `{:error, :busy}` only when it has consumed none
  of that chunk, to defer consumption and withhold its ACK. It is retried every `:consumer_retry_interval` (default 100 ms), keeping
  the reader responsive. At most one deferred chunk per configured subscription
  is retained; the transport's upstream backpressure bounds further delivery.
  This pairs with `T3.RPC.WorkQueue.enqueue/2` for optional asynchronous processing.
  Queue admission ACKs before execution and is not durable. Catch-up/status
  callbacks must still return `:ok` promptly.

  There is no durable delivery guarantee for intermediate events while offline.
  Both stream completion and transport failure trigger reconnect. Backoff is
  exponential with jitter, bounded by `:min_backoff` (500 ms) and `:max_backoff`
  (30 seconds). A successfully consumed chunk resets it. `:jitter` defaults to
  0.2 (set zero in deterministic tests).

  Set `:health_check` to a read-only `{method, payload}` to detect half-open idle
  connections. It runs every `:health_interval` (30 seconds), with a
  `:health_timeout` (5 seconds). A failed probe reconnects. Disabled by default.

  See the board integration guide for a complete supervision example. Credentials
  and callback state are omitted from process status output.
  """
  use GenServer
  alias T3.RPC

  def start_link(opts) do
    {server_opts, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc "Return `:connected` or `:disconnected` without exposing connection credentials."
  def status(server), do: GenServer.call(server, :status)

  @doc "Return committed per-stream sequence cursors (only for resume-enabled streams)."
  def cursors(server), do: GenServer.call(server, :cursors)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    connect = Keyword.fetch!(opts, :connect)
    callback = Keyword.fetch!(opts, :on_event)
    streams = Keyword.fetch!(opts, :streams)
    min = Keyword.get(opts, :min_backoff, 500)
    max = Keyword.get(opts, :max_backoff, 30_000)
    jitter = Keyword.get(opts, :jitter, 0.2)
    health = Keyword.get(opts, :health_check)
    interval = Keyword.get(opts, :health_interval, 30_000)
    health_timeout = Keyword.get(opts, :health_timeout, 5_000)
    load_cursor = Keyword.get(opts, :load_cursor, fn _key -> nil end)
    save_cursor = Keyword.get(opts, :save_cursor, fn _key, _sequence -> :ok end)
    consumer_retry = Keyword.get(opts, :consumer_retry_interval, 100)

    if is_function(connect, 0) and is_function(callback, 1) and is_list(streams) and
         streams != [] and Enum.all?(streams, &valid_stream?/1) and
         length(Enum.uniq_by(streams, & &1.key)) == length(streams) and
         is_integer(min) and min > 0 and is_integer(max) and max >= min and
         is_number(jitter) and jitter >= 0 and jitter <= 1 and
         valid_health?(health) and is_integer(interval) and interval > 0 and
         is_integer(health_timeout) and health_timeout > 0 and
         is_function(load_cursor, 1) and is_function(save_cursor, 2) and
         is_integer(consumer_retry) and consumer_retry > 0 do
      state = %{
        connect: connect,
        callback: callback,
        streams: streams,
        rpc: nil,
        ids: %{},
        timer: nil,
        min: min,
        max: max,
        delay: min,
        jitter: jitter,
        health: health,
        health_interval: interval,
        health_timeout: health_timeout,
        cursors: initial_cursors(streams, load_cursor),
        save_cursor: save_cursor,
        deferred: %{},
        drain_timer: nil,
        consumer_retry: consumer_retry
      }

      {:ok, schedule(state, 0)}
    else
      {:stop, %T3.Error{kind: :configuration, message: "invalid RPC reader configuration"}}
    end
  end

  @impl true
  def handle_call(:status, _, state),
    do: {:reply, if(state.rpc, do: :connected, else: :disconnected), state}

  def handle_call(:cursors, _, state), do: {:reply, state.cursors, state}

  @impl true
  def handle_info({:connect, marker}, %{timer: {_, marker}} = state) do
    state = %{state | timer: nil}

    case state.connect.() do
      {:ok, opts} when is_list(opts) ->
        case RPC.start_link(Keyword.put(opts, :owner, self())) do
          {:ok, rpc} ->
            state = %{state | rpc: rpc}

            case establish(state) do
              {:ok, state} ->
                schedule_health(state)
                :ok = state.callback.({:status, :connected})
                {:noreply, state}

              {:error, reason} ->
                {:noreply, retry(state, reason)}
            end

          {:error, reason} ->
            {:noreply, retry(state, reason)}
        end

      {:error, reason} ->
        {:noreply, retry(state, reason)}
    end
  end

  def handle_info({:health, rpc}, %{rpc: rpc, health: {method, payload}} = state)
      when is_pid(rpc) do
    case RPC.call(rpc, method, payload, timeout: state.health_timeout) do
      {:ok, _} ->
        schedule_health(state)
        {:noreply, state}

      {:error, reason} ->
        {:noreply, retry(state, reason)}
    end
  end

  def handle_info({:t3_rpc, id, {:chunk, values}}, state) do
    case Map.fetch(state.ids, id) do
      {:ok, key} -> consume_chunk(state, id, key, values)
      :error -> {:noreply, state}
    end
  end

  def handle_info({:drain, marker}, %{drain_timer: {_, marker}} = state) do
    state = %{state | drain_timer: nil}

    Enum.reduce_while(state.deferred, {:noreply, state}, fn {id, {key, values}},
                                                            {:noreply, acc} ->
      case consume_chunk(acc, id, key, values) do
        {:noreply, %{rpc: nil} = next} -> {:halt, {:noreply, next}}
        result -> {:cont, result}
      end
    end)
  end

  def handle_info({:t3_rpc, id, {kind, _}}, state) when kind in [:done, :error] do
    if Map.has_key?(state.ids, id),
      do: {:noreply, retry(state, :stream_ended)},
      else: {:noreply, state}
  end

  def handle_info({:EXIT, rpc, _}, %{rpc: rpc} = state) when is_pid(rpc),
    do: {:noreply, retry(state, :connection_closed)}

  def handle_info(_, state), do: {:noreply, state}

  defp establish(state) do
    Enum.reduce_while(state.streams, {:ok, state}, fn stream, {:ok, acc} ->
      cursor = Map.get(acc.cursors, stream.key)
      payload = subscription_payload(stream, cursor)

      with :ok <- catch_up(acc, stream),
           {:ok, id} <- RPC.subscribe(acc.rpc, stream.method, payload) do
        {:cont, {:ok, %{acc | ids: Map.put(acc.ids, id, stream.key)}}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp catch_up(state, %{catch_up: {method, payload}, key: key}) do
    payload = resolve_payload(payload, Map.get(state.cursors, key))

    with {:ok, value} <- RPC.call(state.rpc, method, payload) do
      :ok = state.callback.({:snapshot, key, value})
    end
  end

  defp catch_up(_, _), do: :ok

  defp retry(state, _reason) do
    close(state)
    # close/1 waits for the old RPC process to stop before discarding its messages.
    # Its request IDs may be reused by the next connection.
    flush_old_messages()
    :ok = state.callback.({:status, :disconnected})
    spread = round(state.delay * state.jitter)
    delay = state.delay + if(spread > 0, do: :rand.uniform(spread + 1) - 1, else: 0)
    delay = min(delay, state.max)
    if state.drain_timer, do: Process.cancel_timer(elem(state.drain_timer, 0))

    schedule(
      %{
        state
        | rpc: nil,
          ids: %{},
          deferred: %{},
          drain_timer: nil,
          delay: min(state.delay * 2, state.max)
      },
      delay
    )
  end

  defp schedule(state, delay) do
    marker = make_ref()
    timer = Process.send_after(self(), {:connect, marker}, delay)
    %{state | timer: {timer, marker}}
  end

  defp close(%{rpc: rpc}) when is_pid(rpc), do: RPC.close(rpc)
  defp close(_), do: :ok

  defp flush_old_messages do
    receive do
      {:t3_rpc, _, _} -> flush_old_messages()
    after
      0 -> :ok
    end
  end

  defp consume_chunk(state, id, key, values) do
    case state.callback.({:chunk, key, values}) do
      :ok ->
        state = commit_cursor(state, key, values)

        case RPC.ack(state.rpc, id) do
          :ok -> {:noreply, %{state | delay: state.min, deferred: Map.delete(state.deferred, id)}}
          {:error, reason} -> {:noreply, retry(state, reason)}
        end

      {:error, :busy} ->
        state = %{state | deferred: Map.put(state.deferred, id, {key, values})}
        {:noreply, schedule_drain(state)}
    end
  end

  defp schedule_drain(%{drain_timer: nil} = state) do
    marker = make_ref()
    timer = Process.send_after(self(), {:drain, marker}, state.consumer_retry)
    %{state | drain_timer: {timer, marker}}
  end

  defp schedule_drain(state), do: state

  defp commit_cursor(state, key, values) do
    if Map.has_key?(state.cursors, key) do
      previous = state.cursors[key]
      next = T3.RPC.Cursor.advance(previous, values)

      if next != previous do
        :ok = state.save_cursor.(key, next)
        %{state | cursors: Map.put(state.cursors, key, next)}
      else
        state
      end
    else
      state
    end
  end

  defp initial_cursors(streams, load) do
    Map.new(
      for stream <- streams, Map.get(stream, :resume, false) do
        loaded = load.(stream.key)

        seed =
          if is_nil(loaded),
            do: Map.get(resolve_payload(Map.get(stream, :payload, %{}), nil), "afterSequence"),
            else: loaded

        if not is_nil(seed) and not (is_integer(seed) and seed >= 0),
          do: raise(ArgumentError, "cursor must be a nonnegative integer or nil")

        {stream.key, seed}
      end
    )
  end

  defp subscription_payload(stream, cursor) do
    payload = resolve_payload(Map.get(stream, :payload, %{}), cursor)

    if Map.get(stream, :resume, false) and not is_nil(cursor),
      do: Map.put(payload, "afterSequence", cursor),
      else: payload
  end

  defp resolve_payload(payload, _cursor) when is_map(payload), do: payload
  defp resolve_payload(builder, cursor) when is_function(builder, 1), do: builder.(cursor)

  defp valid_payload?(payload), do: is_map(payload) or is_function(payload, 1)

  defp valid_stream?(%{key: _, method: method} = stream) when is_binary(method) do
    resume = Map.get(stream, :resume, false)

    valid_payload?(Map.get(stream, :payload, %{})) and is_boolean(resume) and
      (not resume or method in ["orchestration.subscribeShell", "orchestration.subscribeThread"]) and
      case Map.get(stream, :catch_up) do
        nil -> true
        {read, payload} -> is_binary(read) and valid_payload?(payload)
        _ -> false
      end
  end

  defp valid_stream?(_), do: false

  defp valid_health?(nil), do: true
  defp valid_health?({method, payload}), do: is_binary(method) and is_map(payload)
  defp valid_health?(_), do: false

  defp schedule_health(%{health: nil}), do: :ok

  defp schedule_health(state),
    do: Process.send_after(self(), {:health, state.rpc}, state.health_interval)

  @impl true
  def terminate(_, state), do: close(state)

  @impl true
  def format_status(status),
    do: %{status | state: %{reader: :redacted}, message: :redacted, reason: :redacted}
end
