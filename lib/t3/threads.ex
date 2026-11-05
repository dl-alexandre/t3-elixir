defmodule T3.Threads do
  @moduledoc """
  Thread MCP operations with original string-keyed arguments.

  Outside clients have no implicit project: supply `projectId` where required.
  Every operation also has an exact wire-name counterpart in `T3.Tools`.
  Existing ID/message convenience signatures remain available.
  """
  alias T3.Client
  use T3.Toolset, category: :threads, except: [:list, :read, :search, :launch, :send, :interrupt]

  def list(client, args \\ %{}), do: Client.call_tool(client, "t3_thread_list", args)
  def read(client, args) when is_map(args), do: Client.call_tool(client, "t3_thread_read", args)
  def read(client, id), do: read(client, id, %{})

  def read(client, id, args),
    do: Client.call_tool(client, "t3_thread_read", Map.put(args, "threadId", id))

  def search(client, args) when is_map(args),
    do: Client.call_tool(client, "t3_thread_search", args)

  def search(client, query), do: search(client, query, %{})

  def search(client, query, args),
    do: Client.call_tool(client, "t3_thread_search", Map.put(args, "query", query))

  def launch(client, args) when is_map(args),
    do: Client.call_tool(client, "t3_thread_launch", args)

  def launch(client, title), do: launch(client, title, %{})

  def launch(client, title, args),
    do: Client.call_tool(client, "t3_thread_launch", Map.put(args, "title", title))

  def send(client, args) when is_map(args), do: Client.call_tool(client, "t3_thread_send", args)

  def send(client, id, message, args \\ %{}),
    do:
      Client.call_tool(
        client,
        "t3_thread_send",
        Map.merge(args, %{"threadId" => id, "message" => message})
      )

  def interrupt(client, args) when is_map(args),
    do: Client.call_tool(client, "t3_thread_interrupt", args)

  def interrupt(client, id), do: interrupt(client, id, %{})

  def interrupt(client, id, args),
    do: Client.call_tool(client, "t3_thread_interrupt", Map.put(args, "threadId", id))
end
