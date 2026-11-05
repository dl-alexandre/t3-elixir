defmodule T3.OAuth do
  @moduledoc """
  T3 sign-in using ConduitMCP's OAuth discovery, registration, PKCE and callback handling.
  Defaults to read-only scope. Tokens stay in Conduit's in-memory store unless the
  caller supplies a custom `:store` in `:oauth_options`. The caller owns single-use
  consumption of flows created through `begin/2`; `login/2` uses a one-shot listener.
  """
  alias ConduitMcp.Client.OAuth
  alias T3.Error

  defmodule Flow do
    @moduledoc "Private pending OAuth authorization."
    @derive {Inspect, only: [:authorization_url]}
    defstruct [:authorization_url, :config, :pending]
  end

  @doc "Run a sign-in with a temporary loopback callback. Requires an :open URL callback."
  def login(client, opts) do
    config = config(client, opts)

    options =
      opts |> Keyword.take([:open, :timeout, :port, :path]) |> Keyword.put(:scopes, scopes(opts))

    case OAuth.Loopback.run(config, options) do
      {:ok, tokens} ->
        T3.Client.close(client)

        {:ok,
         %{client | token: tokens.access_token, connected?: false, name: nil, supervisor: nil}}

      {:error, reason} ->
        failure(reason)
    end
  end

  @doc "Begin a sign-in for an application serving its own :redirect_uri."
  def begin(client, opts) do
    config =
      config(client, opts) |> Keyword.put(:redirect_uri, Keyword.fetch!(opts, :redirect_uri))

    case OAuth.authorize_url(config, scopes: scopes(opts)) do
      {:ok, url, pending} ->
        {:ok, %Flow{authorization_url: url, config: config, pending: pending}}

      {:error, reason} ->
        failure(reason)
    end
  end

  @doc "Validate a complete callback URL and exchange its code for secret-wrapped tokens."
  def complete(%Flow{} = flow, callback_url) do
    uri = URI.parse(callback_url)

    if %{uri | query: nil} == URI.parse(flow.pending.redirect_uri) do
      case OAuth.handle_callback(flow.pending, URI.decode_query(uri.query || ""),
             config: flow.config
           ) do
        {:ok, tokens} -> {:ok, tokens}
        {:error, reason} -> failure(reason)
      end
    else
      {:error, %Error{kind: :oauth, message: "OAuth redirect URI mismatch"}}
    end
  end

  defp config(client, opts) do
    loopback? = URI.parse(client.url).host in ["localhost", "127.0.0.1", "::1"]

    defaults = [
      store: {ConduitMcp.Client.OAuth.TokenStore.ETS, name: T3.OAuth.Store},
      server_url: client.url,
      client_metadata: [client_name: Keyword.get(opts, :client_name, "T3 Elixir Client")],
      allow_insecure_oauth: loopback?,
      allow_private: if(loopback?, do: ["127.0.0.0/8", "::1/128"], else: [])
    ]

    Keyword.merge(defaults, Keyword.get(opts, :oauth_options, []))
    |> Keyword.put(:server_url, client.url)
  end

  defp scopes(opts), do: opts |> Keyword.get(:scope, "orchestration:read") |> String.split()

  defp failure(reason),
    do: {:error, %Error{kind: :oauth, message: "T3 OAuth sign-in failed", details: reason}}
end
