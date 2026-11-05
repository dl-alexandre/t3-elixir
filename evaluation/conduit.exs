Mix.install([{:conduit_mcp, "== 0.11.0"}, {:finch, "~> 0.24"}])
Logger.configure(level: :error)
for mode <- ["json", "sse"] do
  name = "eval_#{mode}"
  {:ok, pid} = ConduitMcp.Client.start_link(name: name, transport: {ConduitMcp.Client.Transport.StreamableHTTP, url: "http://127.0.0.1:47831/#{mode}", auth: {:bearer,"fixture-token"}}, protocol: "2025-06-18", max_reconnects: 0)
  IO.inspect(ConduitMcp.Client.await_ready(name,5000),label: "#{mode} ready")
  IO.inspect(ConduitMcp.Client.list_tools(name,timeout: 5000),label: "#{mode} list")
  IO.inspect(ConduitMcp.Client.call_tool(name,"t3_thread_list",%{},timeout: 5000),label: "#{mode} call")
  for tool <- ["tool_error", "rpc_error", "http_error"] do
    IO.inspect(ConduitMcp.Client.call_tool(name,tool,%{},timeout: 5000),label: "#{mode} #{tool}")
  end
  Supervisor.stop(pid)
end
