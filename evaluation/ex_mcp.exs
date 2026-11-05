Mix.install([{:ex_mcp, "== 1.8.1"}])
Logger.configure(level: :error)
for mode <- ["json", "sse"] do
  {:ok, pid} = ExMCP.Client.start_link(transport: :http, url: "http://127.0.0.1:47831/#{mode}", protocol_mode: :legacy_only, protocol_version: "2025-06-18", use_sse: false, headers: [{"authorization","Bearer fixture-token"}], retry_policy: [max_attempts: 1])
  IO.inspect(ExMCP.Client.list_tools(pid,timeout: 5000),label: "#{mode} list")
  IO.inspect(ExMCP.Client.call_tool(pid,"t3_thread_list",%{},timeout: 5000, retry_policy: [max_attempts: 1]),label: "#{mode} call")
  for tool <- ["tool_error", "rpc_error", "http_error"] do
    IO.inspect(ExMCP.Client.call_tool(pid,tool,%{},timeout: 5000, retry_policy: [max_attempts: 1]),label: "#{mode} #{tool}")
  end
  GenServer.stop(pid)
end
