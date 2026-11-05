# A supervised local board reader

These helpers require `{:t3, "~> 0.2.0"}`; version 0.1.0 does not include them.

Use `T3.LocalAuth` and `T3.RPC.Reader` for a service that reads its own localhost
T3 installation. No browser or OAuth approval is needed at service startup. The
service OS account must already have access to the intended T3 data directory
and installed `t3` executable; this is the same local authority as the CLI.

## Supervision and board cache

This example keeps one cache for one host. Add a reader/auth pair per host, with
unique child IDs and names. Each node should authenticate to its own localhost
T3; aggregate normalized rows between your nodes separately.

```elixir
defmodule MyApp.BoardCache do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, %{}, opts)
  def init(rows), do: {:ok, rows}

  def handle_call({:consume, host, values}, _from, rows) do
    rows = T3.Board.apply(rows, values, host: host)
    # Broadcast normalized rows through your application's PubSub here.
    {:reply, :ok, rows}
  end

  def handle_call(:rows, _from, rows), do: {:reply, rows, rows}
end

host = "workstation"

consume = fn
  {:chunk, :shell, values} ->
    GenServer.call(MyApp.BoardCache, {:consume, host, values})

  {:status, _status} ->
    :ok
end

children = [
  {MyApp.BoardCache, name: MyApp.BoardCache},
  {T3.LocalAuth,
   name: MyApp.T3Auth,
   base_url: "http://127.0.0.1:3773",
   ttl: "24h",
   label: "board-reader",
   ticket: true},
  {T3.RPC.Reader,
   name: MyApp.T3Reader,
   connect: fn -> T3.LocalAuth.connection_options(MyApp.T3Auth) end,
   streams: [%{key: :shell, method: "orchestration.subscribeShell", payload: %{}}],
   on_event: consume,
   health_check: {"server.getConfig", %{}},
   health_interval: 30_000,
   health_timeout: 5_000}
]

Supervisor.start_link(children, strategy: :rest_for_one)
```

Put the children in your application's existing supervision tree. `rest_for_one`
restarts dependent readers if their auth/cache process restarts; do not put
unrelated application children after this group. `BoardCache` stores values keyed
by `{host, thread_id}`. Its values are `T3.Board.Thread` structs exposing
`thread_id`, `title`, `state`, `last_turn_at`, `last_message_snippet`, and `host`.
Your LiveView consumes these rows without interpreting wire events. Keep cache
consumption bounded; the callback runs inside the reader and must return `:ok`.
The reader sends the upstream ACK only after that return. A callback failure
stops the reader and lets supervision restart it.

The shell stream reflects T3's subscribed shell view, which may omit older settled
threads depending on its options; it is not a complete historical inventory.
The shell stream is the cheapest board-wide source and starts with an
authoritative snapshot on every subscription. Project-only enrichment messages
do not clear the cache. For an individual thread view instead of the shell view, use a stream map like this:

```elixir
thread_stream = %{
  key: {:thread, thread_id},
  method: "orchestration.subscribeThread",
  payload: %{"threadId" => thread_id},
  catch_up: {"orchestration.getThreadProjection", %{"threadId" => thread_id}}
}

consume = fn
  {:snapshot, {:thread, _id}, projection} ->
    GenServer.call(MyApp.BoardCache, {:consume, host, projection})

  {:chunk, _stream_key, values} ->
    GenServer.call(MyApp.BoardCache, {:consume, host, values})

  {:status, _status} ->
    :ok
end
```

Pass the stream in `:streams` and the matching callback in `:on_event`. Keep
shell and per-thread views in separate caches when consuming overlapping streams;
independent subscriptions do not supply one globally ordered event sequence. A thread
projection is more expensive than a shell row; subscribe only to threads whose
detail your board needs. See [actual payload shapes](BOARD_EVENTS.md).

## Recovery and credentials

A disconnect, stream completion, or failed health read closes the old connection
and re-creates all configured subscriptions with exponential backoff and jitter.
The credential callback runs once per attempt. LocalAuth caches the underlying
session, renews near expiry when asked for options, and creates a fresh
RPC bearer ticket for each attempt by default. It revokes sessions it replaces and attempts to
revoke its session on orderly shutdown. Abrupt termination still leaves the TTL
as the lifetime bound. Choose `:base_dir` and `:cli` explicitly when the service
account has different home/PATH settings. Never log the connection options.

