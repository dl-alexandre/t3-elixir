# Independent client smoke experiments

These scripts install pinned versions into Mix's external installation cache.
They do not add the alternatives to t3's dependencies.

In one terminal, run `python3 evaluation/fixture.py`. It listens only on
127.0.0.1:47831 and uses the synthetic token `fixture-token`.
In another, run `elixir evaluation/anubis.exs` (or ex_mcp.exs, sdk.exs, conduit.exs).
Stop the fixture with Ctrl-C afterward.

Raw logs preserve the comparison run. The SDK experiment intentionally stops at
its HTTP503 caller timeout; its initial happy-path run also passed JSON and SSE.
These tests evaluate protocol behavior and integration fit, not throughput.
