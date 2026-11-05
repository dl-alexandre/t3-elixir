defmodule T3.InterfaceInventoryTest do
  use ExUnit.Case, async: true

  test "RPC catalog accounts for every declared source method and exports its helper" do
    source = File.read!(Application.app_dir(:t3, "priv/t3/rpc.ts"))

    declared =
      Regex.scan(~r/Rpc\.make\(\s*(WS_METHODS|ORCHESTRATION_V2_WS_METHODS)\.(\w+)/, source)
      |> Enum.map(fn [_, _group, key] -> key end)
      |> Enum.sort()

    methods = T3.RPC.Catalog.methods()
    assert Enum.sort(Enum.map(methods, & &1["key"])) == declared
    assert length(Enum.uniq(Enum.map(methods, & &1["name"]))) == length(declared)
    Code.ensure_loaded!(T3.RPC.Methods)

    for method <- methods do
      prefix =
        if String.starts_with?(method["name"], "orchestration."), do: "orchestration_", else: ""

      helper = String.to_existing_atom(prefix <> Macro.underscore(method["key"]))
      assert function_exported?(T3.RPC.Methods, helper, 3)
    end
  end

  test "all inventories share the pinned revision and top-level inventory stays offline" do
    metadata =
      Application.app_dir(:t3, "priv/t3/upstream.json") |> File.read!() |> JSON.decode!()

    assert T3.Catalog.upstream_ref() == metadata["ref"]
    assert T3.RPC.Catalog.upstream_ref() == metadata["ref"]
    interfaces = T3.interfaces()
    assert interfaces.mcp == T3.Catalog.tools()
    assert interfaces.http == T3.HTTP.endpoints()
    assert interfaces.rpc == T3.RPC.Catalog.methods()
    assert interfaces.http_raw == T3.HTTP.raw_endpoints()
    assert interfaces.web_socket == T3.WebSocket.Routes.all()
    assert "thread" in interfaces.cli
  end
end
