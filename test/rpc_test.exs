defmodule T3.RPCFixture.Socket do
  @behaviour WebSock
  def init(state), do: {:ok, state}

  def handle_in({body, [opcode: :text]}, state) do
    frame = JSON.decode!(body)
    send(state.owner, {:rpc_frame, self(), frame})

    case frame do
      %{"_tag" => "Request", "id" => id, "tag" => "echo", "payload" => payload} ->
        success(state, id, payload)

      %{"_tag" => "Request", "id" => id, "tag" => "fail"} ->
        push(state, %{
          "_tag" => "Exit",
          "requestId" => id,
          "exit" => %{
            "_tag" => "Failure",
            "cause" => [%{"_tag" => "Fail", "error" => %{"message" => "bad request"}}]
          }
        })

      %{"_tag" => "Request", "id" => id, "tag" => "stream"} ->
        push(%{state | stream: id}, %{"_tag" => "Chunk", "requestId" => id, "values" => [1, 2]})

      %{"_tag" => "Ack", "requestId" => id} ->
        success(state, id, "finished")

      %{"_tag" => "Request", "tag" => "disconnect"} ->
        {:stop, :normal, state}

      %{"_tag" => "Request", "tag" => "server_request"} ->
        push(state, %{
          "_tag" => "Request",
          "id" => "from-server",
          "tag" => "client.prompt",
          "payload" => %{"question" => "hello"},
          "headers" => []
        })

      %{"_tag" => "Ping"} ->
        push(state, %{"_tag" => "Pong"})

      _ ->
        {:ok, state}
    end
  end

  def handle_info({:push, value}, state), do: push(state, value)

  defp success(state, id, value),
    do:
      push(state, %{
        "_tag" => "Exit",
        "requestId" => id,
        "exit" => %{"_tag" => "Success", "value" => value}
      })

  defp push(state, value), do: {:push, {:text, JSON.encode!(value)}, state}
end

defmodule T3.RPCFixture.Plug do
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    conn = fetch_query_params(conn)
    send(opts[:owner], {:rpc_upgrade, conn.query_params, conn.req_headers})

    if conn.query_params["orchestrationProtocol"] == "2" and
         (get_req_header(conn, "authorization") in [
            ["Bearer synthetic-token"],
            ["DPoP synthetic-token"]
          ] or
            conn.query_params["wsTicket"] == "synthetic-ticket") do
      conn
      |> upgrade_adapter(
        :websocket,
        {T3.RPCFixture.Socket, %{owner: opts[:owner], stream: nil}, []}
      )
      |> halt()
    else
      send_resp(conn, 401, "")
    end
  end
end

