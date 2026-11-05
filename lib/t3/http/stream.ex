defmodule T3.HTTP.Stream do
  @moduledoc """
  Bounded HTTP response streaming with callback backpressure and cancellation.

  `run/5` returns `{:ok, summary}` or `{:error, %T3.Error{}}`. Its callback runs
  in an isolated worker and receives `{:status, integer}`, `{:headers, pairs}`,
  and `{:data, binary}`. Return `:cont` or `:halt` (a successful early stop).
  The worker waits for the callback before reading more bytes. Capture the
  caller PID explicitly when forwarding events; `self()` inside the callback
  is the worker PID. MJPEG, AVCC, files and other binary data are unchanged.

  With `mode: :sse`, `{:event, %ConduitMcp.Client.SSE.Event{}}` replaces data
  callbacks. Parsing uses Conduit's incremental parser; heartbeats/comments
  do not generate events, incomplete trailing events are discarded. Event
  data is left as text so callers choose JSON decoding. Reconnect/resume is
  explicit: there are no retries or automatic Last-Event-ID requests.

  Options include `:timeout` (hard wall-clock deadline, default client timeout),
  `:idle_timeout`, `:max_bytes`, `:max_events`, `:max_event_bytes`, and ordinary
  HTTP request options. All bounds must be positive integers. A hard deadline
  also stops a blocked callback. Defaults: 16 MiB total bytes (client body cap),
  10,000 data deliveries/events, 1 MiB per SSE event/line.

      task = T3.HTTP.start_stream(http, :get, "/api/guest/stream", callback,
        query: %{"share" => share_id}, mode: :sse, timeout: 60_000)
      # Consume the result with Task.await/2, or cancel from its owner process:
      T3.HTTP.cancel_stream(task)
  """
  alias T3.Error
  alias ConduitMcp.Client.SSE

  defmodule Summary do
    @moduledoc "Counters and response metadata after stream completion or callback halt."
    @derive {Inspect, only: [:status, :bytes, :events, :halted?]}
    defstruct [:status, headers: [], bytes: 0, events: 0, halted?: false, last_event_id: nil]
  end

  @doc "Run a bounded stream. The callback must return :cont or :halt."
  def run(client, method, path, callback, opts \\ []) when is_function(callback, 1) do
    timeout = positive!(opts, :timeout, client.timeout)
    task = Task.async(fn -> consume(client, method, path, callback, opts) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, %Error{kind: :timeout, message: "HTTP stream exceeded its deadline"}}
    end
  end

  @doc "Start a Task. Await or cancel it from the process that called start/5."
  def start(client, method, path, callback, opts \\ []),
    do: Task.async(fn -> run(client, method, path, callback, opts) end)

  @doc "Stop an owned streaming Task, including its linked network worker."
  def cancel(%Task{} = task) do
    Task.shutdown(task, :brutal_kill)
    :ok
  end

  defp consume(client, method, path, callback, opts) do
    mode = Keyword.get(opts, :mode, :raw)
    unless mode in [:raw, :sse], do: raise(ArgumentError, "stream mode must be :raw or :sse")
    bytes = positive!(opts, :max_bytes, client.max_body_bytes)
    events = positive!(opts, :max_events, 10_000)
    event_bytes = positive!(opts, :max_event_bytes, 1_048_576)
    timeout = positive!(opts, :idle_timeout, client.timeout)

    with {:ok, request} <- T3.HTTP.prepare_request(client, method, path, opts) do
      initial = %{
        summary: %Summary{},
        error: nil,
        parser: SSE.new(max_line_bytes: event_bytes, max_event_bytes: event_bytes)
      }

      result =
        Finch.stream_while(
          request,
          client.finch,
          initial,
          fn event, acc ->
            receive_event(event, acc, callback, mode, bytes, events)
          end,
          receive_timeout: timeout,
          request_timeout: positive!(opts, :timeout, client.timeout),
          pool_timeout: client.pool_timeout
        )

      finish(result)
    end
  rescue
    exception ->
      {:error,
       %Error{kind: :stream, message: "HTTP stream or callback failed", details: exception}}
  catch
    kind, reason ->
      {:error,
       %Error{kind: :stream, message: "HTTP stream worker failed", details: {kind, reason}}}
  end

  defp receive_event({:status, status} = event, acc, callback, _, _, _) do
    acc = put_in(acc.summary.status, status)

    if status in 200..299 do
      deliver(event, acc, callback)
    else
      {:halt, %{acc | error: %Error{kind: :http, code: status, message: "T3 HTTP #{status}"}}}
    end
  end

  defp receive_event({:headers, headers} = event, acc, callback, _, _, _) do
    acc = put_in(acc.summary.headers, acc.summary.headers ++ headers)
    deliver(event, acc, callback)
  end

  defp receive_event({:data, data}, acc, callback, mode, max_bytes, max_events) do
    acc = put_in(acc.summary.bytes, acc.summary.bytes + byte_size(data))

    cond do
      acc.summary.bytes > max_bytes ->
        fail(acc, "HTTP stream exceeded max_bytes")

      mode == :sse ->
        case SSE.feed(acc.parser, data) do
          {:ok, events, parser} ->
            acc = %{acc | parser: parser}

            Enum.reduce_while(events, {:cont, acc}, fn event, {:cont, acc} ->
              case data_event({:event, event}, acc, callback, max_events) do
                {:cont, acc} -> {:cont, {:cont, acc}}
                {:halt, acc} -> {:halt, {:halt, acc}}
              end
            end)

          {:error, _, _} ->
            fail(acc, "HTTP SSE event exceeded max_event_bytes")
        end

      true ->
        data_event({:data, data}, acc, callback, max_events)
    end
  end

  defp receive_event(_, acc, _, _, _, _), do: {:cont, acc}

  defp data_event(event, acc, callback, limit) do
    if acc.summary.events >= limit do
      fail(acc, "HTTP stream exceeded max_events")
    else
      acc = put_in(acc.summary.events, acc.summary.events + 1)

      last_id =
        case event do
          {:event, decoded} -> decoded.id
          _ -> acc.summary.last_event_id
        end

      acc = put_in(acc.summary.last_event_id, last_id)
      deliver(event, acc, callback)
    end
  end

  defp deliver(event, acc, callback) do
    case callback.(event) do
      :cont -> {:cont, acc}
      :halt -> {:halt, put_in(acc.summary.halted?, true)}
      _ -> fail(acc, "stream callback must return :cont or :halt")
    end
  end

  defp fail(acc, message), do: {:halt, %{acc | error: %Error{kind: :protocol, message: message}}}
  defp finish({:ok, %{error: nil} = acc}), do: {:ok, acc.summary}
  defp finish({:ok, %{error: error}}), do: {:error, error}

  defp finish({:error, reason, _acc}),
    do: {:error, %Error{kind: :transport, message: "HTTP stream failed", details: reason}}

  defp finish({:error, reason}),
    do: {:error, %Error{kind: :transport, message: "HTTP stream failed", details: reason}}

  defp positive!(opts, key, default) do
    value = Keyword.get(opts, key, default)

    unless is_integer(value) and value > 0,
      do: raise(ArgumentError, "#{key} must be a positive integer")

    value
  end
end
