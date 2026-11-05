# Changelog

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
