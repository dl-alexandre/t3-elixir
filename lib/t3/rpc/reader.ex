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

  Catch-up reads run before subscriptions on each connection. T3's shell/thread
  streams start with an authoritative snapshot, covering changes between the
  read and subscription. Other protocols need their own cursor/snapshot strategy.
  Snapshots/events can repeat across reconnects; reducers must tolerate duplicates.
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

    if is_function(connect, 0) and is_function(callback, 1) and is_list(streams) and
         streams != [] and Enum.all?(streams, &valid_stream?/1) and
         length(Enum.uniq_by(streams, & &1.key)) == length(streams) and
         is_integer(min) and min > 0 and is_integer(max) and max >= min and
         is_number(jitter) and jitter >= 0 and jitter <= 1 and
         valid_health?(health) and is_integer(interval) and interval > 0 and
         is_integer(health_timeout) and health_timeout > 0 do
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
        health_timeout: health_timeout
      }

      {:ok, schedule(state, 0)}
    else
      {:stop, %T3.Error{kind: :configuration, message: "invalid RPC reader configuration"}}
    end
  end

  @impl true
  def handle_call(:status, _, state),
    do: {:reply, if(state.rpc, do: :connected, else: :disconnected), state}

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
      {:ok, key} ->
        :ok = state.callback.({:chunk, key, values})

        case RPC.ack(state.rpc, id) do
          :ok -> {:noreply, %{state | delay: state.min}}
          {:error, reason} -> {:noreply, retry(state, reason)}
        end

      :error ->
        {:noreply, state}
    end
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
      with :ok <- catch_up(acc, stream),
           {:ok, id} <- RPC.subscribe(acc.rpc, stream.method, Map.get(stream, :payload, %{})) do
        {:cont, {:ok, %{acc | ids: Map.put(acc.ids, id, stream.key)}}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp catch_up(state, %{catch_up: {method, payload}, key: key}) do
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
    schedule(%{state | rpc: nil, ids: %{}, delay: min(state.delay * 2, state.max)}, delay)
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

  defp valid_stream?(%{key: _, method: method} = stream) when is_binary(method) do
    is_map(Map.get(stream, :payload, %{})) and
      case Map.get(stream, :catch_up) do
        nil -> true
        {read, payload} -> is_binary(read) and is_map(payload)
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
