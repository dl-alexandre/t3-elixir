defmodule T3.Feedback do
  @moduledoc """
  Feedback operations through MCP. Pass T3's original string-keyed argument maps.

  Feedback visibility and submission behavior depend on server settings and
  invocation context. Use `T3.Catalog.discover/1` to inspect availability.
  """
  use T3.Toolset, category: :feedback
end
