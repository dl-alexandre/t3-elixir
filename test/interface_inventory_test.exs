defmodule T3.InterfaceInventoryTest do
  use ExUnit.Case, async: true

  test "RPC catalog accounts for every declared source method and exports its helper" do
    source = File.read!(Application.app_dir(:t3, "priv/t3/rpc.ts"))
    methods = T3.RPC.Catalog.methods()

    definitions =
      Regex.scan(~r/(?:export\s+)?const\s+(\w+)\s*=\s*Rpc\.make\(/, source)
      |> Enum.map(fn [_, name] -> name end)
      |> Enum.sort()

    assert length(methods) == 261
    assert Enum.sort(Enum.map(methods, & &1["definition"])) == definitions
    assert length(Enum.uniq(Enum.map(methods, & &1["name"]))) == length(definitions)
    Code.ensure_loaded!(T3.RPC.Methods)

    for method <- methods do
      definition = Regex.escape(method["definition"])

      [_, body] =
        Regex.run(
          Regex.compile!(
            "(?:export\\s+)?const\\s+#{definition}\\s*=\\s*Rpc\\.make\\((.*?\\n\\s*\\}\\s*\\);)",
            "s"
          ),
          source
        )

      assert String.contains?(body, "stream: true") == method["stream"]

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
    assert T3.WebSocket.Routes.source_ref() == metadata["ref"]
    cli = Application.app_dir(:t3, "priv/t3/cli.json") |> File.read!() |> JSON.decode!()
    assert cli["version"] == "t3 v0.1.12"
    assert length(cli["commands"]) == 23
    interfaces = T3.interfaces()
    assert interfaces.mcp == T3.Catalog.tools()
    assert interfaces.http == T3.HTTP.endpoints()
    assert interfaces.rpc == T3.RPC.Catalog.methods()
    assert interfaces.http_raw == T3.HTTP.raw_endpoints()
    assert interfaces.web_socket == T3.WebSocket.Routes.all()
    assert "thread" in interfaces.cli
    assert length(interfaces.cli) == 23
  end
end
