# Contributing

This is an independent T3 Code SDK. Use Elixir 1.20.5 / OTP 29.1.2 as pinned in
`.mise.toml`, on Linux or macOS. Install a C compiler and make for Exile.

```sh
git clone https://github.com/dl-alexandre/t3-elixir.git
cd t3-elixir
mise install
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix docs --warnings-as-errors
mix hex.build
```

The default tests use local HTTP/WebSocket/subprocess fixtures and exclude live
tests. Follow [LIVE_TESTING.md](LIVE_TESTING.md) to opt into read-only live probes.
Never add production credentials to tests or CI. Avoid tests that mutate a normal
T3 environment; use a disposable environment for explicitly authorized workflows.

Keep wire arguments/results faithful to the upstream contract and return the
interface's existing error/result conventions. Add a regression test for protocol,
authentication or lifecycle fixes. If you add an operation, update its catalog,
input routing tests, interface inventory and changelog together. Input schemas
remain server-owned; helpers do not bypass scopes or invocation context.

Pinned upstream source lives in `priv/t3`, with its provenance and MIT notice.
Record a new source revision explicitly rather than silently replacing snapshots.
A passing local suite does not establish live compatibility with every T3 version.

Open a pull request describing the concrete behavior change and relevant test
results. CI checks Linux and macOS on OTP 29. Publishing to Hex is manual and
requires a separate maintainer decision; see [RELEASE.md](RELEASE.md).
