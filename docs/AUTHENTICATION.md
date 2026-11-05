# Authentication

T3 has several credential audiences. Choose the interface first; an MCP sign-in
is not a native environment session. Every SDK helper is still subject to T3's
server-side scopes, permission mode and invocation context.

## External MCP clients

Copy the MCP URL from **T3 Settings → Environments**. It ends in `/mcp`.

```elixir
client = T3.new(url: "http://127.0.0.1:3773/mcp")
{:ok, client} = T3.OAuth.login(client, open: &IO.puts/1)
{:ok, client} = T3.connect(client)
```

Open the printed authorization URL yourself. In T3, select **Read only** for
project/thread discovery, enter a pairing code from **Sharing & access**, and
approve. Keep the calling process alive while the callback listener waits.
`login/2` does not launch a browser automatically. Its `:timeout` controls how long
it waits for approval; `connect/1` starts the subsequent MCP session.

The default scope is explicitly `orchestration:read`. To request mutations, use
`scope: "orchestration:read orchestration:operate"`. Approval still limits the
runtime mode. Full-access approval does not turn an external client into an
in-app agent; browser/device/delegation tools may require agent context.

Apps serving their own callback use `T3.OAuth.begin/2` and `complete/2`. Keep the
flow server-side, look it up and consume it once before completing the exchange.
A callback must match the registered URI, state, issuer and expiration checks.
T3's SDK token store is in memory; tokens are not written to disk. The facade uses
a bearer token and does not refresh an existing MCP connection automatically.
Reauthorize and create a new connection on expiry/revocation. Conduit's managed
OAuth APIs are available to applications needing automatic refresh.

## Native HTTP and Effect RPC

These use an environment access token or an appropriate route-bound ticket.
For a script running on the T3 host, the installed CLI can issue a scoped bearer
session. Check `t3 auth session issue --help` for your T3 version. Run this yourself
in a trusted terminal on that host:

```sh
export T3_ENVIRONMENT_TOKEN="$(t3 auth session issue --scope orchestration:read --ttl 1h --label t3-sdk-read --token-only)"
```

Specifying `--scope` replaces the CLI's broad default scopes. This example grants
only orchestration reads. It creates a real credential; do not enable shell
tracing, print it, or commit it. If T3 uses a non-default data directory, pass the
corresponding `--base-dir`. For a remote environment, obtain the credential using
that host's authorized access flow and deliver it through your secret manager.
Do not assume a locally issued token belongs to a different environment.

```elixir
http = T3.HTTP.new(
  base_url: "http://127.0.0.1:3773",
  token: System.fetch_env!("T3_ENVIRONMENT_TOKEN")
)
{:ok, response} = T3.HTTP.Orchestration.shell_snapshot(http)
```

Obtain a single-use RPC ticket through the native HTTP client:

```elixir
{:ok, response} = T3.HTTP.Auth.web_socket_ticket_for(http, "rpc")
{:ok, rpc} = T3.RPC.start_link(
  url: "ws://127.0.0.1:3773/ws",
  ticket: response.body["ticket"]
)
```

Keep proof-bound credentials separate: HTTP accepts `auth_scheme: "DPoP"` with
a `dpop` header; RPC accepts `dpop:` and the matching auth scheme. The caller
creates/signs proofs and handles nonces; the SDK does not manage signing keys.
A proof for a bearer token is not reusable for a different ticket or request.
Use the server's expected proof audience and hashed credential.

## Media and device streams

Use a native environment credential with the required read/operate scopes or a
`"media"` ticket from `web_socket_ticket_for/3`. Preview controls additionally
require preview-operate permission; simulator/emulator control channels may
require orchestration operate. See `T3.WebSocket.Routes` for route-specific scopes.
The SDK does not grant these scopes or boot/select devices implicitly.

## Guest shares and attachment capabilities

Guest-share redemption returns a share-specific cookie. Retain that cookie in
your application and send it with the share query; a bearer token is not a guest
session. The HTTP client does not maintain a cookie jar. Treat Set-Cookie and
cookie headers as secrets.

Prepared attachment URLs contain signed capabilities. Post the exact bytes using
`T3.HTTP.upload/4` to the same environment origin. Do not log signed URL queries.

## Transport and credential lifetime

Use HTTPS/WSS outside loopback. Custom private HTTPS OAuth hosts may require
explicit `oauth_options: [allow_private: ["your-CIDR"]]`. Close connections when
finished. Inspect output hides token/result data, but direct field access and
error details can contain credentials or private server content.
