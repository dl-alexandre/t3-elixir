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

## Local service accounts without interactive sign-in

A board node talking only to its own localhost T3 can use `T3.LocalAuth`. This
uses the installed CLI's native auth control plane under the service's OS user;
it does not open a browser or need MCP OAuth. The service user must have access
to the correct T3 data directory and executable. Use a dedicated OS account and
explicit `base_dir` if your T3 installation does not use its default directory.
The helper does not create an OS account or grant access to another user's T3.

Start the credential provider before the reader in your supervision tree:

```elixir
children = [
  {T3.LocalAuth,
   name: MyApp.T3Auth,
   base_url: "http://127.0.0.1:3773",
   ttl: "24h",
   scopes: ["orchestration:read"],
   label: "board-reader"}
]
```

Pass this function to a reconnecting reader; invoke it anew for each connection:

```elixir
connect = fn -> T3.LocalAuth.connection_options(MyApp.T3Auth) end
{:ok, rpc_options} = connect.()
{:ok, rpc} = T3.RPC.start_link(rpc_options)
:ok = T3.RPC.close(rpc)
```

The provider caches one owned environment session, renews it when connection
options are requested within 60 seconds of expiry, and revokes the prior session.
It never mints a session for every reconnect while the existing session remains
usable. Set `renew_before:` in milliseconds to adjust that window. Renewal is
lazy at connection time, not a refresh of an already connected socket; a reader
must reconnect after server expiry/revocation. Call `T3.LocalAuth.invalidate/1`
when a cached session is revoked early, before requesting replacement options.
A normal supervisor shutdown attempts to revoke owned sessions; forced OS kills
can leave them until their TTL expires. A 24-hour TTL bounds that exposure while
avoiding interactive service boots.

Set `ticket: true` on the provider to use single-use RPC tickets. Each request for
connection options obtains a fresh `"rpc"` ticket over local HTTP; the underlying
environment token is still cached. Never reuse a ticket after a failed handshake.
The provider only accepts loopback HTTP(S) origins, including IPv6 `[::1]`.
Tokens stay in memory and are redacted in process status. Returned RPC options
contain credentials and must not be logged or included in crash metadata.

For one-off provisioning, `T3.LocalAuth.issue/1` returns an opaque credential;
the caller owns its lifetime and must use `T3.LocalAuth.revoke/2` with the same
CLI/data-directory options. For a service, the supervised provider is preferred.
No runtime dependency on Python, a shell script or an OAuth callback is needed.

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
