defmodule T3.Application do
  @moduledoc false
  use Application
  @impl true
  def start(_type, _args) do
    children = [
      {ConduitMcp.Client.OAuth.TokenStore.ETS, name: T3.OAuth.Store},
      {Finch, name: T3.HTTP.Finch}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: T3.Supervisor)
  end
end
