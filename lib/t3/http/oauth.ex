defmodule T3.HTTP.OAuth do
  @moduledoc "Named access to T3 HTTP oauth routes. Options accept wire-map JSON/form bodies, query and headers."
  @doc "GET `/.well-known/oauth-protected-resource`. Body encoding: none."
  def protected_resource(client, opts \\ []),
    do: T3.HTTP.call(client, :oauth_protected_resource, opts)

  @doc "GET `/.well-known/oauth-protected-resource/mcp`. Body encoding: none."
  def mcp_protected_resource(client, opts \\ []),
    do: T3.HTTP.call(client, :oauth_mcp_protected_resource, opts)

  @doc "GET `/.well-known/oauth-authorization-server`. Body encoding: none."
  def authorization_server(client, opts \\ []),
    do: T3.HTTP.call(client, :oauth_authorization_server, opts)

  @doc "POST `/oauth/mcp/register`. Body encoding: json."
  def register(client, opts \\ []), do: T3.HTTP.call(client, :oauth_register, opts)
  @doc "GET `/oauth/mcp/authorize`. Body encoding: none."
  def authorize(client, opts \\ []), do: T3.HTTP.call(client, :oauth_authorize, opts)
  @doc "POST `/oauth/mcp/approval`. Body encoding: json."
  def approval(client, opts \\ []), do: T3.HTTP.call(client, :oauth_approval, opts)
  @doc "POST `/oauth/mcp/decision`. Body encoding: json."
  def decision(client, opts \\ []), do: T3.HTTP.call(client, :oauth_decision, opts)
  @doc "POST `/oauth/mcp/token`. Body encoding: form."
  def token(client, opts \\ []), do: T3.HTTP.call(client, :oauth_token, opts)
end
