defmodule T3.HTTP.Connect do
  @moduledoc "Named access to T3 HTTP connect routes. Options accept wire-map JSON/form bodies, query and headers."
  @doc "POST `/api/connect/link-proof`. Body encoding: json."
  def link_proof(client, opts \\ []), do: T3.HTTP.call(client, :connect_link_proof, opts)
  @doc "POST `/api/connect/relay-config`. Body encoding: json."
  def relay_config(client, opts \\ []), do: T3.HTTP.call(client, :connect_relay_config, opts)
  @doc "GET `/api/connect/link-state`. Body encoding: none."
  def link_state(client, opts \\ []), do: T3.HTTP.call(client, :connect_link_state, opts)
  @doc "POST `/api/connect/reachability`. Body encoding: none."
  def check_reachability(client, opts \\ []),
    do: T3.HTTP.call(client, :connect_check_reachability, opts)

  @doc "POST `/api/connect/unlink`. Body encoding: none."
  def unlink(client, opts \\ []), do: T3.HTTP.call(client, :connect_unlink, opts)
  @doc "POST `/api/connect/preferences`. Body encoding: json."
  def preferences(client, opts \\ []), do: T3.HTTP.call(client, :connect_preferences, opts)
  @doc "POST `/api/t3-connect/health`. Body encoding: json."
  def health(client, opts \\ []), do: T3.HTTP.call(client, :connect_health, opts)
  @doc "POST `/api/t3-connect/mint-credential`. Body encoding: json."
  def mint_credential(client, opts \\ []),
    do: T3.HTTP.call(client, :connect_mint_credential, opts)
end
