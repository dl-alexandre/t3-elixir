# Release readiness

The SDK builds a local `t3-0.1.0.tar` archive. It is not published to Hex.
The CI workflow builds and tests only: it contains no publishing step, account
credentials, T3 tokens or live-environment configuration.

## CI coverage

The project targets OTP 29. `.mise.toml` pins OTP 29.1.2 and Elixir 1.20.5
(compiled for OTP 29). The GitHub Actions workflow checks this same pair on:

- Ubuntu 24.04.
- macOS 15, including Exile's native build.

Every pairing compiles and tests with warnings treated as errors. The primary
Linux job also checks formatting, prints the offline interface inventory, builds
ExDoc with warnings treated as errors and builds the local Hex archive. Formatting
uses one Elixir release because formatter output can vary between versions.
Dependency/build caches are separated by operating system, architecture and both
runtime versions. Jobs use GitHub-hosted runners, which include the C compiler and
`make` required by Exile. Linux and macOS are the supported native CLI platforms.

The action references are pinned to reviewed upstream commits. Version sources:
[setup-beam compatibility and inputs](https://github.com/erlef/setup-beam),
[Elixir 1.20.5 release assets](https://github.com/elixir-lang/elixir/releases/tag/v1.20.5),
[checkout](https://github.com/actions/checkout), and
[cache](https://github.com/actions/cache), and
[OTP 29.1.2](https://github.com/erlang/otp/releases/tag/OTP-29.1.2).

The repository is public at `dl-alexandre/t3-elixir`. Both platform jobs passed
for commit `6c78657a9317f0a13afa2b8401ee77b4c548b153` in
[the recorded CI run](https://github.com/dl-alexandre/t3-elixir/actions/runs/42066189074).

## Recorded local validation

On 2026-11-05, all 67 local tests passed on this Mac with Elixir 1.20.5 /
OTP 29.1.2 in a fresh build directory; four live tests were excluded from that
local suite. The remote matrix result is recorded separately above.
OTP 27/28 are outside this project's current support target.

The same versions are the local global Mise defaults. Existing shells with
inherited version-specific PATH entries need a Mise environment refresh.

All four opt-in live smoke checks passed against T3 Code 0.1.1 on 2026-11-05:
public environment metadata, authenticated HTTP shell snapshot, authenticated
WebSocket RPC server configuration, and external OAuth MCP discovery/project
and thread reads. The native checks ran together (three passed, MCP skipped);
the OAuth MCP check ran separately after read-only approval (one passed, three
skipped). The temporary native credential was revoked after validation.

These checks validate read-only integration. Live upload/download, guest-share
SSE, mutation and media workflows remain unverified. See
[LIVE_TESTING.md](LIVE_TESTING.md) for exact variables and limits.

## Before the first publication

1. The chosen Hex package and OTP application name are `t3`, version `0.1.0`.
   Recheck name availability before first publication; a lookup does not reserve it.
2. The SDK repository is `https://github.com/dl-alexandre/t3-elixir`. Source and
   homepage links and GitHub maintainer identity are configured in `mix.exs`.
   Confirm the intended Hex owner and repository visibility before publication.
3. Review `LICENSE`, the included upstream MIT notices, dependency licenses,
   `README.md`, `INTERFACES.md`, and the changelog for the final package identity.
4. Push the repository and confirm all CI matrix jobs pass. Check the declared
   minimum locally or in CI; do not raise or lower it based only on a successful
   run with the developer's newer Elixir version.
5. Run opt-in live checks with explicitly supplied, appropriately scoped test
   credentials. Verify authenticated HTTP/RPC, upload/download, guest-share SSE
   and media flows relevant to the release. Local fixtures prove transport
   behavior, not every operation's live business semantics. Do not enable live
   checks in fork pull-request CI or log tokens, cookies, callbacks or proof data.
6. Decide the tested T3 version/revision policy and document any compatibility
   exceptions. Reconcile the pinned catalogs with the actual release target.
7. Run the local release checks below and inspect the archive contents. Unpack
   it into a clean directory and compile in production to catch missing runtime
   catalogs and private files.
8. Confirm the account/organization that will own the Hex package. Authenticate
   interactively on the publishing machine when ready. Publishing is a separate,
   explicit user action; neither CI nor this checklist authorizes publication.
9. Only after that explicit decision, publish the intended version and docs,
   verify the public package, and create the matching repository release/tag.

## Local checks

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix t3.interfaces
mix docs --warnings-as-errors
mix hex.build
```

`mix hex.build` creates a local archive and never publishes it. The release
workflow leaves credential entry and final publication outside automation. The
repository and package identity are configured. Verify CI and live integration
results before the separate decision to publish.
