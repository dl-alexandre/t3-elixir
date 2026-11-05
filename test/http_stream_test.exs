defmodule T3.HTTPStreamTest.Fixture do
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    {:ok, body, conn} = read_body(conn)

    send(
      opts[:owner],
      {:raw_request, conn.method, conn.request_path, conn.query_string, conn.req_headers, body}
    )

    case conn.request_path do
      path when path in ["/sse", "/api/guest/stream", "/api/guest/command-output"] ->
        conn = conn |> put_resp_content_type("text/event-stream") |> send_chunked(200)

        send_chunks(conn, [
          <<0xEF, 0xBB>>,
          <<0xBF>> <> ": ping\r\nid: 1\r\ndata: {\"value\":",
          "1}\r\n\r\nid: 2\ndata: two\n\nid: 3\ndata: three\n\n"
        ])

      "/large-event" ->
        conn = conn |> put_resp_content_type("text/event-stream") |> send_chunked(200)
        send_chunks(conn, ["data: " <> String.duplicate("x", 100) <> "\n\n"])

      "/unauthorized" ->
        send_resp(conn, 401, "unauthorized")

      "/slow" ->
        Process.sleep(200)
        send_resp(conn, 200, "late")

      "/binary" ->
        conn = conn |> put_resp_content_type("video/avcc") |> send_chunked(200)
        send_chunks(conn, [<<0, 0, 0, 1, 255>>, {:delay, 20}, <<4, 3, 2, 1, 0>>])

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, JSON.encode!(%{accepted: true}))
    end
  end

  # Clients intentionally halt/cancel streams; a closed socket is an expected fixture outcome.
  defp send_chunks(conn, chunks) do
    Enum.reduce_while(chunks, conn, fn
      {:delay, milliseconds}, conn ->
        Process.sleep(milliseconds)
        {:cont, conn}

      bytes, conn ->
        case chunk(conn, bytes) do
          {:ok, next} -> {:cont, next}
          {:error, :closed} -> {:halt, conn}
        end
    end)
  end
end

