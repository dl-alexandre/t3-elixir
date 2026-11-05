defmodule T3.RPC.Cursor do
  @moduledoc """
  Extract T3 orchestration resume sequences without interpreting event bodies.

  `sequence/1` reads an event's `sequence`, a thread snapshot's
  `snapshotSequence`, or a shell snapshot's nested `snapshotSequence`. Arrays
  return their highest eligible sequence. Unknown event bodies still advance a
  cursor. Missing/invalid sequence fields and completion markers return `nil`.

  Project-enrichment shell snapshots marked `resolvedRepositoryIdentityRoots`
  are always ignored: their high-water may precede replayed events on the wire.
  Advancing from that marker can skip replay if a consumer crashes partway.

  `advance/2` is monotonic. Commit the result only after consuming the entire
  chunk (and, for durable consumers, storing the corresponding application
  changes). A cursor alone does not make T3 replay durable: the server can fall
  back to a current-state snapshot when history is pruned or over its replay
  budget. Scope stored cursors to the environment and subscription/filter set.
  """

  @type t :: non_neg_integer() | nil

  @doc "Return the highest resumable sequence in a stream item or chunk array."
  @spec sequence(term()) :: t()
  def sequence(%{"resolvedRepositoryIdentityRoots" => _}), do: nil

  def sequence(%{"sequence" => value}) when is_integer(value) and value >= 0, do: value

  def sequence(%{"snapshotSequence" => value}) when is_integer(value) and value >= 0,
    do: value

  def sequence(%{"kind" => "snapshot", "snapshot" => snapshot}), do: sequence(snapshot)
  def sequence(values) when is_list(values), do: advance(nil, values)
  def sequence(_), do: nil

  @doc "Advance an existing cursor after consuming items; never moves backwards."
  @spec advance(t(), term()) :: t()
  def advance(cursor, values) when is_nil(cursor) or (is_integer(cursor) and cursor >= 0) do
    Enum.reduce(List.wrap(values), cursor, fn item, current ->
      case sequence(item) do
        nil -> current
        candidate when is_nil(current) -> candidate
        candidate -> max(current, candidate)
      end
    end)
  end
end
