defmodule T3.Workflows do
  @moduledoc """
  Durable workflow operations through MCP. Pass T3's original string-keyed argument maps.

  The T3 server owns workflow persistence and authorization; availability depends
  on the connected server and invocation context.
  """
  use T3.Toolset, category: :workflows
end
