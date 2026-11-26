defmodule T3.Issues do
  @moduledoc """
  Issue tracker operations through MCP. Pass T3's original string-keyed argument maps.

  Availability and target requirements depend on the authenticated server and
  invocation context. Use `T3.Catalog.discover/1` to inspect the connected surface.
  """
  use T3.Toolset, category: :issues
end
