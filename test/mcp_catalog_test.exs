defmodule T3.MCPCatalogFixture do
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    {:ok, body, conn} = read_body(conn)

    cond do
      conn.method == "DELETE" -> send_resp(conn, 204, "")
      conn.method != "POST" -> send_resp(conn, 405, "")
      true -> rpc(conn, JSON.decode!(body), opts)
    end
  end

  defp rpc(conn, %{"method" => "initialize", "id" => id}, _opts) do
    conn
    |> put_resp_header("mcp-session-id", "catalog-session")
    |> reply(id, %{
      protocolVersion: "2025-06-18",
      capabilities: %{tools: %{}},
      serverInfo: %{name: "MCP catalog fixture", version: "1.0"}
    })
  end

  defp rpc(conn, request, opts) do
    if get_req_header(conn, "mcp-session-id") != ["catalog-session"] do
      send_resp(conn, 400, "missing session")
    else
      case request do
        %{"method" => "notifications/initialized"} ->
          send_resp(conn, 202, "")

        %{"method" => "tools/call", "id" => id, "params" => params} ->
          reply(conn, id, %{content: [], structuredContent: params, isError: false})

        %{"method" => "tools/list", "id" => id} ->
          cursor = request["params"]["cursor"]
          name = if cursor, do: "future_tool", else: "t3_project_list"
          next_cursor = if opts[:cycle] == true or is_nil(cursor), do: "second-page", else: nil

          reply(conn, id, %{
            tools: [
              %{
                name: name,
                description: "Fixture tool",
                inputSchema: %{type: "object", properties: %{}}
              }
            ],
            nextCursor: next_cursor
          })
      end
    end
  end

  defp reply(conn, id, result),
    do:
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, JSON.encode!(%{jsonrpc: "2.0", id: id, result: result}))
end

defmodule T3.MCPCatalogTest do
  use ExUnit.Case, async: true

  defp connect(opts \\ []) do
    server =
      start_supervised!(
        {Bandit,
         plug: {T3.MCPCatalogFixture, opts}, ip: {127, 0, 0, 1}, port: 0, startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    {:ok, client} = T3.new(url: "http://127.0.0.1:#{port}/mcp", timeout: 2000) |> T3.connect()
    on_exit(fn -> T3.Client.close(client) end)
    client
  end

  test "all canonical and category helpers send exact wire names and original arguments" do
    client = connect()

    for descriptor <- T3.Catalog.tools() do
      args = %{
        "sentinel" => %{"nested" => [1, true, nil]},
        "projectId" => "project",
        "threadId" => "thread",
        "taskId" => "task"
      }

      expected = %{"name" => descriptor.name, "arguments" => args}

      assert {:ok, %{"structuredContent" => ^expected}} =
               apply(T3.Tools, descriptor.canonical_function, [client, args])

      assert {:ok, %{"structuredContent" => ^expected}} =
               apply(descriptor.module, descriptor.function, [client, args])
    end
  end

  test "catalog exactly matches the versioned manifest with no duplicate names" do
    manifest =
      Path.join(:code.priv_dir(:t3), "t3/mcp_tools.json") |> File.read!() |> JSON.decode!()

    assert manifest["upstream_ref"] == T3.Catalog.upstream_ref()
    assert Enum.sort(Enum.map(manifest["tools"], & &1["name"])) == Enum.sort(T3.Catalog.names())
    assert length(T3.Catalog.names()) == 71
    assert length(Enum.uniq(T3.Catalog.names())) == 71

    assert {:ok, %{module: T3.Environments, function: :link}} =
             T3.Catalog.fetch("t3_environment_link")

    assert T3.Catalog.fetch("future_tool") == :error
    assert Enum.all?(T3.Catalog.tools(:projects), &(&1.module == T3.Projects))
    assert Enum.count(T3.Catalog.tools(), & &1.advertised_in_session) == 66
  end

  test "discovery follows cursors and comparison identifies future tools" do
    client = connect()
    assert {:ok, [first, second]} = T3.Catalog.discover(client)
    assert first["name"] == "t3_project_list"
    assert second["name"] == "future_tool"
    assert {:ok, comparison} = T3.Catalog.compare(client)
    assert [%{name: "t3_project_list"}] = comparison.available
    assert [%{"name" => "future_tool"}] = comparison.unwrapped
    assert length(comparison.unavailable) == 70
  end

  test "discovery refuses cursor loops instead of polling forever" do
    client = connect(cycle: true)

    assert {:error, %T3.Error{kind: :protocol, message: "tool discovery repeated a cursor"}} =
             T3.Catalog.discover(client)
  end
end
