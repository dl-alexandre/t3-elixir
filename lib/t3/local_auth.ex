defmodule T3.LocalAuth do
  @moduledoc """
  Cached, renewable native credentials for a service on the T3 host.

  Add this process before the reader in your supervision tree. It invokes the
  installed `t3 auth session issue --json` without a shell or browser, explicitly
  requests read scope, and keeps the bearer token in memory. The OS user must
  already have access to the intended T3 data directory. This is local control
  plane authorization, not an OAuth bypass for remote services.

      children = [
        {T3.LocalAuth, name: MyApp.T3Auth, base_url: "http://127.0.0.1:3773",
         ttl: "24h", label: "board-reader"}
      ]

      connect = fn -> T3.LocalAuth.connection_options(MyApp.T3Auth) end

  `connection_options/1` returns RPC options and reuses the issued session until
  it is within `:renew_before` milliseconds of expiry (default 60 seconds).
  Renewal happens when options are requested, not while an existing socket is
  open. Configure `ticket: true` to mint a fresh RPC bearer ticket each time
  options are requested; the underlying environment session remains cached.
  Set `ticket_cache_ttl: milliseconds` to opt into ticket reuse. Its lifetime is
  bounded by this TTL, the server ticket expiry and the underlying session expiry.
  The default zero disables ticket caching. CLI-issued credentials are bearer
  credentials; DPoP-bound credentials require a new proof for every handshake.
  Reconnect readers should call the function for every connection attempt.

  Defaults are `ttl: "24h"`, `scopes: ["orchestration:read"]` and
  `label: "t3-elixir-local-service"`. `:base_dir` selects the same T3 data
  directory used by the localhost server; `:cli` configures the executable and
  command deadline. Only loopback HTTP(S) origins are accepted. Renewal revokes
  the previous owned session; orderly shutdown attempts to revoke the current
  session. Abrupt OS/process termination cannot guarantee revocation: TTL still
  bounds the credential lifetime. No token is persisted.

  Returned connection options contain a credential: do not log them. Process
  status and credential inspection are redacted. The caller owns any separately
  issued credential returned by `issue/1` and must revoke it with `revoke/2`.
  """
  use GenServer
  alias ConduitMcp.Client.Secret
  alias T3.{CLI, Error}

  defmodule Credential do
    @moduledoc "An owned native session. Token inspection is redacted; expiry is a DateTime."
    @derive {Inspect, only: [:session_id, :expires_at]}
    @enforce_keys [:session_id, :token, :expires_at]
    defstruct [:session_id, :token, :expires_at]
    @type t :: %__MODULE__{session_id: String.t(), token: Secret.t(), expires_at: DateTime.t()}
  end

  @doc "Start a supervised credential provider. Requires a localhost :base_url."
  def start_link(opts) do
    {gen_opts, opts} = Keyword.split(opts, [:name])

    with {:ok, state} <- provider_state(opts) do
      GenServer.start_link(__MODULE__, state, gen_opts)
    end
  end

  @doc "Get fresh RPC connection options, reusing or renewing the owned session."
  def connection_options(server), do: GenServer.call(server, :connection_options, :infinity)

  @doc "Discard and revoke a cached session, for example after explicit server revocation."
  def invalidate(server), do: GenServer.call(server, :invalidate, :infinity)

  @doc "Issue one scoped native session through the local CLI; caller owns revocation."
  def issue(opts \\ []) do
    with :ok <- validate_issue_options(opts),
         {:ok, result} <- CLI.run(cli(opts), issue_arguments(opts)),
         {:ok, decoded} <- JSON.decode(result.output),
         {:ok, credential} <- credential(decoded) do
      {:ok, credential}
    else
      _ -> error(:issue_failed, "Cannot issue local T3 service credential")
    end
  end

  @doc "Revoke a credential issued by the same local T3 data directory."
  def revoke(%Credential{session_id: id}, opts \\ []) do
    case CLI.run(cli(opts), ["auth", "session", "revoke", id] ++ base_arguments(opts)) do
      {:ok, _} -> :ok
      {:error, _} -> error(:revoke_failed, "Cannot revoke local T3 service credential")
    end
  end

  @impl true
  def init(state) do
    Process.flag(:trap_exit, true)
    {:ok, state}
  end

  defp provider_state(opts) do
    with {:ok, origin, rpc_url} <- local_urls(Keyword.get(opts, :base_url)),
         :ok <- validate_issue_options(opts),
         true <-
           is_integer(Keyword.get(opts, :renew_before, 60_000)) and
             Keyword.get(opts, :renew_before, 60_000) >= 0,
         true <- is_boolean(Keyword.get(opts, :ticket, false)),
         true <-
           is_integer(Keyword.get(opts, :ticket_cache_ttl, 0)) and
             Keyword.get(opts, :ticket_cache_ttl, 0) >= 0,
         true <-
           Keyword.get(opts, :ticket_cache_ttl, 0) == 0 or
             Keyword.get(opts, :ticket, false) do
      {:ok,
       %{opts: opts, origin: origin, rpc_url: rpc_url, credential: nil, ticket: nil, retired: []}}
    else
      {:error, :non_local_origin} ->
        {:error,
         %Error{
           kind: :configuration,
           code: :non_local_origin,
           message:
             "T3.LocalAuth requires a loopback origin; use an authorized environment token for remote services"
         }}

      _ ->
        {:error, %Error{kind: :configuration, message: "Invalid local auth options or origin"}}
    end
  end

  @impl true
  def handle_call(:connection_options, _from, state) do
    state = cleanup_retired(state)

    case ensure_credential(state) do
      {:ok, state} ->
        {result, state} = connect_options(state)
        {:reply, result, state}

      {:error, error} ->
        {:reply, {:error, error}, state}
    end
  end

  def handle_call(:invalidate, _from, state) do
    state = retire(state, state.credential)
    {:reply, :ok, cleanup_retired(%{state | credential: nil, ticket: nil})}
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    state = retire(state, state.credential)
    cleanup_retired(state)
    :ok
  end

  @impl true
  def format_status(status),
    do: %{status | state: :redacted, message: :redacted, reason: :redacted}

  defp ensure_credential(state) do
    renew_before = Keyword.get(state.opts, :renew_before, 60_000)

    if state.credential &&
         DateTime.diff(state.credential.expires_at, DateTime.utc_now(), :millisecond) >
           renew_before do
      {:ok, state}
    else
      case issue(state.opts) do
        {:ok, credential} ->
          {:ok,
           state
           |> retire(state.credential)
           |> Map.put(:credential, credential)
           |> Map.put(:ticket, nil)
           |> cleanup_retired()}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp connect_options(state) do
    if Keyword.get(state.opts, :ticket, false) do
      ticket_options(state)
    else
      token = Secret.expose(state.credential.token)
      {{:ok, [url: state.rpc_url, token: token]}, state}
    end
  end

  defp ticket_options(state) do
    now = System.system_time(:millisecond)

    if not is_nil(state.ticket) and state.ticket.until > now and
         state.ticket.deadline > System.monotonic_time(:millisecond) do
      {{:ok, [url: state.rpc_url, ticket: Secret.expose(state.ticket.value)]}, state}
    else
      token = Secret.expose(state.credential.token)
      http = T3.HTTP.new(base_url: state.origin, token: token)

      case T3.HTTP.Auth.web_socket_ticket_for(http, "rpc") do
        {:ok, %{body: %{"ticket" => ticket} = body}} when is_binary(ticket) and ticket != "" ->
          cached = cache_ticket(ticket, body["expiresAt"], state)
          {{:ok, [url: state.rpc_url, ticket: ticket]}, %{state | ticket: cached}}

        _ ->
          {error(:ticket_failed, "Cannot obtain local T3 RPC ticket"), %{state | ticket: nil}}
      end
    end
  end

  defp cache_ticket(ticket, expiry, state) when is_binary(expiry) do
    ttl = Keyword.get(state.opts, :ticket_cache_ttl, 0)

    with true <- ttl > 0,
         {:ok, expires_at, _} <- DateTime.from_iso8601(expiry) do
      until =
        Enum.min([
          System.system_time(:millisecond) + ttl,
          DateTime.to_unix(expires_at, :millisecond),
          DateTime.to_unix(state.credential.expires_at, :millisecond)
        ])

      %{
        value: Secret.new(ticket),
        until: until,
        deadline:
          System.monotonic_time(:millisecond) + max(until - System.system_time(:millisecond), 0)
      }
    else
      _ -> nil
    end
  end

  defp cache_ticket(_, _, _), do: nil

  defp retire(state, nil), do: state
  defp retire(state, credential), do: %{state | retired: [credential | state.retired]}

  defp cleanup_retired(state) do
    retired = Enum.reject(state.retired, &(revoke(&1, state.opts) == :ok))
    %{state | retired: retired}
  end

  defp cli(opts), do: Keyword.get_lazy(opts, :cli, &CLI.new/0)

  defp issue_arguments(opts) do
    [
      "auth",
      "session",
      "issue",
      "--json",
      "--ttl",
      Keyword.get(opts, :ttl, "24h"),
      "--label",
      Keyword.get(opts, :label, "t3-elixir-local-service")
    ] ++
      Enum.flat_map(Keyword.get(opts, :scopes, ["orchestration:read"]), &["--scope", &1]) ++
      base_arguments(opts)
  end

  defp base_arguments(opts) do
    case Keyword.get(opts, :base_dir) do
      nil -> []
      dir -> ["--base-dir", dir]
    end
  end

  defp validate_issue_options(opts) do
    strings = [
      Keyword.get(opts, :ttl, "24h"),
      Keyword.get(opts, :label, "t3-elixir-local-service")
    ]

    scopes = Keyword.get(opts, :scopes, ["orchestration:read"])
    base_dir = Keyword.get(opts, :base_dir)

    if Enum.all?(strings, &(is_binary(&1) and String.trim(&1) != "")) and
         is_list(scopes) and scopes != [] and
         Enum.all?(scopes, &(is_binary(&1) and String.trim(&1) != "")) and
         (is_nil(base_dir) or (is_binary(base_dir) and base_dir != "")) and
         match?(%CLI{}, cli(opts)) do
      :ok
    else
      :error
    end
  end

  defp credential(%{"sessionId" => id, "token" => token, "expiresAt" => expiry})
       when is_binary(id) and id != "" and is_binary(token) and token != "" and is_binary(expiry) do
    with {:ok, expires_at, _} <- DateTime.from_iso8601(expiry),
         :gt <- DateTime.compare(expires_at, DateTime.utc_now()) do
      {:ok, %Credential{session_id: id, token: Secret.new(token), expires_at: expires_at}}
    else
      _ -> :error
    end
  end

  defp credential(_), do: :error

  defp local_urls(origin) when is_binary(origin) do
    uri = URI.parse(origin)

    cond do
      is_binary(uri.host) and uri.host not in ["localhost", "127.0.0.1", "::1"] ->
        {:error, :non_local_origin}

      uri.scheme in ["http", "https"] and uri.host in ["localhost", "127.0.0.1", "::1"] and
        uri.path in [nil, "", "/"] and is_nil(uri.userinfo) and is_nil(uri.query) and
          is_nil(uri.fragment) ->
        rpc = %{uri | scheme: if(uri.scheme == "https", do: "wss", else: "ws"), path: "/ws"}
        {:ok, String.trim_trailing(origin, "/"), URI.to_string(rpc)}

      true ->
        :error
    end
  end

  defp local_urls(_), do: :error
  defp error(code, message), do: {:error, %Error{kind: :local_auth, code: code, message: message}}
end
