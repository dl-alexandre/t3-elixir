defmodule T3.LocalAuthTest.TicketFixture do
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, owner) do
    send(owner, {:ticket_request, conn.request_path, get_req_header(conn, "authorization")})
    ticket = "private-ticket-#{System.unique_integer([:positive])}"

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, JSON.encode!(%{"ticket" => ticket}))
  end
end

defmodule T3.LocalAuthTest do
  use ExUnit.Case, async: true
  alias T3.{CLI, LocalAuth}

  setup do
    dir = Path.join(System.tmp_dir!(), "t3-local-auth-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    exe = Path.join(dir, "t3-fixture")

    File.write!(exe, """
    #!/bin/sh
    printf '%s\n' "$*" >> "$FIXTURE_DIR/commands"
    if [ "$3" = "issue" ]; then
      count=0
      if [ -f "$FIXTURE_DIR/count" ]; then read -r count < "$FIXTURE_DIR/count"; fi
      count=$((count + 1))
      printf '%s' "$count" > "$FIXTURE_DIR/count"
      if [ "$FIXTURE_FAIL" = "yes" ]; then
        printf 'private-failed-token'; exit 7
      fi
      printf '{"sessionId":"session-%s","token":"private-token-%s","expiresAt":"%s"}' "$count" "$count" "$FIXTURE_EXPIRY"
    fi
    """)

    File.chmod!(exe, 0o700)
    expiry = DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_iso8601()
    cli = CLI.new(executable: exe, env: [{"FIXTURE_DIR", dir}, {"FIXTURE_EXPIRY", expiry}])
    on_exit(fn -> File.rm_rf!(dir) end)
    %{cli: cli, dir: dir}
  end

  test "issues explicit scopes with literal arguments and hides token", %{cli: cli, dir: dir} do
    assert {:ok, credential} = LocalAuth.issue(cli: cli, base_dir: "/tmp/t3 data", ttl: "7d")
    assert credential.session_id == "session-1"
    refute inspect(credential) =~ "private-token"
    assert :ok = LocalAuth.revoke(credential, cli: cli, base_dir: "/tmp/t3 data")
    commands = File.read!(Path.join(dir, "commands"))
    assert commands =~ "--scope orchestration:read"
    assert commands =~ "--ttl 7d"
    assert commands =~ "--base-dir /tmp/t3 data"
    assert commands =~ "auth session revoke session-1"
  end

  test "reuses a session across reconnects, supports invalidation and revokes shutdown", %{
    cli: cli,
    dir: dir
  } do
    auth = start_supervised!({LocalAuth, cli: cli, base_url: "http://127.0.0.1:3773"})
    assert {:ok, first} = LocalAuth.connection_options(auth)
    assert first[:url] == "ws://127.0.0.1:3773/ws"
    assert first[:token] == "private-token-1"
    assert {:ok, ^first} = LocalAuth.connection_options(auth)
    assert File.read!(Path.join(dir, "count")) == "1"
    refute inspect(:sys.get_status(auth)) =~ "private-token"
    assert :ok = LocalAuth.invalidate(auth)
    assert {:ok, options} = LocalAuth.connection_options(auth)
    assert options[:token] == "private-token-2"
    stop_supervised!(LocalAuth)
    commands = File.read!(Path.join(dir, "commands"))
    assert commands =~ "auth session revoke session-1"
    assert commands =~ "auth session revoke session-2"
  end

  test "renews near expiry and revokes prior owned session", %{cli: cli, dir: dir} do
    auth =
      start_supervised!(
        {LocalAuth, cli: cli, base_url: "http://[::1]:3773", renew_before: 7_200_000}
      )

    assert {:ok, first} = LocalAuth.connection_options(auth)
    assert first[:url] == "ws://[::1]:3773/ws"
    assert {:ok, second} = LocalAuth.connection_options(auth)
    refute first[:token] == second[:token]
    assert File.read!(Path.join(dir, "commands")) =~ "auth session revoke session-1"
  end

  test "mints a new route-bound ticket per connect but reuses its environment session", %{
    cli: cli,
    dir: dir
  } do
    server =
      start_supervised!(
        {Bandit,
         plug: {T3.LocalAuthTest.TicketFixture, self()},
         ip: {127, 0, 0, 1},
         port: 0,
         startup_log: false}
      )

    {:ok, {_, port}} = ThousandIsland.listener_info(server)

    auth =
      start_supervised!({LocalAuth, cli: cli, base_url: "http://127.0.0.1:#{port}", ticket: true})

    assert {:ok, first} = LocalAuth.connection_options(auth)
    assert {:ok, second} = LocalAuth.connection_options(auth)
    assert first[:ticket] != second[:ticket]
    refute Keyword.has_key?(first, :token)
    assert first[:url] == "ws://127.0.0.1:#{port}/ws"

    for _ <- 1..2 do
      assert_receive {:ticket_request, "/api/auth/websocket-ticket/rpc",
                      ["Bearer private-token-1"]}
    end

    assert File.read!(Path.join(dir, "count")) == "1"
  end

  test "fails closed for non-loopback URLs and invalid scope defaults", %{cli: cli, dir: dir} do
    for url <- [
          "https://example.com",
          "http://127.0.0.1:3773/path",
          "http://user@localhost",
          "http://localhost?token=x"
        ] do
      assert {:error, %T3.Error{kind: :configuration}} =
               LocalAuth.start_link(cli: cli, base_url: url)
    end

    assert {:error, %T3.Error{}} = LocalAuth.issue(cli: cli, scopes: [])
    refute File.exists?(Path.join(dir, "commands"))
  end

  test "does not expose command output on issuance failure", %{cli: cli} do
    cli = %{cli | env: [{"FIXTURE_FAIL", "yes"} | cli.env]}
    assert {:error, error} = LocalAuth.issue(cli: cli)
    refute inspect(error) =~ "private-failed-token"
    assert error.details == nil
  end
end
