defmodule T3Test do
  use ExUnit.Case, async: true
  alias T3.{Client, Error}

  setup do
    server =
      start_supervised!(
        {Bandit,
         plug: {T3.TestFixture, owner: self()}, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    {:ok, origin: "http://127.0.0.1:#{port}"}
  end

  defp connect(origin, path \\ "/json") do
    {:ok, client} =
      T3.new(url: origin <> path, token: "fixture-token", timeout: 1000) |> T3.connect()

    on_exit(fn -> Client.close(client) end)
    client
  end

  for path <- ["/json", "/sse"] do
    test "handshake, discovery, pagination and structured calls over #{path}", %{origin: origin} do
      client = connect(origin, unquote(path))

      assert {:ok, %{"tools" => [%{"name" => "t3_thread_list"}], "nextCursor" => "page-2"}} =
               T3.list_tools(client)

      assert {:ok, _} = Client.list_tools(client, %{"cursor" => "page-2"})

      assert {:ok, %{"structuredContent" => %{"threads" => []}, "_meta" => %{"fixture" => true}}} =
               T3.Threads.read(client, "thread-1", %{"limit" => 2})

      assert_receive {:request, "POST", _, headers, _}
      assert {"authorization", "Bearer fixture-token"} in headers
      assert_receive {:request, "POST", _, _, "{\"jsonrpc\"" <> _}, 1000
      assert Client.close(client) == :ok
      assert Client.close(client) == :ok
    end
  end

  test "thread and task helpers preserve T3 arguments", %{origin: origin} do
    client = connect(origin)
    assert {:ok, _} = T3.Threads.send(client, "thread-1", "hello", %{"mode" => "queue"})
    requests = collect_requests([])
    bodies = for {:request, "POST", _, _, body} <- requests, do: JSON.decode!(body)

    assert Enum.any?(
             bodies,
             &(&1["params"] == %{
                 "name" => "t3_thread_send",
                 "arguments" => %{
                   "threadId" => "thread-1",
                   "message" => "hello",
                   "mode" => "queue"
                 }
               })
           )

    assert {:ok, _} = T3.Tasks.cancel(client, "task-1")
  end

  test "tool, RPC and HTTP errors are returned promptly", %{origin: origin} do
    client = connect(origin)

    assert {:error, %Error{kind: :tool, details: %{"isError" => true}}} =
             T3.call_tool(client, "tool_error")

    assert {:error, %Error{kind: :protocol}} = T3.call_tool(client, "rpc_error")
    assert {:error, %Error{kind: :transport}} = T3.call_tool(client, "http_error")
    bodies = for {:request, "POST", _, _, body} <- collect_requests([]), do: JSON.decode!(body)
    assert Enum.count(bodies, &(&1["params"]["name"] == "http_error")) == 1
  end

  test "caller deadlines return timeout tuples", %{origin: origin} do
    client = connect(origin)
    assert {:error, %Error{kind: :timeout}} = T3.call_tool(%{client | timeout: 25}, "slow")
  end

  test "unauthenticated and incompatible handshakes fail", %{origin: origin} do
    assert {:error, %Error{}} = T3.new(url: origin <> "/json", timeout: 1000) |> T3.connect()

    assert {:error, %Error{}} =
             T3.new(url: origin <> "/bad-version", token: "fixture-token", timeout: 1000)
             |> T3.connect()
  end

  test "external client discovers projects before listing threads", %{origin: origin} do
    client = connect(origin)
    assert {:error, %Error{kind: :tool}} = T3.Threads.list(client)
    assert {:ok, result} = T3.Projects.list(client)
    assert {:ok, %{"projects" => [%{"id" => id}]}} = T3.Result.data(result)
    assert {:ok, result} = T3.Threads.list(client, %{"projectId" => id})
    assert {:ok, %{"threads" => []}} = T3.Result.data(result)

    assert {:error, %Error{kind: :protocol}} =
             T3.Result.data(%{"content" => [%{"type" => "text", "text" => "invalid"}]})
  end

  test "closed clients can reconnect", %{origin: origin} do
    client = connect(origin)
    :ok = Client.close(client)
    assert {:ok, fresh} = T3.connect(client)

    try do
      refute fresh.supervisor == client.supervisor
      assert {:ok, _} = T3.Threads.list(fresh, %{"projectId" => "project-1"})
    after
      Client.close(fresh)
    end
  end

  test "uninitialized calls fail and secrets are hidden" do
    client = T3.new(url: "http://localhost/mcp", token: "private-token")
    assert {:error, %Error{kind: :protocol}} = T3.list_tools(client)
    refute inspect(client) =~ "private-token"

    for url <- [
          "http://example.com/mcp",
          "https://user:pass@example.com/mcp",
          "https://example.com/mcp?token=secret",
          "https:/mcp"
        ] do
      assert_raise ArgumentError, fn -> T3.new(url: url) end
    end
  end

  defp collect_requests(acc) do
    receive do
      {:request, _, _, _, _} = request -> collect_requests([request | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end
end
