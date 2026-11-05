# Opt-in live integration tests

The normal suite uses local fixtures and never contacts your T3 installation.
Live tests are excluded by default. Run them from a repository checkout; test
files are not shipped inside the Hex library archive. Enable them explicitly:

```sh
mix test test/live --include live --warnings-as-errors
```

Tests with missing environment variables are skipped. The default harness performs
read operations: environment metadata, MCP project/thread discovery, HTTP shell
snapshot and RPC server configuration. It does not launch threads, change settings,
redeem guest shares or control devices. Disposable attachment tests require a
separate explicit opt-in, described below.

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

## Disposable attachment checks

Set `T3_LIVE_DISPOSABLE_UPLOADS=1` along with the HTTP/RPC URLs and an environment
credential permitting `orchestration:read`, `orchestration:operate` and
`filesystem:read`, then run:

```sh
mix test test/live/attachments_test.exs --include live --warnings-as-errors
```

These two tests upload a tiny text file and PNG, download each through an asset
capability, compare exact bytes, and delete the pending attachment in an `after`
block. They never attach files to a user thread or start an agent. Revoke any
temporary environment credential after the run.

On 2026-11-05 both tests passed against T3 Code 0.1.1. Media ticket issuance also
returned HTTP 200. Device discovery initially returned HTTP 503 because the hub
was not running. After the T3 device-tool refresh started hub 0.19.1, SDK discovery
returned HTTP 200; no devices were available for a device media stream. `settings.guestSharingEnabled` was false, so guest redemption/SSE
remains unverified. Full guest tests need guest sharing enabled, a running T3
Connect tunnel and a disposable shareable thread. Browser media tests need a
disposable browser tab and file-picker/download fixtures.

## Recorded browser media validation

A disposable server browser tab was exercised on 2026-11-05 using a short-lived
environment credential with `preview:operate` in addition to the native test
scopes. A media ticket authenticated `T3.WebSocket.Routes.preview/4`. JPEG frames
were checked for the JPEG signature and acknowledged with `preview_ack/2`.

The fixture contained a file input and a Blob-backed download link. The SDK viewer
sent `takeControl` on its interactive stream, received the `fileChooser` ID, and
answered it through `T3.HTTP.Media.preview_upload/3` with multipart text bytes.
HTTP 204 and the page's file contents confirmed the upload. The viewer then clicked
the fixture link, received the `download` ID and fetched it using
`T3.HTTP.Media.preview_download/2`; bytes matched exactly. File-chooser/download
notifications go to the controlling viewer, so a view-only stream cannot supply
these capability IDs. The tab and downloads were removed and the credential
revoked. This was a manual live fixture, not an automatically enabled CI test.
