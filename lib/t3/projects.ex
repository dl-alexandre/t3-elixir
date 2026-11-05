defmodule T3.Projects do
  @moduledoc """
  Project discovery and mutation through MCP. Outside clients have no implicit T3
  project. `read/2`, `create/2`, `update/2`, `delete/2` and `clone/2` take T3's
  original string-keyed maps. Permission and availability are enforced by T3.
  """
  use T3.Toolset, category: :projects
end
