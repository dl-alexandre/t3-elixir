# T3 MCP client dependency evaluation

Evaluated 2026-11-05. Choose **conduit_mcp ~> 0.11.0**, with Finch. It replaces
our handwritten MCP framing, session lifecycle, PKCE and OAuth callback server.
This is a functional fit decision, not a latency benchmark or a security audit.

## Candidates and evidence

All versions are published Hex releases, installed independently with Mix.install.
The same local HTTP fixture enforces bearer and session headers and exercises
initialization, tool listing, structured tool calls, tool errors, RPC errors and
HTTP 503 responses. JSON and finite SSE modes are tested. Scripts and raw logs are
in `evaluation/`; these are separate experiments, not runtime dependencies.

| Candidate | JSON + SSE happy paths | Failure checks | OAuth suitability | Decision |
|---|---|---|---|---|
| Anubis 2.2.0 | Passed both | Tool/RPC/503 returned | Client discovery helper; full client flow still needs glue | Runner-up |
| ExMCP 1.8.1 | Passed both | Tool/RPC/503 returned | Broad built-in authorization machinery | Capable but broader runtime/dependencies |
| MCP Elixir SDK 1.1.0 | Passed both in initial run | Tool/RPC returned; JSON HTTP503 caused caller exit after 5s; later SSE failure cases not reached | No complete OAuth client flow found | Reject for this bridge |
| ConduitMCP 0.11.0 | Passed both | Tool/RPC/503 returned in both modes | Discovery, registration, PKCE, token store, loopback listener | Adopt |

Earlier setup mistakes were corrected before assessment: Anubis APIs take its
client name rather than the returned supervisor PID and require a Finch pool;
ExMCP headers require a list. ExMCP startup with retry_policy:false also crashed;
the final run uses max_attempts:1. Anubis needs readiness coordination before
listing tools; the final experiment waits for server info.

## Package footprint

[Hex metadata](https://hex.pm/api/packages/conduit_mcp): version 0.11.0 released
2026-10-18, Apache-2.0, Elixir ~>1.18, 151 weekly downloads when checked. Mandatory
Bandit, Plug and exact nimble_options 1.1.1; optional Finch enabled by our library.
Conduit also starts server-related ETS/janitor infrastructure even for client use.
Pinning ~>0.11.0 limits pre-1.0 minor changes; the exact NimbleOptions pin may affect
consumers' dependency resolution. Do not describe this dependency as minimal.

Anubis 2.2.0: LGPL-3.0, Elixir ~>1.18, required Finch/Peri/Telemetry; 25,639 weekly
downloads. ExMCP 1.8.1: MIT, Elixir ~>1.17; includes required Plug/Cowboy, JOSE,
JSON Schema, Mint/WebSocket and other dependencies; 2,451 weekly downloads.
MCP Elixir SDK 1.1.0: MIT, Elixir ~>1.17; Req optional but required for our HTTP
use, Jason and elixir_uuid; 494 weekly downloads. Popularity is contextual only.

Repositories showed recent pushes: Anubis Nov 2, ExMCP Nov 2, SDK Oct 26, Conduit
Oct 18. Conduit had zero open issues when checked, Anubis 11, SDK 1, ExMCP 0.
Latest Anubis workflow required action; no blanket green-CI claim is made.
Upstream coverage percentages and three-month commit counts were not measured.
We inspected published source and ran our own scenarios; this is not exhaustive.

## T3 compatibility and implementation

Conduit OAuth discovery and dynamic registration passed against the actual T3
server at localhost:3773. It selected PKCE S256 and recognized required issuer
validation. Invalid state was rejected before token exchange. No authenticated
live tool call was made: that requires a user-approved T3 sign-in.

The integrated library additionally tests a complete mocked OAuth callback, secret
wrapped token, authenticated tool call, single-request HTTP503 handling, bounded
timeout, exact T3 helper arguments, session handling and the native loopback helper.
Eleven integration tests pass with warnings treated as errors. OAuth state/principal/
expiry/issuer validation was independently reviewed in Conduit's published source.

Always pass scopes explicitly to authorize_url/run: its default scope selection
prefers the server's advertised scopes over config.scopes. T3 advertises both read
and operate. Our facade explicitly requests orchestration:read by default.
Standalone OAuth calls need a running token store; T3.Application starts a shared,
in-memory store. No access tokens are written to disk. Consumers can supply their
own store in oauth_options. Each MCP connection has explicit close/1 lifecycle.

## Primary sources

- [T3 outside agents](https://github.com/pingdotgg/t3code/blob/main/docs/user/outside-agents.md)
- [Conduit source](https://github.com/nyo16/conduit_mcp)
- [Conduit OAuth](https://hexdocs.pm/conduit_mcp/ConduitMcp.Client.OAuth.html)
- [Anubis authorization](https://anubis-mcp.hexdocs.pm/authorization.html)
- [ExMCP source](https://github.com/trust-arbor/arbor_mcp)
- [SDK source](https://github.com/JohnSmall/mcp-elixir-sdk)
