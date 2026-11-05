defmodule T3.HTTP.PullRequests do
  @moduledoc "Named access to T3 HTTP pull_requests routes. Options accept wire-map JSON/form bodies, query and headers."
  @doc "POST `/api/pull-requests/diff`. Body encoding: json."
  def diff(client, opts \\ []), do: T3.HTTP.call(client, :pull_requests_diff, opts)
end
