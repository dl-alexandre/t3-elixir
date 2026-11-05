defmodule T3.RPC.Catalog do
  @moduledoc """
  Pinned upstream WebSocket method inventory. Methods accept their original JSON
  wire payloads; this catalog does not pretend to validate TypeScript schemas.
  The transport supports arbitrary method strings for forward compatibility.
  """
  @external_resource Path.join(__DIR__, "catalog.json")
  @catalog @external_resource |> File.read!() |> JSON.decode!()
  def upstream_ref, do: @catalog["upstream_ref"]
  def protocol_version, do: @catalog["protocol_version"]
  def methods, do: @catalog["methods"]
  def names, do: Enum.map(methods(), & &1["name"])

  def fetch(name) do
    case Enum.find(methods(), &(&1["name"] == name)) do
      nil -> :error
      method -> {:ok, method}
    end
  end
end
