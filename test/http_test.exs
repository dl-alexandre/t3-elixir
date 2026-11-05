defmodule T3.HTTPTest.Fixture do
  @behaviour Plug
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, opts) do
    {:ok, body, conn} = read_body(conn)

    send(
      opts[:owner],
      {:http_request, conn.method, conn.request_path, conn.query_string, conn.req_headers, body}
    )

    case conn.request_path do
      "/upload" ->
        conn |> put_resp_content_type("application/octet-stream") |> send_resp(200, body)

      "/redirect" ->
        conn
        |> put_resp_header("location", "http://127.0.0.1:1/never")
        |> send_resp(302, "redirect")

      "/unauthorized" ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(401, JSON.encode!(%{error: "unauthorized"}))

      "/large" ->
        send_resp(conn, 200, String.duplicate("x", 5000))

      "/slow" ->
        Process.sleep(100)
        send_resp(conn, 200, "late")

      "/invalid-json" ->
        conn |> put_resp_content_type("application/json") |> send_resp(200, "{")

      "/empty" ->
        send_resp(conn, 204, "")

      _ ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(
          200,
          JSON.encode!(%{
            method: conn.method,
            path: conn.request_path,
            query: conn.query_string,
            body: body
          })
        )
    end
  end
end

defmodule T3.HTTPTest do
  use ExUnit.Case, async: true
  alias T3.HTTP

  setup do
    server =
      start_supervised!(
        {Bandit,
         plug: {T3.HTTPTest.Fixture, owner: self()},
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)
    {:ok, http: HTTP.new(base_url: "http://127.0.0.1:#{port}", token: "private-token")}
  end

  test "catalog matches every contract route, including PUT webhooks", %{http: http} do
    assert length(HTTP.endpoints()) == 38
    contract = File.read!(Path.expand("../priv/t3/environmentHttp.ts", __DIR__))

    declared =
      Regex.scan(
        ~r/HttpApiEndpoint\.(get|post|put|patch|delete)\("[^"]+", ("[^"]+"|WEBHOOK_PATH)/,
        contract,
        capture: :all_but_first
      )
      |> Enum.map(fn [method, path] ->
        path =
          if path == "WEBHOOK_PATH",
            do: "/api/hooks/:hookId/:token",
            else: String.trim(path, "\"")

        {method, path}
      end)
      |> MapSet.new()

    implemented =
      HTTP.endpoints() |> Enum.map(&{Atom.to_string(&1.method), &1.path}) |> MapSet.new()

    assert implemented == declared
    assert Enum.any?(HTTP.endpoints(), &(&1.id == :webhooks_put and &1.method == :put))

    for spec <- HTTP.endpoints() do
      params = Map.new(spec.path_params, &{&1, "value"})
      assert {:ok, %HTTP.Response{status: 200}} = HTTP.call(http, spec.id, params: params)
    end
  end

  test "all named helpers dispatch their declared route", %{http: http} do
    for spec <- HTTP.endpoints() do
      group =
        %{
          metadata: HTTP.Metadata,
          auth: HTTP.Auth,
          oauth: HTTP.OAuth,
          orchestration: HTTP.Orchestration,
          projects: HTTP.Projects,
          pull_requests: HTTP.PullRequests,
          connect: HTTP.Connect,
          webhooks: HTTP.Webhooks
        }[spec.group]

      args = [http] ++ Enum.map(spec.path_params, fn _ -> "value" end)
      assert {:ok, %HTTP.Response{status: 200}} = apply(group, spec.name, args)
    end
  end

  test "encodes path segments and query without changing wire keys", %{http: http} do
    assert {:ok, response} =
             HTTP.Orchestration.thread_history_page(http, "thread /&",
               query: %{"cursor" => "a & b", "view" => "activity"}
             )

    assert response.body["path"] == "/api/orchestration/threads/thread%20%2F%26/history"

    assert URI.decode_query(response.body["query"]) == %{
             "cursor" => "a & b",
             "view" => "activity"
           }

    assert_receive {:http_request, "GET", _, _, headers, _}
    assert {"authorization", "Bearer private-token"} in headers
    assert {"x-t3-orchestration-protocol", "2"} in headers
  end

  test "uses JSON or form per contract and sends exact upload bytes", %{http: http} do
    assert {:ok, response} =
             HTTP.Projects.mutate(http, json: %{"_tag" => "create", "title" => "Project"})

    assert JSON.decode!(response.body["body"])["title"] == "Project"

    assert {:ok, response} =
             HTTP.OAuth.token(http,
               form: %{"code" => "a+b & c", "grant_type" => "authorization_code"}
             )

    assert URI.decode_query(response.body["body"])["code"] == "a+b & c"

    assert {:ok, response} =
             HTTP.upload(http, "/upload?capability=a%2Bb%2Fc", <<0, 1, 2, 255>>, decode: :binary)

    assert response.body == <<0, 1, 2, 255>>
    assert_receive {:http_request, "POST", "/api/projects/mutate", _, headers, _}
    assert {"content-type", "application/json"} in headers
    assert_receive {:http_request, "POST", "/oauth/mcp/token", _, headers, _}
    assert {"content-type", "application/x-www-form-urlencoded"} in headers
    assert_receive {:http_request, "POST", "/upload", "capability=a%2Bb%2Fc", _, <<0, 1, 2, 255>>}
  end

  test "no token is required for public metadata and secret Inspect hides credentials", %{
    http: http
  } do
    public = %{http | token: nil}
    assert {:ok, _} = HTTP.Metadata.descriptor(public)
    assert_receive {:http_request, "GET", _, _, headers, _}
    refute List.keymember?(headers, "authorization", 0)
    refute inspect(http) =~ "private-token"
    secret = %{http | token: ConduitMcp.Client.Secret.new("wrapped-token")}
    assert {:ok, response} = HTTP.Auth.session(secret)
    refute inspect(response) =~ "wrapped-token"
    assert_receive {:http_request, "GET", _, _, headers, _}
    assert {"authorization", "Bearer wrapped-token"} in headers
  end

  test "redirects and HTTP errors are returned with status and never followed", %{http: http} do
    assert {:error, %T3.Error{kind: :http, code: 302, details: %HTTP.Response{headers: headers}}} =
             HTTP.request(http, :get, "/redirect")

    assert {"location", "http://127.0.0.1:1/never"} in headers

    assert {:error,
            %T3.Error{
              kind: :http,
              code: 401,
              details: %HTTP.Response{body: %{"error" => "unauthorized"}}
            }} = HTTP.request(http, :get, "/unauthorized")

    assert_receive {:http_request, "GET", "/redirect", _, _, _}
    assert_receive {:http_request, "GET", "/unauthorized", _, _, _}
    refute_receive {:http_request, _, _, _, _, _}
  end

  test "rejects cross-origin requests and unsafe configuration", %{http: http} do
    for path <- [
          "https://elsewhere.example/",
          "//elsewhere.example/",
          "/path#fragment",
          "/\\elsewhere"
        ] do
      assert {:error, %T3.Error{kind: :configuration}} = HTTP.request(http, :get, path)
    end

    for origin <- [
          "http://example.com",
          "https://user:secret@example.com",
          "https://example.com/mcp",
          "https://example.com?secret=x"
        ] do
      assert_raise ArgumentError, fn -> HTTP.new(base_url: origin) end
    end

    assert {:error, %T3.Error{kind: :configuration}} =
             HTTP.request(http, :get, "/path", headers: [{"host", "elsewhere"}])

    assert {:error, %T3.Error{kind: :configuration}} =
             HTTP.request(http, :post, "/path", json: %{}, body: "bytes")

    assert {:error, %T3.Error{kind: :configuration}} =
             HTTP.call(http, :orchestration_thread_snapshot)

    refute_receive {:http_request, _, _, _, _, _}
  end

  test "bounds responses and deadlines and reports malformed JSON", %{http: http} do
    assert {:error, %T3.Error{kind: :protocol}} =
             HTTP.request(http, :get, "/large", max_body_bytes: 20)

    assert {:error, %T3.Error{kind: :transport}} = HTTP.request(http, :get, "/slow", timeout: 10)
    assert {:error, %T3.Error{kind: :protocol}} = HTTP.request(http, :get, "/invalid-json")
    assert {:ok, %HTTP.Response{status: 204, body: nil}} = HTTP.request(http, :get, "/empty")
  end
end
