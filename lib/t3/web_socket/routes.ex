defmodule T3.WebSocket.Routes do
  @moduledoc """
  The four non-Effect WebSocket routes in the pinned T3 server. All use the
  environment/media authentication audience, not MCP OAuth credentials. Obtain a
  media ticket with `T3.HTTP.Auth.web_socket_ticket_for(http, "media")` and pass
  `ticket: response.body["ticket"]`.

  Preview delivers binary JPEG frames plus JSON text status/control messages.
  After consuming a JPEG delivery, `preview_ack/2` releases the local delivery and
  sends the route's `{"type":"ack"}`. Other route-specific control/video codecs
  remain literal frames: the SDK does not transcode JPEG/H.264/emulator protocols.

  Device routes accept `query: %{"hostId" => host_id, ...}`. The server consumes
  hostId/wsTicket and forwards remaining query parameters to its allowlisted hub.
  `simulator/2` and `emulator/2` require orchestration operate scope; discovery
  requires read scope. Preview controls additionally require preview operate scope.
  """
  @source_ref "337c5858c33bc7f8f6dfd391a2c279fa0f7e4d17"
  @routes [
    %{
      name: :preview,
      path: "/api/preview-stream/ws",
      audience: "media",
      scope: "orchestration:read",
      query: ["threadId", "tabId"],
      source: "apps/server/src/preview/ServerBrowserStream.ts"
    },
    %{
      name: :devices,
      path: "/api/device-hub/api/devices/ws",
      audience: "media",
      scope: "orchestration:read",
      query: [],
      source: "apps/server/src/device/DeviceHubProxy.ts"
    },
    %{
      name: :simulator,
      path: "/api/device-hub/vendor/serve-sim/helper/ws",
      audience: "media",
      scope: "orchestration:operate",
      query: [],
      source: "apps/server/src/device/DeviceHubProxy.ts"
    },
    %{
      name: :emulator,
      path: "/api/device-hub/vendor/serve-emu/ws",
      audience: "media",
      scope: "orchestration:operate",
      query: [],
      source: "apps/server/src/device/DeviceHubProxy.ts"
    }
  ]
  def source_ref, do: @source_ref
  def catalog, do: @routes
  def all, do: @routes

  @doc "Connect a preview viewer. Set query interactive=false for view-only behavior."
  def preview(base_url, thread_id, tab_id, opts \\ []) do
    query =
      opts |> Keyword.get(:query, %{}) |> Map.merge(%{"threadId" => thread_id, "tabId" => tab_id})

    connect(:preview, base_url, Keyword.put(opts, :query, query))
  end

  def devices(base_url, opts \\ []), do: connect(:devices, base_url, opts)
  def simulator(base_url, opts \\ []), do: connect(:simulator, base_url, opts)
  def emulator(base_url, opts \\ []), do: connect(:emulator, base_url, opts)

  @doc "Release a consumed JPEG delivery and send preview's server acknowledgement."
  def preview_ack(socket, delivery_ref) do
    with :ok <- T3.WebSocket.ack(socket, delivery_ref),
         do: T3.WebSocket.send_json(socket, %{"type" => "ack"})
  end

  defp connect(name, base_url, opts) do
    uri = URI.parse(base_url)

    if uri.userinfo != nil or uri.query != nil or uri.fragment != nil do
      {:error,
       %T3.Error{
         kind: :configuration,
         message: "WebSocket base URL must not contain credentials, query or fragment"
       }}
    else
      route = Enum.find(@routes, &(&1.name == name))
      # Only the path changes; caller-supplied host, scheme, and port stay fixed.
      url = URI.to_string(%{uri | path: route.path})
      T3.WebSocket.start_link(Keyword.put(opts, :url, url))
    end
  end
end
