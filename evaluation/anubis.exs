Mix.install([{:anubis_mcp, "== 2.2.0"}])
Logger.configure(level: :error)
{:ok, _} = Finch.start_link(name: Anubis.Finch)
for mode <- ["json", "sse"] do
  {:ok, pid} = Anubis.Client.start_link(name: String.to_atom("eval_#{mode}"), transport: {:streamable_http, base_url: "http://127.0.0.1:47831", mcp_path: "/#{mode}", headers: %{"authorization" => "Bearer fixture-token"}}, protocol_version: "2025-06-18", client_info: %{"name"=>"evaluation", "version"=>"1.0"})
  name = String.to_atom("eval_#{mode}")
  Enum.reduce_while(1..100, nil, fn _, _ ->
    case Anubis.Client.get_server_info(name) do
      {:ok, info} when not is_nil(info) -> {:halt, :ready}
      _ -> Process.sleep(20); {:cont, nil}
    end
  end)
  IO.inspect(Anubis.Client.list_tools(String.to_atom("eval_#{mode}"), timeout: 5000),label: "#{mode} list")
  IO.inspect(Anubis.Client.call_tool(String.to_atom("eval_#{mode}"),"t3_thread_list",%{},timeout: 5000),label: "#{mode} call")
  for tool <- ["tool_error", "rpc_error", "http_error"] do
    IO.inspect(Anubis.Client.call_tool(name,tool,%{},timeout: 5000),label: "#{mode} #{tool}")
  end
  GenServer.stop(pid)
end
