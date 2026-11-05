defmodule T3.Client do
  @moduledoc """
  A connection to one T3 `/mcp` endpoint, backed by ConduitMCP.

  `connect/1` starts a linked supervised connection; `close/1` stops it.
  Keep the returned client for subsequent calls. Token values may be strings
  or `ConduitMcp.Client.Secret` values. No credentials are persisted by T3.Client.
  """
  alias ConduitMcp.Client, as: MCP
  alias T3.Error
  @derive {Inspect, only: [:url, :protocol_version, :connected?]}
  defstruct [
    :url,
    :token,
    :name,
    :supervisor,
    protocol_version: "2025-06-18",
    timeout: 30_000,
    connected?: false
  ]

  @type t :: %__MODULE__{}

  @spec new(keyword()) :: t()
  def new(opts) do
    url = Keyword.fetch!(opts, :url)
    uri = URI.parse(url)

    unless uri.scheme == "https" or
             (uri.scheme == "http" and uri.host in ["localhost", "127.0.0.1", "::1"]) do
      raise ArgumentError, "use HTTPS or loopback HTTP for the MCP endpoint"
    end

    unless is_binary(uri.host) and uri.userinfo == nil and uri.query == nil and
             uri.fragment == nil do
      raise ArgumentError, "MCP URL must have a host and no credentials, query, or fragment"
    end

    client = struct!(__MODULE__, Keyword.put(opts, :url, String.trim_trailing(url, "/")))

    unless is_integer(client.timeout) and client.timeout > 0,
      do: raise(ArgumentError, "timeout must be a positive integer")

    client
  end

  @spec connect(t()) :: {:ok, t()} | {:error, Error.t()}
  def connect(%{connected?: true} = client) do
    if is_pid(client.supervisor) and Process.alive?(client.supervisor) do
      {:ok, client}
    else
      connect(%{client | connected?: false, name: nil, supervisor: nil})
    end
  end

  def connect(client) do
    name = {__MODULE__, make_ref()}
    transport = [url: client.url]

    transport =
      if client.token, do: Keyword.put(transport, :auth, {:bearer, client.token}), else: transport

    case MCP.start_link(
           name: name,
           transport: {ConduitMcp.Client.Transport.StreamableHTTP, transport},
           protocol: client.protocol_version,
           request_timeout: client.timeout,
           max_reconnects: 0,
           client_info: %{"name" => "t3", "version" => "0.1.0"}
         ) do
      {:ok, supervisor} ->
        case MCP.await_ready(name, client.timeout) do
          :ok ->
            {:ok, %{client | name: name, supervisor: supervisor, connected?: true}}

          {:error, reason} ->
            close(%{supervisor: supervisor})
            failure(reason)
        end

      {:error, reason} ->
        failure(reason)
    end
  end

  @doc "Stop this connection and terminate its MCP session. Safe to call repeatedly."
  def close(%{supervisor: pid}) when is_pid(pid) do
    if Process.alive?(pid), do: Supervisor.stop(pid)
    :ok
  catch
    :exit, reason ->
      # A linked owner's shutdown can race an explicit close/on_exit callback.
      if Process.alive?(pid), do: exit(reason), else: :ok
  end

  def close(_), do: :ok

  @doc "List a page of tools; pass nextCursor back as the string-keyed cursor argument."
  def list_tools(client, params \\ %{})

  def list_tools(%{connected?: true} = client, params) do
    opts = [timeout: client.timeout]
    opts = if params["cursor"], do: Keyword.put(opts, :cursor, params["cursor"]), else: opts

    case MCP.list_tools(client.name, opts) do
      {:ok, page} ->
        {:ok, %{"tools" => Enum.map(page.tools, & &1.raw), "nextCursor" => page.next_cursor}}

      {:error, reason} ->
        failure(reason)
    end
  end

  def list_tools(_, _), do: disconnected()

  @doc "Call an advertised tool and return its MCP result envelope."
  def call_tool(client, name, arguments \\ %{})

  def call_tool(%{connected?: true} = client, name, arguments)
      when is_binary(name) and is_map(arguments) do
    case MCP.call_tool(client.name, name, arguments, timeout: client.timeout) do
      {:ok, result} ->
        wire =
          Map.merge(result.extra, %{"content" => result.content, "isError" => result.is_error})

        wire =
          if is_nil(result.structured),
            do: wire,
            else: Map.put(wire, "structuredContent", result.structured)

        wire = if result.meta == %{}, do: wire, else: Map.put(wire, "_meta", result.meta)

        if result.is_error do
          {:error, %Error{kind: :tool, message: "T3 tool #{name} failed", details: wire}}
        else
          {:ok, wire}
        end

      {:error, reason} ->
        failure(reason)
    end
  end

  def call_tool(_, _, _), do: disconnected()

  @doc false
  def failure(%ConduitMcp.Client.Error{} = error),
    do:
      {:error,
       %Error{
         kind: error.kind,
         code: error.reason,
         message: Exception.message(error),
         details: error
       }}

  def failure(reason),
    do: {:error, %Error{kind: :transport, message: "T3 connection failed", details: reason}}

  defp disconnected,
    do: {:error, %Error{kind: :protocol, message: "call T3.Client.connect/1 first"}}
end
