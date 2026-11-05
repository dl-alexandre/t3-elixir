# Opt-in live integration tests

The normal suite uses local fixtures and never contacts your T3 installation.
Live tests are excluded by default. Run them from a repository checkout; test
files are not shipped inside the Hex library archive. Enable them explicitly:

```sh
mix test test/live --include live --warnings-as-errors
```

Tests with missing environment variables are skipped. The harness only performs
read operations: environment metadata, MCP project/thread discovery, HTTP shell
snapshot and RPC server configuration. It does not launch threads, change settings,
upload attachments, redeem guest shares or control devices.

| Test | Required environment variables |
|---|---|
| Public metadata | `T3_LIVE_HTTP_URL` (origin, e.g. `http://127.0.0.1:3773`) |
| MCP projects/threads | `T3_LIVE_MCP_URL`, `T3_LIVE_MCP_TOKEN` |
| HTTP orchestration | `T3_LIVE_HTTP_URL`, `T3_LIVE_ENVIRONMENT_TOKEN` |
| RPC configuration | `T3_LIVE_RPC_URL` (e.g. `ws://127.0.0.1:3773/ws`), `T3_LIVE_ENVIRONMENT_TOKEN` |

Set `T3_LIVE_PROJECT_ID` to select a project for the MCP thread read; otherwise
the first discovered project is used. An empty project list passes discovery
without making a thread request.

Obtain tokens through the appropriate T3 sign-in flow and inject them privately
through your shell environment or secret manager. Do not put credentials into
source files, shell history or CI logs. MCP OAuth tokens and environment access
tokens have different audiences. A read-only MCP approval does not grant access
to native HTTP/RPC. The supplied environment credential must permit the requested
read operations.

These initial credential probes use ordinary Bearer credentials. DPoP-bound
credentials require per-request proof generation and nonce handling in a caller
adapter; they are not supported by this live harness yet. The transports do support
caller-supplied proofs. Live CI credentials are intentionally not configured.

A passing fixture suite is not a substitute for these tests against each supported
T3 version. Record the T3 version, upstream contract revision, OS and Elixir/OTP
combination when preparing a release. Media, guest and mutation workflows need a
separate disposable environment and explicit test fixtures before enabling them.
