defmodule T3.HTTP.PeerLink do
  @moduledoc "Named access to T3 HTTP peer-link routes. Options accept wire-map JSON and headers."

  @doc "POST `/api/peer-link/client-pairing`. Body encoding: json."
  def client_pairing(client, opts \\ []),
    do: T3.HTTP.call(client, :peer_link_client_pairing, opts)
end
