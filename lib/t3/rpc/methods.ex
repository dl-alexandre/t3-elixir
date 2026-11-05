defmodule T3.RPC.Methods do
  @moduledoc """
  Named helpers for every method in the pinned T3 WebSocket contract.
  All take `(rpc, payload \\ %{}, options \\ [])`. Stream methods return a
  subscription ID, unary methods return their result. See `T3.RPC` for explicit
  acknowledgements and lifecycle. Argument maps keep T3's original string keys.
  """
  for method <- T3.RPC.Catalog.methods() do
    prefix =
      if String.starts_with?(method["name"], "orchestration."), do: "orchestration_", else: ""

    name = String.to_atom(prefix <> Macro.underscore(method["key"]))
    transport = if method["stream"], do: :subscribe, else: :call
    @doc "Invoke `#{method["name"]}` (#{if method["stream"], do: "stream", else: "unary"})."
    def unquote(name)(rpc, payload \\ %{}, opts \\ []) do
      T3.RPC.unquote(transport)(rpc, unquote(method["name"]), payload, opts)
    end
  end
end
