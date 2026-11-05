defmodule T3.TestFixture do
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    {:ok, body, conn} = read_body(conn)
    origin = "http://127.0.0.1:#{conn.port}"
    send(opts[:owner], {:request, conn.method, conn.request_path, conn.req_headers, body})

    cond do
      conn.method == "GET" and
          String.starts_with?(conn.request_path, "/.well-known/oauth-protected-resource") ->
        json(conn, %{
          resource: origin <> "/json",
          authorization_servers: [origin],
          scopes_supported: ["orchestration:read", "orchestration:operate"]
        })

      conn.request_path == "/.well-known/oauth-authorization-server" ->
        json(conn, %{
          issuer: origin,
          authorization_endpoint: origin <> "/authorize",
          token_endpoint: origin <> "/token",
          registration_endpoint: origin <> "/register",
          response_types_supported: ["code"],
          grant_types_supported: ["authorization_code"],
          code_challenge_methods_supported: ["S256"],
          token_endpoint_auth_methods_supported: ["none"],
          authorization_response_iss_parameter_supported: true
        })

      conn.request_path == "/register" ->
        json(conn, %{client_id: "registered-client"})

      conn.request_path == "/token" ->
        json(conn, %{
          access_token: "fixture-token",
          token_type: "Bearer",
          expires_in: 3600,
          scope: "orchestration:read"
        })

      conn.method == "DELETE" ->
        send_resp(conn, 204, "")

      conn.method != "POST" ->
        send_resp(conn, 405, "")

      get_req_header(conn, "authorization") != ["Bearer fixture-token"] ->
        send_resp(conn, 401, "")

      true ->
        rpc(conn, JSON.decode!(body))
    end
  end

  defp rpc(conn, %{"method" => "initialize", "id" => id}) do
    version = if conn.request_path == "/bad-version", do: "unknown", else: "2025-06-18"

    conn
    |> put_resp_header("mcp-session-id", "fixture-session")
    |> reply(id, %{
      protocolVersion: version,
      capabilities: %{tools: %{}},
      serverInfo: %{name: "T3 Fixture", version: "1.0"}
    })
  end

  defp rpc(conn, request) do
    if get_req_header(conn, "mcp-session-id") != ["fixture-session"] do
      send_resp(conn, 400, "missing session")
    else
      case request do
        %{"method" => "notifications/initialized"} ->
          send_resp(conn, 202, "")

        %{"method" => "tools/list", "id" => id} ->
          reply(conn, id, %{
            tools: [
              %{
                name: "t3_thread_list",
                description: "List threads",
                inputSchema: %{type: "object"}
              }
            ],
            nextCursor: "page-2"
          })

        %{"method" => "tools/call", "id" => _id, "params" => %{"name" => "http_error"}} ->
          send_resp(conn, 503, "")

        %{"method" => "tools/call", "id" => id, "params" => %{"name" => "t3_project_list"}} ->
          reply(conn, id, %{
            content: [
              %{
                type: "text",
                text:
                  JSON.encode!(%{
                    projects: [%{id: "project-1", title: "Fixture"}],
                    nextCursor: nil
                  })
              }
            ]
          })

        %{
          "method" => "tools/call",
          "id" => id,
          "params" => %{"name" => "t3_thread_list", "arguments" => args}
        }
        when not is_map_key(args, "projectId") ->
          reply(conn, id, %{
            content: [
              %{
                type: "text",
                text: "Pass projectId: this MCP client is not running inside a T3 thread."
              }
            ],
            isError: true
          })

        %{"method" => "tools/call", "id" => id, "params" => %{"name" => "rpc_error"}} ->
          json(conn, %{
            jsonrpc: "2.0",
            id: id,
            error: %{code: -32602, message: "invalid argument"}
          })

        %{"method" => "tools/call", "id" => id, "params" => %{"name" => "tool_error"}} ->
          reply(conn, id, %{content: [%{type: "text", text: "failed"}], isError: true})

        %{"method" => "tools/call", "id" => id, "params" => %{"name" => "slow"}} ->
          Process.sleep(150)
          reply(conn, id, %{content: []})

        %{"method" => "tools/call", "id" => id} ->
          reply(conn, id, %{
            content: [],
            structuredContent: %{threads: []},
            isError: false,
            _meta: %{fixture: true}
          })

        _ ->
          send_resp(conn, 202, "")
      end
    end
  end

  defp reply(conn, id, result) do
    envelope = %{jsonrpc: "2.0", id: id, result: result}

    if conn.request_path == "/sse" do
      conn
      |> put_resp_content_type("text/event-stream")
      |> send_resp(200, "event: message\ndata: " <> JSON.encode!(envelope) <> "\n\n")
    else
      json(conn, envelope)
    end
  end

  defp json(conn, value),
    do: conn |> put_resp_content_type("application/json") |> send_resp(200, JSON.encode!(value))
end
