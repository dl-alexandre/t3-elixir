defmodule T3.Requests do
  @moduledoc """
  Requests MCP operations. Pass T3's original string-keyed argument maps.

  Tool availability depends on the authenticated server, permission mode and
  invocation context. In-app agent tools may not be available to outside clients.
  See `T3.Catalog.tools(:requests)` for descriptions and context requirements.
  """
  use T3.Toolset, category: :requests
end
