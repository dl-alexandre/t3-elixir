defmodule T3.HTTP.DeviceHub do
  @moduledoc """
  Low-level HTTP access to T3's allowlisted device-hub proxy routes.
  Pass `query: %{"hostId" => host_id}` to select a host. Codec streams remain
  binary, and screenshots/accessibility/control payloads are forwarded unchanged.
  These APIs expose the server interface; they do not boot or select devices.
  """
  @doc "Call any :device_list, :sim_* or :emu_* route from the raw catalog."
  def call(client, route, opts \\ []), do: T3.HTTP.Raw.call(client, route, opts)
  @doc "Stream device data with callback backpressure; MJPEG/AVCC bytes are unchanged."
  def stream(client, route, callback, opts \\ []),
    do: T3.HTTP.Raw.stream(client, route, callback, opts)

  @doc "Access a proxy subpath using an explicitly chosen method; the server's allowlist applies."
  def request(client, method, path, opts \\ []) do
    if String.starts_with?(path, "/") and not String.starts_with?(path, "//") do
      T3.HTTP.request(client, method, "/api/device-hub" <> path, opts)
    else
      {:error,
       %T3.Error{kind: :configuration, message: "device hub subpath must start with one slash"}}
    end
  end
end