Only configured catch-up reads are repeated. They run before subscriptions; T3's
initial stream snapshot then supplies authoritative current state, including
changes since the read. Snapshots/events may repeat across reconnects; intermediate
events while offline are not durably replayed. This is a current-state board,
not an audit log. `T3.RPC` itself still never retries arbitrary commands.

If an operator revokes a cached session, explicitly call
`T3.LocalAuth.invalidate/1` before retrying; do not automatically circumvent
intentional revocation. External services must use their authorized environment
credentials instead of this local CLI provider.

## Raw subscription and ACK pattern

For short scripts that do not need reconnect management:

```elixir
{:ok, options} = T3.LocalAuth.connection_options(MyApp.T3Auth)
{:ok, rpc} = T3.RPC.start_link(options)
{:ok, id} = T3.RPC.subscribe(rpc, "orchestration.subscribeShell", %{})

receive do
  {:t3_rpc, ^id, {:chunk, values}} ->
    rows = T3.Board.apply(%{}, values, host: "workstation")
    IO.puts("Received #{map_size(rows)} board rows")
    :ok = T3.RPC.ack(rpc, id)

  {:t3_rpc, ^id, {:done, _}} ->
    :ok

  {:t3_rpc, ^id, {:error, error}} ->
    IO.puts(Exception.message(error))
after
  5_000 -> :ok
end

:ok = T3.RPC.unsubscribe(rpc, id)
:ok = T3.RPC.close(rpc)
```

For continuous consumption, receive in a loop and retain the cache between
chunks. ACK each consumed chunk; do not ACK before processing or leave chunks
unacknowledged while awaiting more data. Reusable bearer tickets may be cached explicitly until expiry; never reuse a
DPoP proof. See [ticket caching](AUTHENTICATION.md). Low-level subscriptions default to an infinite stream deadline;
unary reads retain their finite call deadline.

## Optional bounded asynchronous work

The queue and busy-admission protocol require the unreleased 0.3.0 checkout.

The default synchronous callback ACKs after processing. For best-effort work
that can be reconciled from a later snapshot, put a `T3.RPC.WorkQueue` before the
reader in your supervisor. `MyApp.WorkErrors` must be an existing registered
process that handles `{:t3_work_queue, queue, {:failed, event}}` notifications:

```elixir
queue_child = {T3.RPC.WorkQueue,
  name: MyApp.T3Work,
  owner: MyApp.WorkErrors,
  capacity: 32,
  work_timeout: 30_000,
  work: fn {:chunk, _key, values} ->
    MyApp.SlowConsumer.consume(values)
    :ok
  end}

consume = fn
  {:chunk, _, _} = event -> T3.RPC.WorkQueue.enqueue(MyApp.T3Work, event)
  {:snapshot, _key, value} -> MyApp.SlowConsumer.consume_snapshot(value); :ok
  {:status, _} -> :ok
end
```

Set this callback on the reader. Admission is non-blocking; a full queue returns
`{:error, :busy}`. The reader retains the chunk without ACK and retries admission
while continuing to handle health/status messages. Queue capacity includes the
single active worker and all waiting work. Each stream has at most one deferred
chunk. Order is preserved within a stream and by queue admission, not globally
across independent streams.

Once admitted, the reader ACKs and may checkpoint **before execution**. The
queue is bounded memory, not durable: a queue restart loses accepted work; worker
failure/timeout notifies its owner and continues without automatic retries.
Slow work should have idempotent effects and reconciliation. For audit/billing,
keep the synchronous callback and durably enqueue/process data and checkpoint
transactionally before returning `:ok`. Catch-up/status callbacks still need to
return promptly. Do not enable durable cursor persistence with this memory queue
and assume processing is durable.

See [resume cursors, ordering and full inventory](STREAM_CONTRACT.md) for the
supported `afterSequence`, completeness flags and replay limitations.
