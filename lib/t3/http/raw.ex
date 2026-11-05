defmodule T3.HTTP.Raw do
  @moduledoc """
  Routes implemented outside T3's typed EnvironmentHttpApi contract.

  These cover guest shares, files, attachment capabilities, observability, device
  hub binary streams and browser upload/download. Authentication differs per
  route: guest shares require their share cookie and query, uploads use signed
  capability URLs, and media routes require scopes or a purpose-bound ticket.
  Pass cookies/proof/range headers explicitly. There is no cookie jar.

  `call/3` buffers bounded responses. `stream/4` consumes with callback
  backpressure and finite byte/event/deadline limits. Device MJPEG/AVCC data is
  passed unchanged, without codec interpretation. This catalog reflects proxy
  routing; upstream device hubs can impose additional method/payload constraints.
  WebSocket upgrade endpoints belong to the WebSocket transport, not this module.
  """

  @device "/api/device-hub"
  @routes [
    {:asset, :get, "/api/assets/:token/:fileName", :binary, :asset_capability},
    {:attachment_upload, :post, "/api/attachments/upload/:token", :raw, :upload_capability},
    {:otlp_traces, :post, "/api/observability/v1/traces", :json, :orchestration_operate},
    {:guest_redeem, :post, "/api/guest/redeem", :json, :share_credential},
    {:guest_messages, :post, "/api/guest/messages", :json_or_multipart, :guest_cookie},
    {:guest_session, :get, "/api/guest/session", :none, :guest_cookie},
    {:guest_stream, :get, "/api/guest/stream", :sse, :guest_cookie},
    {:guest_render, :get, "/api/guest/render", :binary, :guest_cookie},
    {:guest_item, :get, "/api/guest/item", :none, :guest_cookie},
    {:guest_history, :get, "/api/guest/history", :none, :guest_cookie},
    {:guest_command_output, :get, "/api/guest/command-output", :sse, :guest_cookie},
    {:guest_attachment, :get, "/api/guest/attachment", :binary, :guest_cookie},
    {:guest_media, :get, "/api/guest/media", :binary, :guest_cookie},
    {:preview_download, :get, "/api/preview-stream/download", :binary, :orchestration_read},
    {:preview_upload, :post, "/api/preview-stream/upload", :multipart, :preview_operate},
    {:device_list, :get, @device <> "/api/devices", :none, :orchestration_read},
    {:sim_api, :get, @device <> "/vendor/serve-sim/api", :none, :orchestration_read},
    {:sim_screenshot, :get, @device <> "/vendor/serve-sim/api/screenshot", :binary,
     :orchestration_read},
    {:sim_capture_screenshot, :post, @device <> "/vendor/serve-sim/api/screenshot", :json,
     :orchestration_read},
    {:sim_event_log, :get, @device <> "/vendor/serve-sim/api/event-log", :none,
     :orchestration_read},
    {:sim_event_log_events, :get, @device <> "/vendor/serve-sim/api/event-log/events", :sse,
     :orchestration_read},
    {:sim_mjpeg, :get, @device <> "/vendor/serve-sim/helper/:deviceId/stream.mjpeg",
     :binary_stream, :orchestration_read},
    {:sim_avcc, :get, @device <> "/vendor/serve-sim/helper/:deviceId/stream.avcc", :binary_stream,
     :orchestration_read},
    {:sim_panel_avcc, :get,
     @device <> "/vendor/serve-sim/helper/:deviceId/panel/:panel/stream.avcc", :binary_stream,
     :orchestration_read},
    {:sim_config, :get, @device <> "/vendor/serve-sim/helper/:deviceId/config", :none,
     :orchestration_read},
    {:sim_health, :get, @device <> "/vendor/serve-sim/helper/:deviceId/health", :none,
     :orchestration_read},
    {:sim_accessibility, :get, @device <> "/vendor/serve-sim/helper/:deviceId/ax", :none,
     :orchestration_read},
    {:sim_foreground, :get, @device <> "/vendor/serve-sim/helper/:deviceId/foreground", :none,
     :orchestration_read},
    {:sim_webrtc_offer, :post, @device <> "/vendor/serve-sim/helper/:deviceId/webrtc/offer",
     :json, :orchestration_read},
    {:sim_webrtc_close, :post, @device <> "/vendor/serve-sim/helper/:deviceId/webrtc/close",
     :json, :orchestration_read},
    {:sim_appstate, :get, @device <> "/vendor/serve-sim/appstate", :none, :orchestration_read},
    {:emu_api, :get, @device <> "/vendor/serve-emu/api", :none, :orchestration_read},
    {:emu_devices, :get, @device <> "/vendor/serve-emu/api/devices", :none, :orchestration_read},
    {:emu_screenshot, :get, @device <> "/vendor/serve-emu/api/screenshot", :binary,
     :orchestration_read},
    {:emu_capture_screenshot, :post, @device <> "/vendor/serve-emu/api/screenshot", :json,
     :orchestration_read},
    {:emu_stream_mode, :get, @device <> "/vendor/serve-emu/api/stream-mode", :none,
     :orchestration_read},
    {:emu_set_stream_mode, :post, @device <> "/vendor/serve-emu/api/stream-mode", :json,
     :orchestration_operate},
    {:emu_stream_settings, :get, @device <> "/vendor/serve-emu/api/stream-settings", :none,
     :orchestration_read},
    {:emu_set_stream_settings, :post, @device <> "/vendor/serve-emu/api/stream-settings", :json,
     :orchestration_operate},
    {:emu_accessibility, :get, @device <> "/vendor/serve-emu/api/accessibility", :none,
     :orchestration_read},
    {:emu_fold, :get, @device <> "/vendor/serve-emu/api/fold", :none, :orchestration_read},
    {:emu_set_fold, :post, @device <> "/vendor/serve-emu/api/fold", :json,
     :orchestration_operate},
    {:emu_health, :get, @device <> "/vendor/serve-emu/health", :none, :orchestration_read},
    {:emu_webrtc_offer, :post, @device <> "/vendor/serve-emu/webrtc/offer", :json,
     :orchestration_read},
    {:emu_webrtc_close, :post, @device <> "/vendor/serve-emu/webrtc/close", :json,
     :orchestration_read}
  ]

  @doc "Raw route catalog, separate from the 38 EnvironmentHttpApi endpoints."
  def endpoints do
    Enum.map(@routes, fn {id, method, path, encoding, auth} ->
      %{
        id: id,
        method: method,
        path: path,
        encoding: encoding,
        auth: auth,
        streaming: encoding in [:sse, :binary_stream],
        path_params:
          Regex.scan(~r/:([A-Za-z][A-Za-z0-9]*)/, path, capture: :all_but_first) |> List.flatten()
      }
    end)
  end

  @doc "Call a raw route with string-keyed :params and normal HTTP request options."
  def call(client, id, opts \\ []) do
    with {:ok, spec, path, opts} <- prepare(id, opts),
         do: T3.HTTP.request(client, spec.method, path, opts)
  end

  @doc "Consume a raw route with bounded streaming and callback backpressure."
  def stream(client, id, callback, opts \\ []) do
    with {:ok, spec, path, opts} <- prepare(id, opts) do
      mode = if spec.encoding == :sse, do: :sse, else: :raw
      T3.HTTP.stream(client, spec.method, path, callback, Keyword.put_new(opts, :mode, mode))
    end
  end

  defp prepare(id, opts) do
    case Enum.find(endpoints(), &(&1.id == id)) do
      nil ->
        error("unknown raw HTTP route")

      spec ->
        with {:ok, path} <- expand(spec.path, Keyword.get(opts, :params, %{})) do
          opts = Keyword.delete(opts, :params)

          opts =
            cond do
              spec.encoding in [:json, :json_or_multipart] and
                  not Keyword.has_key?(opts, :multipart) ->
                Keyword.put_new(opts, :json, %{})

              spec.encoding in [:binary, :binary_stream] ->
                Keyword.put_new(opts, :decode, :binary)

              true ->
                opts
            end

          {:ok, spec, path, opts}
        end
    end
  end

  defp expand(path, params) when is_map(params) do
    Enum.reduce_while(
      Regex.scan(~r/:([A-Za-z][A-Za-z0-9]*)/, path, capture: :all_but_first),
      {:ok, path},
      fn [key], {:ok, path} ->
        case Map.fetch(params, key) do
          {:ok, value} when is_binary(value) and value != "" ->
            {:cont,
             {:ok, String.replace(path, ":" <> key, URI.encode(value, &URI.char_unreserved?/1))}}

          _ ->
            {:halt, error("missing raw route parameter #{key}")}
        end
      end
    )
  end

  defp expand(_, _), do: error("raw route params must be a string-keyed map")
  defp error(message), do: {:error, %T3.Error{kind: :configuration, message: message}}
end
