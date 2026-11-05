defmodule T3 do
  @moduledoc """
  Elixir SDK for T3 Code's MCP, HTTP JSON, WebSocket RPC and local CLI interfaces.

  Start MCP access with `T3.Client.new/1` and `connect/1`. See `T3.Tools` for
  every known MCP operation, `T3.HTTP` for environment APIs, `T3.RPC` for Effect
  RPC calls/subscriptions, `T3.WebSocket` for raw media frames, and `T3.CLI` for the installed executable. Credentials
  and context are interface-specific. The catalogs describe a pinned upstream
  revision; `T3.Catalog.discover/1` reports a connected MCP server's actual tools.
  Wire maps retain T3's string keys and server-side input validation.
  """
  defdelegate new(opts), to: T3.Client
  defdelegate connect(client), to: T3.Client
  defdelegate close(client), to: T3.Client
  defdelegate list_tools(client), to: T3.Client
  defdelegate call_tool(client, name, arguments \\ %{}), to: T3.Client
  defdelegate discover(client), to: T3.Catalog

  @doc "Known operation inventories. This does not probe a server or execute CLI commands."
  def interfaces do
    %{
      mcp: T3.Catalog.tools(),
      http: T3.HTTP.endpoints(),
      http_raw: T3.HTTP.raw_endpoints(),
      rpc: T3.RPC.Catalog.methods(),
      web_socket: T3.WebSocket.Routes.all(),
      cli: T3.CLI.families()
    }
  end
end
