# Troubleshooting and errors

SDK operations normally return `{:ok, result}` or `{:error, %T3.Error{}}`.
Invalid constructor options can raise `ArgumentError`; those are programmer
configuration errors. Result types vary by interface:

- MCP: string-keyed result envelope; use `T3.Result.data/1` for a JSON object.
- HTTP: `T3.HTTP.Response` with status, headers and decoded/raw body.
- RPC: the original wire value or a subscription ID.
- HTTP streams: `T3.HTTP.Stream.Summary` after EOF or callback halt.
- CLI: `T3.CLI.Result`, whose output combines stdout and stderr.

## Handle a failure without dumping secrets

```elixir
case T3.Threads.list(client, %{"projectId" => project_id, "limit" => 10}) do
  {:ok, result} -> T3.Result.data(result)
  {:error, %T3.Error{kind: kind, message: message}} ->
    IO.puts(:stderr, "#{kind}: #{message}")
    {:error, kind}
end
```

`kind` identifies the failure class. `code` is interface-specific: it can be an
HTTP status, a CLI exit status, an RPC reason or nil. `details` retains underlying
errors/result content and may include secrets; inspect it only in a controlled
context. Do not assume every error has the same JSON shape.

## `Pass projectId` / `target_required`

External MCP clients have no implicit IDE project. Discover projects using
`T3.Projects.list/2`, extract `projects` with `T3.Result.data/1`, and pass the
selected `projectId` to `T3.Threads.list/2`. Other operations may require an
explicit `threadId`. `T3.discover/1` exposes the server's input schemas.

## 401, 403 or unavailable tools

401 can mean an expired/revoked credential, wrong environment or wrong credential
audience. 403 normally means a missing scope or permission. Check the server
response rather than retrying blindly. Read [AUTHENTICATION.md](AUTHENTICATION.md)
for MCP versus native credentials, DPoP, guest cookies and media tickets.

A successful MCP sign-in does not authorize native HTTP/RPC. A full-access MCP
approval also does not guarantee in-app agent-only tools are advertised. Compare
the connected server with `T3.Catalog.compare/1`. A static helper can exist even
when the current server does not expose it.

## Stream stops, stalls or closes

RPC chunks require `T3.RPC.ack/2` after consumption. Raw WebSocket deliveries
require `T3.WebSocket.ack/2` to release local backlog; preview binary frames use
`T3.WebSocket.Routes.preview_ack/2`, which also sends the server's JSON ACK.
Acknowledge text status frames locally too. Handle terminal/error messages and
use bounded receive timeouts; a closed connection will not produce another chunk.

HTTP callbacks return `:cont` or `:halt`. Their `self()` is an isolated worker;
capture your application's PID before forwarding events. Byte/event and hard
wall-clock limits apply even to a blocked callback. Increase bounds deliberately
for a long media stream. SSE comments/heartbeats do not produce data events;
reconnect and Last-Event-ID handling are caller-owned.

There is no automatic replay after disconnect. Reconnect explicitly after closing
the old connection. After a mutation timeout, inspect T3 state before retrying;
work may already have started.

## CLI/native build issues

Exile requires a C compiler and make on Linux/macOS. Command support follows the
installed `t3` executable; inspect it with `T3.CLI.commands/2` or `help/2`. The CLI
adapter uses pipes, not a terminal/PTY. Stdin-reading commands need finite
`input:` or streaming `write/2` followed by `close_stdin/1`.

If a native library fails to load after switching OTP versions, rebuild it for the
selected runtime. Keep dependency directories as well as build directories
separate when testing several OTP versions: Exile's native files live in
`deps/exile/priv`. CI caches are already separated by runtime, OS and architecture.

## Reporting a problem

Open an issue at https://github.com/dl-alexandre/t3-elixir/issues with the SDK
version, T3 version/upstream revision, interface, OS, Elixir/OTP pair, sanitized
error kind/code and a minimal reproduction. Omit tokens, cookies, signed URLs,
callback queries and private project contents.
