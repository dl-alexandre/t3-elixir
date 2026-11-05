defmodule T3.HTTP.Guest do
  @moduledoc """
  Guest-share routes. Supply `query: %{"share" => share_id}` and the appropriate
  guest Cookie header explicitly; a normal MCP bearer is not a guest session.
  `redeem/2` returns Set-Cookie headers for the caller to retain securely.
  `messages/2` accepts JSON or `multipart: T3.HTTP.multipart(fields, files)`.
  """
  for name <- [:redeem, :messages, :session, :render, :item, :history, :attachment, :media] do
    id = String.to_atom("guest_#{name}")
    @doc "Call the guest #{name} endpoint with explicit query, cookie and body options."
    def unquote(name)(client, opts \\ []), do: T3.HTTP.Raw.call(client, unquote(id), opts)
  end

  @doc "Consume guest updates as SSE events with bounded streaming."
  def stream(client, callback, opts \\ []),
    do: T3.HTTP.Raw.stream(client, :guest_stream, callback, opts)

  @doc "Consume a guest command output item as SSE events."
  def command_output(client, callback, opts \\ []),
    do: T3.HTTP.Raw.stream(client, :guest_command_output, callback, opts)
end
