# Resume cursors, ordering and inventory

The Reader checkpoint hooks and Cursor helper are new in the unreleased 0.3.0
checkout. Low-level wire payload options also work in earlier SDK versions.

The pinned T3 contract supports resumable subscriptions, but they remain
state-oriented streams. A resume request can fall back to a current snapshot;
it is not a durable event-log export for audit or billing.

## Resume the supported streams

Both `orchestration.subscribeThread` and `orchestration.subscribeShell` accept
`afterSequence`, a nonnegative integer. The thread input also requires
`threadId`. A cursor means events **after** that sequence, not including it.
Request `requestCompletionMarker: true` to receive `{"kind":"synchronized"}`
after the initial snapshot or replay, before the live tail.

```elixir
{:ok, id} = T3.RPC.subscribe(rpc, "orchestration.subscribeThread", %{
  "threadId" => thread_id,
  "afterSequence" => last_consumed_sequence,
  "requestCompletionMarker" => true
})
```

The normal unary `orchestration.getThreadProjection` input only accepts
`threadId`; it does not support an `after`, `cursor` or `afterSequence` gap query.
Pass `afterSequence` on the subscription instead. The SDK preserves caller
subscription payloads, including supported completeness and representation
options. Do not add cursor parameters to unrelated catch-up methods.

For a reconnecting reader, opt in per stream:

```elixir
stream = %{
  key: {:thread, thread_id},
  method: "orchestration.subscribeThread",
  payload: %{"threadId" => thread_id, "requestCompletionMarker" => true},
  resume: true
}

reader_options = [
  connect: connect,
  streams: [stream],
  on_event: consume,
  load_cursor: fn key -> MyApp.Cursors.load({environment_id, key}) end,
  save_cursor: fn key, sequence ->
    MyApp.Cursors.save({environment_id, key}, sequence)
    :ok
  end
]
```

The load hook returns an integer or `nil`; the save hook returns `:ok`. Scope
stored cursors to the environment, thread and subscription/filter options. Never
reuse a sequence from another T3 data directory or after changing the represented
view without an authoritative snapshot. Retain the application state that the
cursor represents. A cursor alone cannot rebuild an empty cache when the server
replays only newer changes.

`T3.RPC.Cursor.sequence/1` extracts eligible sequences from stream items or chunk
arrays. `advance/2` advances a checkpoint monotonically. Event items carry
`sequence`; thread snapshots carry `snapshotSequence`; shell snapshots carry it
inside `snapshot`. Unknown event bodies still count toward the checkpoint. A
`synchronized` marker carries no sequence.

Project-only shell enrichment snapshots marked
`resolvedRepositoryIdentityRoots` must **not** advance a resume cursor. During
resume, that enrichment can advertise the server high-water before the replay
arrives. Checkpointing it can skip unconsumed replay after a crash. The Cursor
helper ignores marked enrichment snapshots, even if their sequence is higher.

With synchronous processing, consume the whole chunk before checkpointing and
ACK. Durable consumers should make processing idempotent and persist application
changes/checkpoints with appropriate transaction semantics. A crash between
separate application and checkpoint writes can cause duplicate work. A memory
queue or early ACK is not durable storage; a persisted cursor must not get ahead
of work that would be lost when that queue dies. Choose either current-state
catch-up snapshots or incremental resume for one cache. Combining a newer unary
snapshot with replay from an older cursor can reapply older state; an application
must reconcile snapshot sequences explicitly before combining those strategies.

## Replay limits and fallback

At pinned upstream revision
`337c5858c33bc7f8f6dfd391a2c279fa0f7e4d17`:

- Thread replay is bounded to 128 persisted replay events, 1 MiB of raw payload,
  and 1 MiB of encoded projected replay. An out-of-range cursor, pruned gap,
  excessive replay, or retained thread-creation condition can cause a snapshot.
- Shell replay is bounded to a sequence gap of 1,000 and 8 MiB of raw persisted
  payload. Future cursors, pruned history and over-budget ranges cause a snapshot.
- Thread replay coalesces live-update records. Shell replay projects application
  events into current shell summaries and suppresses unchanged rows. Unknown
  event types can be skipped for forward compatibility.

