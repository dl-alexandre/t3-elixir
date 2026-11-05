defmodule T3.Schedules do
  @moduledoc """
  Schedules MCP operations. Pass T3's original string-keyed argument maps.

  Tool availability depends on the authenticated server, permission mode and
  invocation context. In-app agent tools may not be available to outside clients.
  See `T3.Catalog.tools(:schedules)` for descriptions and context requirements.
  """
  use T3.Toolset, category: :schedules
end
