defmodule T3.ReaderFixture.Socket do
  @behaviour WebSock
  def init(owner) do
    send(owner, {:reader_socket, self()})
    {:ok, owner}
  end

  def handle_in({bytes, [opcode: :text]}, owner) do
    frame = JSON.decode!(bytes)
    send(owner, {:reader_wire, self(), frame})

    case frame do
      %{"_tag" => "Request", "tag" => "snapshot", "id" => id} ->
        push(owner, %{
          "_tag" => "Exit",
          "requestId" => id,
          "exit" => %{"_tag" => "Success", "value" => %{"threads" => []}}
        })

      %{"_tag" => "Request", "tag" => "watch", "id" => id} ->
        push(owner, %{"_tag" => "Chunk", "requestId" => id, "values" => [%{"kind" => "snapshot"}]})

      _ ->
        {:ok, owner}
    end
  end

  def handle_info(:disconnect, owner), do: {:stop, :normal, owner}

  def handle_info({:finish, id}, owner),
    do:
      push(owner, %{
        "_tag" => "Exit",
        "requestId" => id,
        "exit" => %{"_tag" => "Success", "value" => nil}
      })

  defp push(owner, frame), do: {:push, {:text, JSON.encode!(frame)}, owner}
end

defmodule T3.ReaderFixture.Plug do
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    conn |> upgrade_adapter(:websocket, {T3.ReaderFixture.Socket, opts[:owner], []}) |> halt()
  end
end

defmodule T3.RPC.ReaderTest do
  use ExUnit.Case, async: true

  setup do
    server =
      start_supervised!(
        {Bandit,
         plug: {T3.ReaderFixture.Plug, owner: self()},
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    %{url: "ws://127.0.0.1:#{port}/ws"}
  end

  defp opts(url, owner, callback \\ nil) do
    [
      connect: fn ->
        send(owner, :credential_requested)
        {:ok, [url: url, token: "private-reader-token"]}
      end,
      streams: [%{key: :shell, method: "watch", catch_up: {"snapshot", %{}}}],
      on_event:
        callback ||
          fn event ->
            send(owner, {:reader_event, event})
            :ok
          end,
      min_backoff: 20,
      max_backoff: 80,
      jitter: 0
    ]
  end

  test "disconnect re-fetches credentials, catches up and re-subscribes", %{url: url} do
    reader = start_supervised!({T3.RPC.Reader, opts(url, self())})
    assert_receive :credential_requested, 1000
    assert_receive {:reader_socket, socket}, 1000
    assert_receive {:reader_event, {:snapshot, :shell, %{"threads" => []}}}, 1000
    assert_receive {:reader_event, {:status, :connected}}, 1000
    assert_receive {:reader_event, {:chunk, :shell, [_]}}, 1000
    assert_receive {:reader_wire, ^socket, %{"_tag" => "Ack"}}, 1000
    refute inspect(:sys.get_status(reader)) =~ "private-reader-token"
    send(socket, :disconnect)
    assert_receive {:reader_event, {:status, :disconnected}}, 1000
    assert_receive :credential_requested, 1000
    assert_receive {:reader_socket, replacement}, 1000
    refute replacement == socket
    assert_receive {:reader_event, {:snapshot, :shell, %{"threads" => []}}}, 1000
    assert_receive {:reader_event, {:chunk, :shell, [_]}}, 1000
    assert_receive {:reader_wire, ^replacement, %{"_tag" => "Ack"}}, 1000
    assert T3.RPC.Reader.status(reader) == :connected
  end

  test "ACK waits for consumption and completion re-subscribes", %{url: url} do
    owner = self()

    callback = fn
      {:chunk, _, _} = event ->
        send(owner, {:consume, self(), event})

        receive do
          :consumed -> :ok
        end

      event ->
        send(owner, {:reader_event, event})
        :ok
    end

    start_supervised!({T3.RPC.Reader, opts(url, owner, callback)})
    assert_receive {:reader_socket, socket}, 1000
    assert_receive {:reader_wire, ^socket, %{"tag" => "watch", "id" => id}}, 1000
    assert_receive {:consume, reader, _}, 1000
    refute_receive {:reader_wire, ^socket, %{"_tag" => "Ack"}}, 30
    send(reader, :consumed)
    assert_receive {:reader_wire, ^socket, %{"_tag" => "Ack", "requestId" => ^id}}, 1000
    send(socket, {:finish, id})
    assert_receive {:reader_event, {:status, :disconnected}}, 1000
    assert_receive {:reader_socket, replacement}, 1000
    assert_receive {:consume, ^reader, _}, 1000
    send(reader, :consumed)
    assert_receive {:reader_wire, ^replacement, %{"_tag" => "Ack"}}, 1000
  end

  test "failed credential provider retries without dying", %{url: url} do
    owner = self()
    attempts = start_supervised!({Agent, fn -> 0 end})

    connect = fn ->
      count = Agent.get_and_update(attempts, &{&1, &1 + 1})
      send(owner, {:attempt, count})
      if count < 2, do: {:error, :temporarily_unavailable}, else: {:ok, [url: url]}
    end

    start_supervised!({T3.RPC.Reader, Keyword.put(opts(url, owner), :connect, connect)})
    assert_receive {:attempt, 0}, 1000
    assert_receive {:attempt, 1}, 1000
    assert_receive {:attempt, 2}, 1000
    assert_receive {:reader_event, {:chunk, :shell, [_]}}, 1000
  end

  test "a stalled health read reconnects an otherwise open socket", %{url: url} do
    options =
      opts(url, self()) ++
        [health_check: {"silent-health", %{}}, health_interval: 20, health_timeout: 20]

    start_supervised!({T3.RPC.Reader, options})
    assert_receive {:reader_socket, socket}, 1000
    assert_receive {:reader_event, {:chunk, :shell, [_]}}, 1000
    assert_receive {:reader_wire, ^socket, %{"tag" => "silent-health"}}, 1000
    assert_receive {:reader_event, {:status, :disconnected}}, 1000
    assert_receive {:reader_socket, replacement}, 1000
    refute replacement == socket
    assert_receive {:reader_event, {:chunk, :shell, [_]}}, 1000
  end

  test "supervisor shutdown closes the owned socket", %{url: url} do
    start_supervised!({T3.RPC.Reader, opts(url, self())})
    assert_receive {:reader_socket, socket}, 1000
    assert_receive {:reader_event, {:chunk, :shell, [_]}}, 1000
    monitor = Process.monitor(socket)
    stop_supervised!(T3.RPC.Reader)
    assert_receive {:DOWN, ^monitor, :process, ^socket, _}, 1000
  end
end