defmodule T3.RPCTest do
  use ExUnit.Case, async: true
  alias T3.{RPC, Error}

  setup do
    server =
      start_supervised!(
        {Bandit,
         plug: {T3.RPCFixture.Plug, owner: self()},
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    {:ok, url: "ws://127.0.0.1:#{port}/ws"}
  end

  defp rpc(url, opts \\ []) do
    {:ok, pid} =
      RPC.start_link(Keyword.merge([url: url, token: "synthetic-token", owner: self()], opts))

    on_exit(fn -> RPC.close(pid) end)
    pid
  end

  test "unary request, exact payload, typed failure and keepalive", %{url: url} do
    pid = rpc(url)
    assert {:ok, %{"projectId" => "one"}} = RPC.call(pid, "echo", %{"projectId" => "one"})
    assert_receive {:rpc_upgrade, %{"orchestrationProtocol" => "2"}, headers}
    assert {"authorization", "Bearer synthetic-token"} in headers

    assert_receive {:rpc_frame, _,
                    %{"_tag" => "Request", "headers" => [], "payload" => %{"projectId" => "one"}}}

    assert {:error, %Error{kind: :rpc, details: [%{"error" => %{"message" => "bad request"}}]}} =
             RPC.call(pid, "fail")

    assert :ok = RPC.ping(pid)
    assert {:ok, 42} = RPC.call(pid, "echo", 42)
  end

  test "ticket authentication stays in upgrade and connection status is redacted", %{url: url} do
    pid = rpc(url, token: nil, ticket: "synthetic-ticket")
    assert_receive {:rpc_upgrade, %{"wsTicket" => "synthetic-ticket"}, headers}
    refute List.keymember?(headers, "authorization", 0)
    refute inspect(:sys.get_status(pid)) =~ "synthetic-ticket"
    assert {:ok, %{}} = RPC.call(pid, "echo")
  end

  test "subscription chunks are acknowledged explicitly and completed", %{url: url} do
    pid = rpc(url)
    assert {:ok, id} = RPC.subscribe(pid, "stream")
    assert_receive {:t3_rpc, ^id, {:chunk, [1, 2]}}
    refute_receive {:t3_rpc, ^id, {:done, _}}, 20
    assert :ok = RPC.ack(pid, id)
    assert_receive {:t3_rpc, ^id, {:done, "finished"}}
    assert {:error, %Error{kind: :protocol}} = RPC.ack(pid, id)
  end

  test "unsubscribe and owner death send Interrupt", %{url: url} do
    pid = rpc(url)
    {:ok, id} = RPC.subscribe(pid, "hold")
    assert :ok = RPC.unsubscribe(pid, id)
    assert_receive {:rpc_frame, _, %{"_tag" => "Interrupt", "requestId" => ^id}}
    parent = self()

    owner =
      spawn(fn ->
        {:ok, request} = RPC.subscribe(pid, "hold")
        send(parent, {:owned, request})

        receive do
          :quit -> :ok
        end
      end)

    assert_receive {:owned, owned_id}
    send(owner, :quit)
    assert_receive {:rpc_frame, _, %{"_tag" => "Interrupt", "requestId" => ^owned_id}}
  end

  test "deadlines cancel requests without replay", %{url: url} do
    pid = rpc(url)
    assert {:error, %Error{kind: :timeout}} = RPC.call(pid, "hold", %{}, timeout: 20)
    assert_receive {:rpc_frame, _, %{"_tag" => "Request", "id" => id}}
    assert_receive {:rpc_frame, _, %{"_tag" => "Interrupt", "requestId" => ^id}}
    refute_receive {:rpc_frame, _, %{"_tag" => "Request"}}, 20
  end

  test "disconnect fails pending calls and subscriptions", %{url: url} do
    pid = rpc(url)
    {:ok, id} = RPC.subscribe(pid, "hold")
    assert {:error, %Error{kind: kind}} = RPC.call(pid, "disconnect")
    assert kind in [:closed, :transport]
    assert_receive {:t3_rpc, ^id, {:error, %Error{}}}
    assert {:error, %Error{kind: :closed}} = RPC.call(pid, "echo")
  end

  test "server-originated requests can be answered", %{url: url} do
    pid = rpc(url)
    {:ok, id} = RPC.subscribe(pid, "server_request")

    assert_receive {:t3_rpc_request, ^pid, "from-server", "client.prompt",
                    %{"question" => "hello"}}

    assert :ok = RPC.respond(pid, "from-server", {:ok, "answer"})

    assert_receive {:rpc_frame, _,
                    %{
                      "_tag" => "Exit",
                      "requestId" => "from-server",
                      "exit" => %{"_tag" => "Success", "value" => "answer"}
                    }}

    RPC.unsubscribe(pid, id)
  end

  test "limits are validated and pending work is bounded", %{url: url} do
    assert {:error, %Error{kind: :configuration}} = RPC.start_link(url: url, timeout: 0)
    assert {:error, %Error{kind: :configuration}} = RPC.start_link(url: "ws://example.com/ws")
    pid = rpc(url, max_pending: 1)
    {:ok, id} = RPC.subscribe(pid, "hold")
    assert {:error, %Error{kind: :overloaded}} = RPC.call(pid, "echo")
    RPC.unsubscribe(pid, id)
  end

  test "DPoP credentials use the matching authorization scheme", %{url: url} do
    pid = rpc(url, dpop: "synthetic-proof")
    assert_receive {:rpc_upgrade, _, headers}
    assert {"authorization", "DPoP synthetic-token"} in headers
    assert {"dpop", "synthetic-proof"} in headers
    assert {:ok, %{}} = RPC.call(pid, "echo")
  end

  test "scoped protocol errors fail only their named requests", %{url: url} do
    pid = rpc(url)
    {:ok, first} = RPC.subscribe(pid, "hold")
    {:ok, second} = RPC.subscribe(pid, "hold")
    assert_receive {:rpc_frame, socket, %{"id" => ^first}}

    send(
      socket,
      {:push,
       %{
         "_tag" => "ClientProtocolError",
         "requestIds" => [first],
         "error" => %{"message" => "invalid"}
       }}
    )

    assert_receive {:t3_rpc, ^first, {:error, %Error{kind: :protocol}}}
    refute_receive {:t3_rpc, ^second, _}, 20
    assert :ok = RPC.unsubscribe(pid, second)
  end

  test "upgrade packet preserves an immediately following server frame" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, port} = :inet.port(listener)

    server =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, request} = :gen_tcp.recv(socket, 0, 2000)
        [_, key] = Regex.run(~r/sec-websocket-key: ([^\r]+)\r/i, request)

        accept =
          :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") |> Base.encode64()

        body =
          JSON.encode!(%{
            "_tag" => "Request",
            "id" => "early",
            "tag" => "hello",
            "payload" => %{}
          })

        frame = <<0x81, byte_size(body)>> <> body

        :gen_tcp.send(
          socket,
          "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{accept}\r\n\r\n" <>
            frame
        )

        receive do
          :done -> :gen_tcp.close(socket)
        end
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      send(server, :done)
    end)

    {:ok, pid} = RPC.start_link(url: "ws://127.0.0.1:#{port}/ws", owner: self())
    assert_receive {:t3_rpc_request, ^pid, "early", "hello", %{}}, 1000
    assert :ok = RPC.close(pid)
    send(server, :done)
  end

  test "unfinished oversized RPC frames are bounded before a final fragment" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}, reuseaddr: true])

    {:ok, port} = :inet.port(listener)

    server =
      spawn(fn ->
        {:ok, socket} = :gen_tcp.accept(listener)
        {:ok, request} = :gen_tcp.recv(socket, 0, 2000)
        [_, key] = Regex.run(~r/sec-websocket-key: ([^\r]+)\r/i, request)

        accept =
          :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") |> Base.encode64()

        frame = <<0x01, 40>> <> String.duplicate("a", 40)

        :gen_tcp.send(
          socket,
          "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: #{accept}\r\n\r\n" <>
            frame
        )

        :gen_tcp.recv(socket, 0, 2000)
        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      :gen_tcp.close(listener)
      if Process.alive?(server), do: Process.exit(server, :kill)
    end)

    {:ok, pid} = RPC.start_link(url: "ws://127.0.0.1:#{port}/ws", max_message_bytes: 4)
    monitor = Process.monitor(pid)
    assert_receive {:DOWN, ^monitor, :process, ^pid, _}, 1000
  end

  test "catalog covers all pinned methods with generated helpers" do
    methods = RPC.Catalog.methods()
    assert length(methods) == 211
    assert Enum.count(methods, & &1["stream"]) == 27
    assert {:ok, %{"stream" => true}} = RPC.Catalog.fetch("orchestration.subscribeShell")
    Code.ensure_loaded!(RPC.Methods)
    assert function_exported?(RPC.Methods, :server_get_config, 3)
    assert function_exported?(RPC.Methods, :orchestration_subscribe_shell, 3)
  end
end