Always handle a snapshot on reconnect, even when sending a cursor. That is
current-state reconciliation, not evidence that every missed intermediate event
was delivered. The SDK does not invent a durable `getEventsAfter` API that T3
has not exposed. Audit, billing and exact historical transition processing need
an explicitly durable server source with retention/export guarantees.

A read-only live probe against local T3 Code 0.1.1 on 2026-11-05 confirmed:

- A shell re-subscription at its consumed snapshot sequence returned a marked
  project-only snapshot followed by `synchronized`, with no authoritative snapshot.
- A thread re-subscription at its consumed snapshot sequence returned
  `synchronized` without a replacement snapshot.
- Explicit `omitIdleSubagents: false` / `omitOlderSettled: false` was accepted.

The probe generated no thread mutations; replay of missed mutation events was
checked against the pinned server implementation rather than synthesized live.
Its temporary read-only local session was revoked.

## Sequence markers and cross-stream ordering

Thread events and shell deltas expose sequences from T3's application event
store, making related activity comparable within one environment. Initial
snapshots expose the sequence through which they represent state. These markers
are useful for deduplication and causal diagnostics; they do not impose delivery
order between independently subscribed streams.

A shell summary can arrive before the corresponding thread event. A thread
stream filters other threads; shell streams coalesce/suppress updates and merge
project enrichment. Sequence numbers therefore need not be contiguous in either
stream. `synchronized` ends initial catch-up but contains no numeric live
watermark. A library merge buffer cannot know from silence that a missing number
will never arrive. No generic cross-stream total-order guarantee is claimed.
Use one authoritative stream for each board cache. Consumers needing strict
ordering must define the required stream set, acceptable omissions, buffer bound
and server watermark/barrier protocol; sorting by timestamp alone is insufficient.

## Choose completeness versus cost

The shell stream's `payload` accepts these options directly:

```elixir
full_active_shell = %{
  key: :shell,
  method: "orchestration.subscribeShell",
  payload: %{
    "omitIdleSubagents" => false,
    "omitOlderSettled" => false,
    "requestCompletionMarker" => true
  }
}
```

At the pinned revision, omission occurs only when the corresponding flag is
`true`; absent/false leaves those active rows included. Send the options only to
servers advertising `shellThreadFamilies` / `shellOlderSettled` in
`server.getConfig`. Do not infer completeness from a mobile/UI client's chosen
subscription settings.

The initial shell snapshot covers the **active** shell. A complete inventory
including archived threads needs the separate archive read:

```elixir
{:ok, archived} = T3.RPC.call(rpc, "orchestration.getArchivedShellSnapshot", %{})
{:ok, family} = T3.RPC.call(rpc, "orchestration.getThreadFamily", %{"threadId" => thread_id})
```

When omission is enabled, `getThreadFamily` restores idle family members;
`getOlderSettledThreads` pages omitted settled rows. Its `before` cursor contains
`settledAt` and optionally `threadId`, with `limit` from 0 through 50. A limit of
zero returns counts. For the next page, use the last returned row's settle time
and ID. These pagination cursors are not stream event cursors, and separate
reads can see concurrent changes rather than one frozen inventory transaction.

Per-thread `acceptBoundedSnapshot` returns a bounded history window with opaque
`historyCursor` / `hasMoreHistory`. Fetch older pages with the HTTP thread
history route and keep that cursor opaque. It is distinct from `afterSequence`:
one pages transcript history; the other resumes stream changes. The thin board
normalizer expects ordinary full bodies, so do not enable compact/deduped/deferred
representations unless the caller restores them first.

## Pinned primary sources

- [Subscription inputs and stream records](https://github.com/pingdotgg/t3code/blob/337c5858c33bc7f8f6dfd391a2c279fa0f7e4d17/packages/contracts/src/orchestrationV2.ts).
- [Replay, fallback and shell subscription implementation](https://github.com/pingdotgg/t3code/blob/337c5858c33bc7f8f6dfd391a2c279fa0f7e4d17/apps/server/src/ws.ts).
- [Thread replay budgets](https://github.com/pingdotgg/t3code/blob/337c5858c33bc7f8f6dfd391a2c279fa0f7e4d17/apps/server/src/orchestration-v2/ThreadStream.ts).
- [Shell projection and enrichment](https://github.com/pingdotgg/t3code/blob/337c5858c33bc7f8f6dfd391a2c279fa0f7e4d17/apps/server/src/orchestration-v2/ShellStream.ts).
