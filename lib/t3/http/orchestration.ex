defmodule T3.HTTP.Orchestration do
  @moduledoc "Named access to T3 HTTP orchestration routes. Options accept wire-map JSON/form bodies, query and headers."
  @doc "GET `/api/orchestration/shell`. Body encoding: none."
  def shell_snapshot(client, opts \\ []),
    do: T3.HTTP.call(client, :orchestration_shell_snapshot, opts)

  @doc "GET `/api/orchestration/threads/:threadId`. Body encoding: none."
  def thread_snapshot(client, param_threadId, opts \\ []),
    do:
      T3.HTTP.call(
        client,
        :orchestration_thread_snapshot,
        Keyword.put(opts, :params, %{"threadId" => param_threadId})
      )

  @doc "GET `/api/orchestration/threads/:threadId/transcript`. Body encoding: none."
  def thread_transcript(client, param_threadId, opts \\ []),
    do:
      T3.HTTP.call(
        client,
        :orchestration_thread_transcript,
        Keyword.put(opts, :params, %{"threadId" => param_threadId})
      )

  @doc "GET `/api/orchestration/threads/:threadId/bounded`. Body encoding: none."
  def thread_bounded_snapshot(client, param_threadId, opts \\ []),
    do:
      T3.HTTP.call(
        client,
        :orchestration_thread_bounded_snapshot,
        Keyword.put(opts, :params, %{"threadId" => param_threadId})
      )

  @doc "GET `/api/orchestration/threads/:threadId/history`. Body encoding: none."
  def thread_history_page(client, param_threadId, opts \\ []),
    do:
      T3.HTTP.call(
        client,
        :orchestration_thread_history_page,
        Keyword.put(opts, :params, %{"threadId" => param_threadId})
      )
end
