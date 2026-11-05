defmodule T3.RawWebSocketFixture do
  @behaviour WebSock
  def init(state), do: {:ok, state}

  def handle_in({bytes, [opcode: opcode]}, state) do
    send(state.owner, {:raw_in, self(), opcode, bytes})
    {:push, {opcode, bytes}, state}
  end

  def handle_info({:push, frames}, state), do: {:push, frames, state}
  def handle_info(:close, state), do: {:stop, :normal, state}
end

defmodule T3.RawWebSocketFixture.Plug do
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    conn = fetch_query_params(conn)
    send(opts[:owner], {:raw_upgrade, conn.request_path, conn.query_params, conn.req_headers})

    conn
    |> upgrade_adapter(:websocket, {T3.RawWebSocketFixture, %{owner: opts[:owner]}, []})
    |> halt()
  end
end

defmodule T3.WebSocketTest do
  use ExUnit.Case, async: true
  alias T3.{WebSocket, Error}

  setup do
    server =
      start_supervised!(
        {Bandit,
         plug: {T3.RawWebSocketFixture.Plug, owner: self()},
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    {:ok, base: "ws://127.0.0.1:#{port}"}
  end

  defp socket(base, opts) do
    {:ok, socket} =
      WebSocket.start_link(Keyword.merge([url: base <> "/raw", owner: self()], opts))

    on_exit(fn -> WebSocket.close(socket) end)
    socket
  end

  test "text and binary bytes are literal and local acknowledgements release backlog", %{
    base: base
  } do
    socket = socket(base, max_pending_frames: 1)
    assert :ok = WebSocket.send_text(socket, "literal text")
    assert_receive {:t3_web_socket, ^socket, first, {:text, "literal text"}}
    assert :ok = WebSocket.ack(socket, first)
    assert :ok = WebSocket.send_binary(socket, <<0, 255, 10, 20>>)
    assert_receive {:t3_web_socket, ^socket, second, {:binary, <<0, 255, 10, 20>>}}
    assert :ok = WebSocket.ack(socket, second)
    assert {:error, %Error{kind: :protocol}} = WebSocket.ack(socket, second)
    assert :ok = WebSocket.close(socket)
    assert_receive {:t3_web_socket, ^socket, {:closed, :normal}}
    assert :ok = WebSocket.close(socket)
  end

  test "slow owner backlog closes instead of buffering indefinitely", %{base: base} do
    socket = socket(base, max_pending_frames: 1)
    WebSocket.send_text(socket, "one")
    assert_receive {:t3_web_socket, ^socket, _, {:text, "one"}}
    WebSocket.send_text(socket, "two")
    assert_receive {:t3_web_socket, ^socket, {:error, %Error{kind: :overloaded}}}
    assert_receive {:t3_web_socket, ^socket, {:closed, :error}}
  end

  test "message and aggregate byte bounds are enforced", %{base: base} do
    socket = socket(base, max_message_bytes: 4, max_pending_bytes: 4)
    assert {:error, %Error{kind: :configuration}} = WebSocket.send_binary(socket, "12345")
    assert :ok = WebSocket.send_binary(socket, "123")
    assert_receive {:raw_in, peer, :binary, "123"}
    assert_receive {:t3_web_socket, ^socket, _, {:binary, "123"}}
    send(peer, {:push, {:binary, "12"}})
    assert_receive {:t3_web_socket, ^socket, {:error, %Error{kind: :overloaded}}}
  end

  test "oversized server message closes with protocol error", %{base: base} do
    socket = socket(base, max_message_bytes: 4)
    WebSocket.send_text(socket, "ping")
    assert_receive {:raw_in, peer, :text, "ping"}
    assert_receive {:t3_web_socket, ^socket, ref, {:text, "ping"}}
    WebSocket.ack(socket, ref)
    send(peer, {:push, {:binary, "too large"}})
    assert_receive {:t3_web_socket, ^socket, {:error, %Error{kind: :protocol}}}
  end

  test "idle/lifetime deadlines close and owner death cleans up", %{base: base} do
    socket = socket(base, idle_timeout: 20)
    assert_receive {:t3_web_socket, ^socket, {:error, %Error{kind: :timeout}}}, 1000
    parent = self()

    owner =
      spawn(fn ->
        receive do
          :finish -> :ok
        end
      end)

    socket = socket(base, owner: owner, idle_timeout: :infinity, lifetime: :infinity)
    monitor = Process.monitor(socket)
    send(owner, :finish)
    assert_receive {:DOWN, ^monitor, :process, ^socket, :normal}, 1000
    assert is_pid(parent)
  end

  test "explicit credentials and route query are sent only on the chosen origin", %{base: base} do
    socket =
      socket(base,
        token: "private-token",
        query: %{"device" => "one two"},
        headers: [{"x-test", "value"}]
      )

    assert_receive {:raw_upgrade, "/raw", %{"device" => "one two"}, headers}
    assert {"authorization", "Bearer private-token"} in headers
    assert {"x-test", "value"} in headers
    refute inspect(:sys.get_status(socket)) =~ "private-token"
    assert :ok = WebSocket.ping(socket)
    assert :ok = WebSocket.send_json(socket, %{"hello" => "world"})
    assert_receive {:t3_web_socket, ^socket, _, {:text, "{\"hello\":\"world\"}"}}
  end

  test "preview/device named routes preserve media framing and server acknowledgement", %{
    base: base
  } do
    {:ok, socket} =
      WebSocket.Routes.preview(base, "thread", "tab",
        ticket: "media-ticket",
        query: %{"interactive" => false}
      )

    on_exit(fn -> WebSocket.close(socket) end)
    assert_receive {:raw_upgrade, "/api/preview-stream/ws", query, _}

    assert query == %{
             "threadId" => "thread",
             "tabId" => "tab",
             "wsTicket" => "media-ticket",
             "interactive" => "false"
           }

    WebSocket.send_binary(socket, <<255, 216, 255>>)
    assert_receive {:t3_web_socket, ^socket, ref, {:binary, <<255, 216, 255>>}}
    assert :ok = WebSocket.Routes.preview_ack(socket, ref)
    assert_receive {:raw_in, _, :text, "{\"type\":\"ack\"}"}
    assert length(WebSocket.Routes.catalog()) == 4
    assert :ok = WebSocket.close(socket)

    for name <- [:devices, :simulator, :emulator] do
      assert {:ok, connection} =
               apply(WebSocket.Routes, name, [base, [query: %{"hostId" => "host"}]])

      assert_receive {:raw_upgrade, path, %{"hostId" => "host"}, _}
      assert String.starts_with?(path, "/api/device-hub/")
      WebSocket.close(connection)
    end
  end

  test "fragmented messages are bounded before the final fragment" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, port} = :inet.port(listener)

    server =
      spawn(fn ->
        {:ok, peer} = :gen_tcp.accept(listener)
        {:ok, request} = :gen_tcp.recv(peer, 0, 2000)
        [_, key] = Regex.run(~r/sec-websocket-key: ([^\r]+)\r/i, request)

        accept =
          :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") |> Base.encode64()

        # Non-final binary + non-final continuation: no complete message is emitted.
        fragments =
          <<0x02, 12>> <> String.duplicate("a", 12) <> <<0x00, 12>> <> String.duplicate("b", 12)

        :gen_tcp.send(
          peer,
          "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{accept}\r\n\r\n" <>
            fragments
        )

        receive do
          :done -> :gen_tcp.close(peer)
        end
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      send(server, :done)
    end)

    assert {:ok, socket} =
             WebSocket.start_link(url: "ws://127.0.0.1:#{port}/raw", max_message_bytes: 4)

    assert_receive {:t3_web_socket, ^socket, {:error, %Error{kind: :protocol}}}, 1000
    assert_receive {:t3_web_socket, ^socket, {:closed, :error}}
    send(server, :done)
  end

  test "unsafe URLs, reserved headers and invalid limits are rejected before connection" do
    for opts <- [
          [url: "ws://example.com/socket"],
          [url: "ws://localhost/x?token=bad"],
          [url: "ws://user:secret@localhost/x"],
          [url: "ws://localhost/x", headers: [{"host", "other.example"}]],
          [url: "ws://localhost/x", max_pending_frames: 0]
        ] do
      assert {:error, %Error{kind: :configuration}} = WebSocket.start_link(opts)
    end
  end
end
