defmodule T3.RPC.CursorTest do
  use ExUnit.Case, async: true
  alias T3.RPC.Cursor

  test "extracts thread and shell snapshots and unknown event sequences" do
    assert Cursor.sequence(%{"kind" => "snapshot", "snapshotSequence" => 10}) == 10

    assert Cursor.sequence(%{"kind" => "snapshot", "snapshot" => %{"snapshotSequence" => 11}}) ==
             11

    assert Cursor.sequence(%{
             "kind" => "event",
             "sequence" => 12,
             "event" => %{"type" => "future-event"}
           }) == 12

    assert Cursor.sequence(%{"kind" => "thread.updated", "sequence" => 13}) == 13
    assert Cursor.sequence(%{"kind" => "synchronized"}) == nil
  end

  test "project enrichment high-water cannot skip unconsumed replay" do
    enrichment = %{
      "kind" => "snapshot",
      "resolvedRepositoryIdentityRoots" => [],
      "snapshot" => %{"snapshotSequence" => 100}
    }

    assert Cursor.sequence(enrichment) == nil
    assert Cursor.advance(20, [enrichment]) == 20
    assert Cursor.advance(20, [enrichment, %{"kind" => "thread.updated", "sequence" => 21}]) == 21
  end

  test "chunk folding is monotonic, accepts zero and ignores invalid fields" do
    assert Cursor.advance(nil, %{"sequence" => 0}) == 0
    assert Cursor.sequence([%{"sequence" => 3}, %{"sequence" => 2}]) == 3

    assert Cursor.advance(7, [%{"sequence" => 3}, %{"sequence" => "9"}, %{"sequence" => -1}, nil]) ==
             7

    assert Cursor.advance(nil, []) == nil
  end
end
