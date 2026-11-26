defmodule T3.Themes do
  @moduledoc """
  T3 Code theme operations through MCP. Pass T3's original string-keyed argument maps.

  Theme changes may affect the running server's web app and local desktop app.
  Server permissions and invocation context are enforced by T3.
  """
  use T3.Toolset, category: :themes
end
