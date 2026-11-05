defmodule T3.Live.MetadataTest do
  use ExUnit.Case, async: false
  @moduletag :live
  @moduletag skip: is_nil(System.get_env("T3_LIVE_HTTP_URL"))

  test "the live environment descriptor is reachable" do
    http = T3.HTTP.new(base_url: System.fetch_env!("T3_LIVE_HTTP_URL"))
    assert {:ok, %T3.HTTP.Response{status: 200, body: body}} = T3.HTTP.Metadata.descriptor(http)
    assert is_map(body)
  end
end

defmodule T3.Live.MCPTest do
  use ExUnit.Case, async: false
  @moduletag :live
  @moduletag skip: Enum.any?(~w(T3_LIVE_MCP_URL T3_LIVE_MCP_TOKEN), &is_nil(System.get_env(&1)))

  test "an external OAuth client discovers projects and reads their threads" do
    client =
      T3.new(
        url: System.fetch_env!("T3_LIVE_MCP_URL"),
        token: System.fetch_env!("T3_LIVE_MCP_TOKEN")
      )

    assert {:ok, client} = T3.connect(client)

    try do
      assert {:ok, tools} = T3.discover(client)
      assert Enum.any?(tools, &(&1["name"] == "t3_project_list"))
      assert {:ok, result} = T3.Projects.list(client)
      assert {:ok, %{"projects" => projects}} = T3.Result.data(result)

      case System.get_env("T3_LIVE_PROJECT_ID") || get_in(List.first(projects) || %{}, ["id"]) do
        nil ->
          assert projects == []

        id ->
          assert {:ok, result} = T3.Threads.list(client, %{"projectId" => id, "limit" => 1})
          assert {:ok, %{"threads" => threads}} = T3.Result.data(result)
          assert is_list(threads)
      end
    after
      T3.close(client)
    end
  end
end

defmodule T3.Live.HTTPTest do
  use ExUnit.Case, async: false
  @moduletag :live
  @moduletag skip:
               Enum.any?(
                 ~w(T3_LIVE_HTTP_URL T3_LIVE_ENVIRONMENT_TOKEN),
                 &is_nil(System.get_env(&1))
               )

  test "an environment credential can read the orchestration shell" do
    http =
      T3.HTTP.new(
        base_url: System.fetch_env!("T3_LIVE_HTTP_URL"),
        token: System.fetch_env!("T3_LIVE_ENVIRONMENT_TOKEN")
      )

    assert {:ok, %T3.HTTP.Response{status: 200, body: body}} =
             T3.HTTP.Orchestration.shell_snapshot(http)

    assert is_map(body)
  end
end

defmodule T3.Live.RPCTest do
  use ExUnit.Case, async: false
  @moduletag :live
  @moduletag skip:
               Enum.any?(
                 ~w(T3_LIVE_RPC_URL T3_LIVE_ENVIRONMENT_TOKEN),
                 &is_nil(System.get_env(&1))
               )

  test "an environment credential can read server configuration through RPC" do
    assert {:ok, rpc} =
             T3.RPC.start_link(
               url: System.fetch_env!("T3_LIVE_RPC_URL"),
               token: System.fetch_env!("T3_LIVE_ENVIRONMENT_TOKEN")
             )

    try do
      assert {:ok, config} = T3.RPC.Methods.server_get_config(rpc)
      assert is_map(config)
    after
      T3.RPC.close(rpc)
    end
  end
end
