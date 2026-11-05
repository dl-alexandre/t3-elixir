defmodule T3.BoardTest do
  use ExUnit.Case, async: true
  alias T3.Board
  alias T3.Board.Thread

  test "shell snapshot replaces one host and ignores project-only enrichment" do
    rows = %{
      {"other", "same"} => %Thread{thread_id: "same", host: "other"},
      {"local", "gone"} => %Thread{thread_id: "gone", host: "local"}
    }

    snapshot = %{
      "kind" => "snapshot",
      "snapshot" => %{
        "threads" => [
          %{
            "id" => "same",
            "title" => "Current",
            "status" => "waiting",
            "latestVisibleMessage" => %{"text" => " hello\n world "}
          }
        ],
        "archivedThreads" => [
          %{"id" => "old", "title" => "Archived", "archivedAt" => "2026-11-05T00:00:00Z"}
        ]
      }
    }

    rows = Board.apply(rows, [snapshot], host: "local")
    assert map_size(rows) == 3
    refute Map.has_key?(rows, {"local", "gone"})
    assert rows[{"local", "same"}].last_message_snippet == "hello world"
    assert rows[{"local", "same"}].state == "waiting"
    assert rows[{"local", "old"}].state == "archived"

    enrichment = %{
      "kind" => "snapshot",
      "resolvedRepositoryIdentityRoots" => ["/redacted"],
      "snapshot" => %{"threads" => [], "archivedThreads" => [], "projects" => []}
    }

    assert Board.apply(rows, [enrichment], host: "local") == rows

    assert Board.apply(rows, %{"threads" => [], "archivedThreads" => []}, host: "local") == %{
             {"other", "same"} => rows[{"other", "same"}]
           }
  end

  test "thread projection derives state, latest turn activity and Unicode-safe snippet" do
    projection = %{
      "thread" => %{"id" => "thread", "title" => "Title"},
      "runs" => [
        %{"ordinal" => 2, "status" => "running", "startedAt" => "2026-11-05T01:00:00Z"},
        %{"ordinal" => 1, "status" => "completed", "startedAt" => "2026-11-04T01:00:00Z"}
      ],
      "providerTurns" => [%{"completedAt" => "2026-11-05T01:01:00Z"}],
      "messages" => [
        %{
          "id" => "m1",
          "createdAt" => "2026-11-04T01:00:00Z",
          "updatedAt" => "2026-11-05T03:00:00Z",
          "text" => "old"
        },
        %{
          "id" => "m2",
          "createdAt" => "2026-11-05T01:00:00Z",
          "updatedAt" => "2026-11-05T01:00:00Z",
          "text" => " 👩🏽‍💻  new text "
        }
      ]
    }

    rows =
      Board.apply(%{}, [%{"kind" => "snapshot", "projection" => projection}],
        host: "local",
        snippet_length: 5
      )

    assert %Thread{
             thread_id: "thread",
             title: "Title",
             state: "running",
             host: "local",
             last_turn_at: "2026-11-05T01:01:00Z",
             last_message_snippet: "👩🏽‍💻 new"
           } = rows[{"local", "thread"}]
  end

  test "ordered sparse thread events retain absent fields and remove deleted rows" do
    row = %Thread{
      thread_id: "t",
      host: "h",
      title: "Before",
      state: "running",
      last_message_snippet: "keep"
    }

    events = [
      %{
        "kind" => "event",
        "event" => %{
          "type" => "thread.metadata-updated",
          "threadId" => "t",
          "payload" => %{"id" => "t", "title" => "After"}
        }
      },
      %{
        "kind" => "event",
        "event" => %{
          "type" => "run.updated",
          "threadId" => "t",
          "payload" => %{"status" => "completed", "completedAt" => "2026-11-05T02:00:00Z"}
        }
      },
      %{"kind" => "synchronized"},
      %{"kind" => "unknown-event", "sequence" => 99}
    ]

    rows = Board.apply(%{{"h", "t"} => row}, events, host: "h")

    assert %Thread{title: "After", state: "completed", last_message_snippet: "keep"} =
             rows[{"h", "t"}]

    assert Board.apply(rows, %{"kind" => "thread.removed", "threadId" => "t"}, host: "h") == %{}

    assert Board.apply(
             rows,
             %{"kind" => "event", "event" => %{"type" => "thread.deleted", "threadId" => "t"}},
             host: "h"
           ) == %{}
  end

  test "stateless operations retain explicit empty message text and do not create dynamic atoms" do
    chunk = [
      %{
        "kind" => "event",
        "event" => %{"type" => "message.updated", "threadId" => "t", "payload" => %{"text" => ""}}
      }
    ]

    assert [{:upsert, %Thread{thread_id: "t", last_message_snippet: "", host: "h", title: nil}}] =
             Board.normalize(chunk, host: "h")

    assert Board.normalize(
             [%{"kind" => "event", "event" => %{"type" => "future.event", "payload" => %{}}}],
             host: "h"
           ) == []
  end

  test "older run and historical message edits do not replace the current board summary" do
    projection = %{
      "thread" => %{"id" => "t", "title" => "Current"},
      "runs" => [
        %{
          "id" => "r2",
          "ordinal" => 2,
          "status" => "running",
          "requestedAt" => "2026-11-05T02:00:00Z"
        }
      ],
      "messages" => [
        %{
          "id" => "m2",
          "createdAt" => "2026-11-05T02:00:00Z",
          "updatedAt" => "2026-11-05T02:00:00Z",
          "text" => "latest message"
        }
      ]
    }

    rows = Board.apply(%{}, projection, host: "h")

    events = [
      %{
        "kind" => "event",
        "event" => %{
          "type" => "run.updated",
          "threadId" => "t",
          "payload" => %{
            "id" => "r1",
            "ordinal" => 1,
            "status" => "completed",
            "requestedAt" => "2026-11-05T01:00:00Z",
            "completedAt" => "2026-11-05T03:00:00Z"
          }
        }
      },
      %{
        "kind" => "event",
        "event" => %{
          "type" => "message.updated",
          "threadId" => "t",
          "payload" => %{
            "id" => "m1",
            "createdAt" => "2026-11-05T01:00:00Z",
            "updatedAt" => "2026-11-05T03:00:00Z",
            "text" => "historical edit"
          }
        }
      }
    ]

    rows = Board.apply(rows, events, host: "h")
    assert rows[{"h", "t"}].state == "running"
    assert rows[{"h", "t"}].last_message_snippet == "latest message"
    assert rows[{"h", "t"}].last_turn_at == "2026-11-05T03:00:00Z"

    same_message = %{
      "kind" => "event",
      "event" => %{
        "type" => "message.updated",
        "threadId" => "t",
        "payload" => %{
          "id" => "m2",
          "createdAt" => "2026-11-05T02:00:00Z",
          "updatedAt" => "2026-11-05T04:00:00Z",
          "text" => "latest edit"
        }
      }
    }

    rows = Board.apply(rows, same_message, host: "h")
    assert rows[{"h", "t"}].last_message_snippet == "latest edit"

    new_run = %{
      "kind" => "event",
      "event" => %{
        "type" => "run.created",
        "threadId" => "t",
        "payload" => %{
          "id" => "r3",
          "ordinal" => 3,
          "status" => "queued",
          "requestedAt" => "2026-11-05T04:00:00Z"
        }
      }
    }

    assert Board.apply(rows, new_run, host: "h")[{"h", "t"}].state == "queued"
    refute inspect(rows[{"h", "t"}]) =~ "__meta__"
  end

  test "shell summary tracks run IDs and keeps archive state through late run events" do
    rows =
      Board.apply(
        %{},
        %{
          "kind" => "thread.updated",
          "thread" => %{
            "id" => "t",
            "latestRunId" => "new",
            "latestRunRequestedAt" => "2026-11-05T02:00:00Z",
            "status" => "running",
            "archivedAt" => "2026-11-05T02:30:00Z",
            "latestVisibleMessage" => %{
              "id" => "m2",
              "updatedAt" => "2026-11-05T02:00:00Z",
              "text" => "latest"
            }
          }
        },
        host: "h"
      )

    event = %{
      "kind" => "event",
      "event" => %{
        "type" => "run.updated",
        "threadId" => "t",
        "payload" => %{
          "id" => "old",
          "ordinal" => 1,
          "requestedAt" => "2026-11-05T01:00:00Z",
          "status" => "completed"
        }
      }
    }

    rows = Board.apply(rows, event, host: "h")
    assert rows[{"h", "t"}].state == "archived"
    assert rows[{"h", "t"}].__meta__.run.id == "new"
  end
end
