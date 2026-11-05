defmodule T3.Tasks do
  @moduledoc """
  Delegated-task and background-work operations.

  Most require a T3-launched agent/thread context; an external OAuth sign-in may
  not advertise these tools. Use `T3.Catalog.discover/1` to check actual availability.
  """
  alias T3.Client
  use T3.Toolset, category: :tasks, except: [:capabilities, :delegate, :status, :cancel]

  def capabilities(client, args \\ %{}),
    do: Client.call_tool(client, "orchestrator_capabilities", args)

  def delegate(client, args) when is_map(args),
    do: Client.call_tool(client, "delegate_task", args)

  def delegate(client, task), do: delegate(client, task, %{})

  def delegate(client, task, args),
    do: Client.call_tool(client, "delegate_task", Map.put(args, "task", task))

  def status(client, args) when is_map(args), do: Client.call_tool(client, "task_status", args)
  def status(client, id), do: Client.call_tool(client, "task_status", %{"taskId" => id})
  def cancel(client, args) when is_map(args), do: Client.call_tool(client, "task_cancel", args)
  def cancel(client, id), do: cancel(client, id, %{})

  def cancel(client, id, args),
    do: Client.call_tool(client, "task_cancel", Map.put(args, "taskId", id))
end
