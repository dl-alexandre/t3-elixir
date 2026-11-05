# T3

An independent Elixir SDK for T3 Code: **MCP, HTTP JSON, WebSocket RPC,
raw media/device streams, and the local CLI**. Targets Elixir 1.20 and OTP 29 on Linux
or macOS. Not yet published to Hex.

The pinned inventory covers **71 MCP tools**, **38 HTTP routes**, **211 WebSocket
RPC methods (27 streams)**, **45 additional HTTP operations**, **4 raw WebSocket routes**,
and **16 CLI command families**. Named helpers are backed
by generic transports for future server additions. [INTERFACES.md](INTERFACES.md)
lists every operation, its source revision, authentication and coverage limits.

## Installation

Before publication, use the repository dependency:

```elixir
{:t3, github: "dl-alexandre/t3-elixir"}
```

After the first Hex release, use `{:t3, "~> 0.1.0"}`. The package has not yet
been published to Hex. Local development can use `{:t3, path: "/path/to/t3-elixir"}`.

Dependencies handle the hard parts: ConduitMCP for MCP/OAuth, Finch for HTTP,
Mint.WebSocket for WebSocket framing, Multipart for uploads, Exile for subprocess IO/lifecycle, and ExDoc
for documentation. Exile builds native code and requires a C compiler and `make`.
No JavaScript runtime or Python is required to use the SDK.

## MCP: sign in and list threads

```sh
mix deps.get
mix run examples/list_threads.exs
```

Open the printed URL and approve read-only access in T3, then select a project.
A temporary loopback listener handles the callback. Set `T3_MCP_URL` for another
environment; the default is `http://127.0.0.1:3773/mcp`. Set `T3_PROJECT_ID` to skip
the project prompt. Credentials stay in memory; the example closes its connection.

Inside your own tool:

```elixir
client = T3.new(url: mcp_url)
{:ok, client} = T3.OAuth.login(client, open: &IO.puts/1)
{:ok, client} = T3.connect(client)
try do
  {:ok, tools} = T3.discover(client)
  {:ok, projects_result} = T3.Projects.list(client)
  {:ok, projects} = T3.Result.data(projects_result)
  {:ok, result} = T3.Threads.list(client, %{"projectId" => project_id, "limit" => 10})
  T3.Result.data(result)
after
  T3.close(client)
end
```

`connect/1` starts a linked supervised connection. Helpers return the full MCP
result envelope; `T3.Result.data/1` extracts structuredContent or a JSON text block.
Failures return `{:error, %T3.Error{}}`; a tool's `isError` becomes `kind: :tool`.
Optional argument maps use T3's original string keys. External clients must supply
explicit project/thread targets; they do not inherit the agent context of this IDE.

Every known MCP operation has an exact wire-name helper:

```elixir
T3.Tools.t3_thread_configure(client, %{"threadId" => id})
T3.Tools.t3_queue(client, %{"threadId" => id, "action" => "list"})
T3.Tools.t3_worktree_list(client, %{"threadId" => id})
T3.Tools.list_thread_pull_requests(client, %{"threadId" => id})
T3.call_tool(client, "any_new_advertised_tool", %{})
```

Shorter category modules cover threads, projects, tasks, environments, schedules,
queues, pending requests, attachments, worktrees, pull requests, previews, devices
and HTML rendering. `T3.Catalog.compare/1` reports differences from a server's
actual discovered tools. Some tools require a T3-launched agent context and are
not exposed to external OAuth clients even with full access.

## HTTP JSON

HTTP credentials are configured separately; an MCP OAuth token does not imply
access to the application HTTP APIs.

```elixir
http = T3.HTTP.new(base_url: environment_origin, token: environment_access_token)
{:ok, response} = T3.HTTP.Orchestration.thread_transcript(http, thread_id)
response.body

T3.HTTP.call(http, :orchestration_thread_history_page,
  params: %{"threadId" => thread_id}, query: %{"cursor" => cursor})
```

Named modules cover metadata, auth, OAuth, orchestration, projects, PR diffs,
Connect and webhooks. Use `json: map`, `form: map`, or `body: bytes` for the
contract's payload encoding. `T3.HTTP.upload/4` posts attachment bytes to a
same-origin relative upload URL, preserving signed queries. `request/4` permits
new same-origin routes. Responses retain status/headers/body; Inspect hides data.
No automatic redirects, retries, cookie jar or token renewal is enabled. Set
`auth_scheme: "DPoP"` and a `dpop` proof header for proof-bound credentials.

## WebSocket RPC and subscriptions

Obtain an RPC ticket with an appropriately scoped environment credential:

```elixir
{:ok, response} = T3.HTTP.Auth.web_socket_ticket_for(http, "rpc")
{:ok, rpc} = T3.RPC.start_link(url: websocket_url, ticket: response.body["ticket"])
try do
  {:ok, config} = T3.RPC.Methods.server_get_config(rpc)
  {:ok, id} = T3.RPC.subscribe(rpc, "orchestration.subscribeShell", %{})
  receive do
    {:t3_rpc, ^id, {:chunk, values}} ->
      IO.inspect(values)
      :ok = T3.RPC.ack(rpc, id)
  end
  :ok = T3.RPC.unsubscribe(rpc, id)
after
  T3.RPC.close(rpc)
end
```

Alternatively supply an environment `token:` directly, with caller-supplied
`dpop:` proof when required. T3 rejects MCP OAuth client credentials on this
surface. `T3.RPC.Methods` exposes every catalog method; `call/4` and `subscribe/4`
accept arbitrary method strings. Streams require explicit ACK after consuming a
chunk. Deadlines, bounded pending requests, subscriber monitoring, cancellation,
connection cleanup and server-request replies are implemented. Calls are never
replayed after disconnect. Constructing/signing DPoP proofs remains caller-owned.

