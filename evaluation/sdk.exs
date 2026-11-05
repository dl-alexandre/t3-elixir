Mix.install([{:mcp_elixir_sdk, "== 1.1.0"}, {:req, "~> 0.7"}])
Logger.configure(level: :error)
for mode <- ["json", "sse"] do
  {:ok, pid} = MCP.Client.start_link(transport: {MCP.Transport.StreamableHTTP.Client, url: "http://127.0.0.1:47831/#{mode}", protocol_version: "2025-06-18", headers: [{"authorization","Bearer fixture-token"}]}, client_info: %{"name"=>"evaluation", "version"=>"1.0"})
  IO.inspect(MCP.Client.connect(pid,5000),label: "#{mode} connect")
  IO.inspect(MCP.Client.list_tools(pid,timeout: 5000),label: "#{mode} list")
  IO.inspect(MCP.Client.call_tool(pid,"t3_thread_list",%{},timeout: 5000),label: "#{mode} call")
  for tool <- ["tool_error", "rpc_error", "http_error"] do
    IO.inspect(MCP.Client.call_tool(pid,tool,%{},timeout: 5000),label: "#{mode} #{tool}")
  end
  GenServer.stop(pid)
end