defmodule T3.HTTPStreamTest do
  use ExUnit.Case, async: true
  alias T3.HTTP

  setup do
    server =
      start_supervised!(
        {Bandit,
         plug: {T3.HTTPStreamTest.Fixture, owner: self()},
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    {:ok, http: HTTP.new(base_url: "http://127.0.0.1:#{port}")}
  end

  test "SSE parses split BOM/CRLF and preserves ids with callback halt", %{http: http} do
    owner = self()

    callback = fn
      {:event, event} ->
        send(owner, {:event, event})
        if event.id == "2", do: :halt, else: :cont

      _ ->
        :cont
    end

    assert {:ok, summary} = HTTP.stream(http, :get, "/sse", callback, mode: :sse)
    assert summary.events == 2
    assert summary.halted?
    assert summary.last_event_id == "2"
    assert_receive {:event, %{id: "1", data: "{\"value\":1}"}}
    assert_receive {:event, %{id: "2", data: "two"}}
    refute_receive {:event, %{id: "3"}}
  end

  test "binary streams preserve AVCC/MJPEG bytes without codecs", %{http: http} do
    owner = self()

    callback = fn
      {:data, bytes} ->
        send(owner, {:bytes, bytes})
        :cont

      _ ->
        :cont
    end

    assert {:ok, summary} = HTTP.stream(http, :get, "/binary", callback)
    assert summary.bytes == 10
    assert summary.events >= 1
    chunks = collect_bytes([])
    assert IO.iodata_to_binary(chunks) == <<0, 0, 0, 1, 255, 4, 3, 2, 1, 0>>
  end

  test "event, byte and per-event bounds stop streams", %{http: http} do
    callback = fn _ -> :cont end

    assert {:error, %T3.Error{kind: :protocol}} =
             HTTP.stream(http, :get, "/sse", callback, mode: :sse, max_events: 1)

    assert {:error, %T3.Error{kind: :protocol}} =
             HTTP.stream(http, :get, "/binary", callback, max_bytes: 3)

    assert {:error, %T3.Error{kind: :protocol}} =
             HTTP.stream(http, :get, "/large-event", callback, mode: :sse, max_event_bytes: 10)
  end

  test "callbacks apply backpressure and owned tasks can cancel blocked callbacks", %{http: http} do
    owner = self()

    callback = fn
      {:data, _} ->
        send(owner, {:blocked_callback, self()})

        receive do
          :continue -> :cont
        end

      _ ->
        :cont
    end

    task = HTTP.start_stream(http, :get, "/binary", callback)
    assert_receive {:blocked_callback, worker}, 1000
    ref = Process.monitor(worker)
    refute_receive {:blocked_callback, _}, 50
    assert HTTP.cancel_stream(task) == :ok
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 1000
  end

  test "wall-clock deadlines also bound callback execution", %{http: http} do
    callback = fn
      {:data, _} ->
        Process.sleep(5000)
        :cont

      _ ->
        :cont
    end

    start = System.monotonic_time(:millisecond)

    assert {:error, %T3.Error{kind: :timeout}} =
             HTTP.stream(http, :get, "/binary", callback, timeout: 50)

    assert System.monotonic_time(:millisecond) - start < 1000

    assert {:error, %T3.Error{kind: :timeout}} =
             HTTP.stream(http, :get, "/slow", fn _ -> :cont end, timeout: 20)
  end

  test "stream rejects HTTP errors, cross-origin paths and callback failures", %{http: http} do
    assert {:error, %T3.Error{kind: :http, code: 401}} =
             HTTP.stream(http, :get, "/unauthorized", fn _ -> :cont end)

    assert {:error, %T3.Error{kind: :configuration}} =
             HTTP.stream(http, :get, "https://elsewhere.example/", fn _ -> :cont end)

    assert {:error, %T3.Error{kind: :protocol}} =
             HTTP.stream(http, :get, "/binary", fn _ -> :wrong end)

    assert {:error, %T3.Error{kind: :stream}} =
             HTTP.stream(http, :get, "/binary", fn _ -> raise "callback failed" end)
  end

  test "guest streams require explicit share query and cookie headers", %{http: http} do
    assert {:ok, %{events: 3}} =
             HTTP.Guest.stream(http, fn _ -> :cont end,
               query: %{"share" => "share-1"},
               headers: [{"cookie", "guest-share-1=session"}]
             )

    assert_receive {:raw_request, "GET", "/api/guest/stream", "share=share-1", headers, _}
    assert {"cookie", "guest-share-1=session"} in headers
    refute List.keymember?(headers, "authorization", 0)
  end

  test "raw catalog and device helper routes preserve original wire query", %{http: http} do
    routes = HTTP.raw_endpoints()
    assert length(routes) == 45
    assert Enum.any?(routes, &(&1.id == :sim_mjpeg and &1.streaming))
    assert Enum.any?(routes, &(&1.id == :guest_stream and &1.auth == :guest_cookie))

    assert {:ok, _} =
             HTTP.DeviceHub.call(http, :sim_mjpeg,
               params: %{"deviceId" => "device /1"},
               query: %{"hostId" => "host-1"}
             )

    assert_receive {:raw_request, "GET",
                    "/api/device-hub/vendor/serve-sim/helper/device%20%2F1/stream.mjpeg",
                    "hostId=host-1", _, _}

    assert {:ok, _} = HTTP.DeviceHub.request(http, :head, "/api/devices")
    assert_receive {:raw_request, "HEAD", "/api/device-hub/api/devices", _, _, _}
  end

  test "multipart guest and browser uploads use shared encoder and exact file bytes", %{
    http: http
  } do
    file = Path.join(System.tmp_dir!(), "t3-upload-#{System.unique_integer([:positive])}.txt")
    File.write!(file, "streamed-local-file")
    on_exit(fn -> File.rm(file) end)

    multipart =
      HTTP.multipart(%{"shareId" => "share-1", "text" => "hello"}, [
        {"file", file},
        {"file", "memory.bin", <<0, 255, 1>>, "application/octet-stream"}
      ])

    assert {:ok, _} =
             HTTP.Guest.messages(http, query: %{"share" => "share-1"}, multipart: multipart)

    assert_receive {:raw_request, "POST", "/api/guest/messages", "share=share-1", headers, body}
    assert {"content-type", Multipart.content_type(multipart, "multipart/form-data")} in headers
    assert body =~ "streamed-local-file"
    assert :binary.match(body, <<0, 255, 1>>) != :nomatch
    assert body =~ "name=\"shareId\""

    assert {:ok, _} =
             HTTP.Media.preview_upload(http, multipart,
               query: %{"threadId" => "t", "tabId" => "tab", "chooser" => "c"}
             )

    assert_receive {:raw_request, "POST", "/api/preview-stream/upload", query, _, _}
    assert URI.decode_query(query)["chooser"] == "c"
  end

  defp collect_bytes(acc) do
    receive do
      {:bytes, bytes} -> collect_bytes([bytes | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
