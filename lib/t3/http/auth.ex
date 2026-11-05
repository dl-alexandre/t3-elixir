defmodule T3.HTTP.Auth do
  @moduledoc "Named access to T3 HTTP auth routes. Options accept wire-map JSON/form bodies, query and headers."
  @doc "GET `/api/auth/session`. Body encoding: none."
  def session(client, opts \\ []), do: T3.HTTP.call(client, :auth_session, opts)
  @doc "POST `/api/auth/browser-session`. Body encoding: json."
  def browser_session(client, opts \\ []), do: T3.HTTP.call(client, :auth_browser_session, opts)
  @doc "POST `/oauth/token`. Body encoding: form."
  def token(client, opts \\ []), do: T3.HTTP.call(client, :auth_token, opts)
  @doc "POST `/api/auth/websocket-ticket`. Body encoding: none."
  def web_socket_ticket(client, opts \\ []),
    do: T3.HTTP.call(client, :auth_web_socket_ticket, opts)

  @doc "POST `/api/auth/websocket-ticket/:use`. Body encoding: none."
  def web_socket_ticket_for(client, param_use, opts \\ []),
    do:
      T3.HTTP.call(
        client,
        :auth_web_socket_ticket_for,
        Keyword.put(opts, :params, %{"use" => param_use})
      )

  @doc "POST `/api/auth/pairing-token`. Body encoding: json."
  def pairing_credential(client, opts \\ []),
    do: T3.HTTP.call(client, :auth_pairing_credential, opts)

  @doc "POST `/api/auth/pairing-links/revoke`. Body encoding: json."
  def revoke_pairing_link(client, opts \\ []),
    do: T3.HTTP.call(client, :auth_revoke_pairing_link, opts)

  @doc "POST `/api/auth/clients/revoke`. Body encoding: json."
  def revoke_client(client, opts \\ []), do: T3.HTTP.call(client, :auth_revoke_client, opts)
  @doc "POST `/api/auth/clients/revoke-others`. Body encoding: none."
  def revoke_other_clients(client, opts \\ []),
    do: T3.HTTP.call(client, :auth_revoke_other_clients, opts)
end
