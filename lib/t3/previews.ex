defmodule T3.Previews do
  @moduledoc """
  Previews MCP operations. Pass T3's original string-keyed argument maps.

  Tool availability depends on the authenticated server, permission mode and
  invocation context. In-app agent tools may not be available to outside clients.
  See `T3.Catalog.tools(:previews)` for descriptions and context requirements.
  """
  use T3.Toolset, category: :previews
end
