defmodule T3.HTTP.Projects do
  @moduledoc "Named access to T3 HTTP projects routes. Options accept wire-map JSON/form bodies, query and headers."
  @doc "GET `/api/projects`. Body encoding: none."
  def snapshot(client, opts \\ []), do: T3.HTTP.call(client, :projects_snapshot, opts)
  @doc "POST `/api/projects/mutate`. Body encoding: json."
  def mutate(client, opts \\ []), do: T3.HTTP.call(client, :projects_mutate, opts)
end
