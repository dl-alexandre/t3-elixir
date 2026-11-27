# Changelog

## 0.4.1 — 2026-11-27

- Stabilize the test suite on hosted CI runners by raising the default
  `assert_receive` timeout to 5 seconds; this fixes intermittent macOS failures
  seen on the 0.4.0 tag build. No library behaviour changes.

## 0.4.0 — 2026-11-26

- Sync the upstream contract to `d8a52dda31d8e2fe65b183cc97d1e4457d9c2396`:
  93 MCP tools, 59 HTTP routes, 261 RPC methods (35 streams), 46 raw HTTP routes,
  and the `t3 v0.1.12` CLI inventory. Add issue, feedback, theme and workflow
  MCP modules plus HTTP voice and peer-link helpers.
- Add dynamic MCP client version metadata and resilient named `:owner` handling
  in `T3.RPC.WorkQueue`.
- Fall back to `T3CODE_CLI_PATH` when selecting the `T3.CLI` executable.
- Make `T3.Application` supervision children configurable, including Finch and
  OAuth store options.
- Add `:telemetry` instrumentation and expand `@spec` coverage.
- Update CI compatibility for Elixir `~> 1.18` and Finch 0.25, retaining Finch
  0.24 support.
- Set the HexDocs `source_ref` and add a Changelog link.

## 0.3.0 — 2026-11-05

- Add opt-in stream resume checkpoints using supported `afterSequence` inputs,
  with load/save hooks and cursor helpers that ignore enrichment high-waters.
- Add bounded asynchronous work admission with deferred ACK/backpressure.
- Add opt-in reusable bearer RPC ticket caching bounded by server/session expiry.
- Clarify remote environment credentials, sequence ordering and full inventory.
- Correct ticket documentation: bearer tickets are reusable; DPoP proofs are not.

## 0.2.0 — 2026-11-05

- Add supervised RPC readers with reconnect, re-subscription, catch-up reads,
  bounded backoff, optional health checks and consumption-before-ACK callbacks.
- Add local service authentication with scoped CLI-issued session caching,
  lazy renewal, revocation and fresh RPC tickets without browser sign-in.
- Add host-aware board rows and reducers for live shell/thread stream payloads.
- Document confirmed live stream shapes and complete board supervision/ACK examples.

## 0.1.0 — 2026-11-05

- Add publication guides for authentication, troubleshooting and contributing.
- Validate documentation examples and links; fix fast CLI exit handling found by CI.

- Name the Hex package and OTP application `t3`; use the `t3-elixir` repository.

- Target OTP 29 and Elixir 1.20; pin the project to OTP 29.1.2 / Elixir 1.20.5.

- Verify Elixir 1.20.5 / OTP 29.1.2 and update current-runtime CI targets.

- Configure Linux/macOS CI on Elixir 1.20 / OTP 29; add release-readiness checks.
- Add opt-in read-only live tests, excluded from normal test runs.

- Cover all 71 known MCP tools with canonical and category helpers.
- Add authenticated discovery, catalog comparison, context notes and pagination bounds.
- Implement all 38 declared HTTP routes with named modules, binary uploads and generic access.
- Add real Effect WebSocket RPC, all 211 method helpers and 27 stream methods.
- Support explicit stream acknowledgements, deadlines, cancellation and disconnect cleanup.
- Add 45 raw HTTP operations, guest SSE, multipart uploads and binary media streaming.
- Add 4 raw WebSocket media/device routes with explicit ACK/backlog bounds.
- Add shell-free CLI execution, command discovery, streaming stdin/output and process termination.
- Use ConduitMCP, Finch, Mint.WebSocket and Exile rather than reimplement their protocols.
- Pin upstream contract revision and publish a full offline interface inventory.
- Generate ExDoc documentation and a local Hex archive; require Elixir 1.20.