## Guest shares, browser and device streams

Additional routes outside the typed HTTP contract are covered by `T3.HTTP.Raw`,
`Guest`, `Media` and `DeviceHub`. These include guest redemption/messages/history,
SSE updates, asset downloads/ranges, capability uploads, browser file pickers,
OTLP traces, screenshots, accessibility and device MJPEG/AVCC/WebRTC signalling.
Guest cookies, share parameters and media credentials are supplied explicitly.

```elixir
T3.HTTP.Guest.stream(http, fn
  {:event, event} -> IO.puts(event.data); :cont
  _ -> :cont
end, query: %{"share" => share_id}, headers: [{"cookie", guest_cookie}], timeout: 60_000)

multipart = T3.HTTP.multipart(%{}, [{"files", "/absolute/path/to/file.png"}])
T3.HTTP.Media.preview_upload(http, multipart,
  query: %{"threadId" => thread_id, "tabId" => tab_id, "chooser" => chooser_id})
```

`HTTP.stream/5` provides binary chunks or incremental SSE events with callback
backpressure, byte/event bounds and hard deadlines. `start_stream/5` and
`cancel_stream/1` manage cancellable Tasks. Callback `self()` is its isolated
worker; capture the caller PID when forwarding events. Media bytes are not
transcoded, and WebRTC signalling does not itself decode/play a WebRTC session.

For preview JPEG frames or device raw WebSockets, use a media ticket and the
separate raw transport (not Effect RPC):

```elixir
{:ok, response} = T3.HTTP.Auth.web_socket_ticket_for(http, "media")
{:ok, socket} = T3.WebSocket.Routes.preview(websocket_origin, thread_id, tab_id,
  ticket: response.body["ticket"])
try do
  receive do
    {:t3_web_socket, ^socket, ref, {:binary, jpeg}} ->
      consume_jpeg(jpeg)
      :ok = T3.WebSocket.Routes.preview_ack(socket, ref)
  end
after
  T3.WebSocket.close(socket)
end
```

Other raw routes cover device discovery, simulator and emulator channels.
`T3.WebSocket` preserves text/binary frames and supports send/ACK/ping/pong,
backlog/partial-message limits, owner monitoring and idle/lifetime deadlines.
Local ACK releases delivery memory; preview ACK also sends its server protocol ACK.

## Local CLI

```elixir
cli = T3.CLI.new(executable: "t3", timeout: 30_000)
T3.CLI.version(cli)
T3.CLI.commands(cli) # discover this installed version
T3.CLI.project(cli, ["--help"])
T3.CLI.run(cli, ["any-command", "literal argument with spaces"])
T3.CLI.run(cli, ["thread", "send", thread_id, "-"], input: "message via stdin")
```

Arguments are passed without a shell. Command-family helpers and a generic runner
support the installed executable, with bounded output/deadlines, streaming,
stdin/EOF and cancellation. Linux/macOS are supported; there is no PTY emulator
or arbitrary inherited-file-descriptor API. CLI commands can differ by release:
our installed `t3 v0.1.1` lacks newer `t3 thread` commands. The SDK does not upgrade
or start T3 automatically. See `T3.CLI` documentation for interactive process IO.

## Authentication and lifecycle

MCP sign-in explicitly requests `orchestration:read` by default. To request writes,
pass `scope: "orchestration:read orchestration:operate"`; T3 approval still sets
the allowed permission mode. HTTPS/WSS are required except on loopback.

For apps with their own callback, use `T3.OAuth.begin/2` and `complete/2`. Store the
flow privately and consume it once. Tokens are secret-wrapped. T3.Application
runs a shared in-memory store; `oauth_options: [store: {YourStore, options}]` can
replace it. Loopback OAuth enables Conduit's explicit development exception;
private HTTPS OAuth hosts may need `oauth_options: [allow_private: ["your-CIDR"]]`.
The simple MCP facade uses the signed-in bearer token; it does not automatically
refresh an existing connection. Reauthorize and reconnect when needed, or use
Conduit's managed OAuth APIs for refresh. Do not log callbacks or secret results.

After an ambiguous mutation timeout, inspect T3 state before retrying: work may
have started. The SDK preserves T3's original wire payloads and relies on the
server for TypeScript schema validation; it does not invent local typed models
or elevate permissions. Static inventories describe the pinned upstream contract,
not a guarantee of access to every operation on every installed server.

## Development and package inventory

```sh
mix t3.interfaces
mix t3.interfaces --json
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix docs --warnings-as-errors
mix hex.build
```

Tests cover actual ephemeral HTTP/WebSocket fixtures and subprocesses, complete
catalog routing, session handling, OAuth, streaming back-pressure, cancellation,
errors and bounds. The running T3 server's metadata, OAuth discovery/registration,
CLI version/help and unauthenticated WebSocket protocol responses were checked.
Authenticated live HTTP/RPC operations and destructive operations were not run.

Conduit is pinned to `~> 0.11.0`; it includes Plug/Bandit, server-related runtime
processes and an exact NimbleOptions 1.1.1 dependency. Dependency experiments are
in `docs/dependency-evaluation.md` and `evaluation/README.md`.

The package archive is local, not published. Before publishing, choose the
permanent package name, add repository/maintainer metadata, verify real workflows
with appropriate credentials and authenticate to Hex.

## CI, live testing and release readiness

The local fixture suite excludes live tests by default. See [LIVE_TESTING.md](LIVE_TESTING.md)
for opt-in read-only probes and [RELEASE.md](RELEASE.md) for the CI matrix and publication
checklist. GitHub Actions is configured for Linux/macOS with Elixir 1.20.5 / OTP 29.1.2; it
runs when the repository is pushed. No CI publishing
or live-environment credentials are configured.
