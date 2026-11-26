defmodule T3.Application do
  @moduledoc "Application callback and configurable default supervision children for T3."
  use Application

  @spec start(Application.start_type(), term()) :: Supervisor.on_start()
  @impl true
  def start(_type, _args) do
    Supervisor.start_link(child_specs(), strategy: :one_for_one, name: T3.Supervisor)
  end

  @doc false
  @spec child_specs() :: [Supervisor.child_spec()]
  def child_specs do
    oauth? = Application.get_env(:t3, :start_oauth_store, true)
    finch? = Application.get_env(:t3, :start_finch, true)
    finch_opts = Application.get_env(:t3, :finch_opts, [])

    oauth =
      if oauth?, do: [{ConduitMcp.Client.OAuth.TokenStore.ETS, name: T3.OAuth.Store}], else: []

    finch =
      if finch? do
        opts = Keyword.put_new(finch_opts, :name, T3.HTTP.Finch)
        [{Finch, opts}]
      else
        []
      end

    oauth ++ finch
  end
end
