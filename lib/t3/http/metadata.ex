defmodule T3.HTTP.Metadata do
  @moduledoc "Named access to T3 HTTP metadata routes. Options accept wire-map JSON/form bodies, query and headers."
  @doc "GET `/.well-known/t3/environment`. Body encoding: none."
  def descriptor(client, opts \\ []), do: T3.HTTP.call(client, :metadata_descriptor, opts)
end
