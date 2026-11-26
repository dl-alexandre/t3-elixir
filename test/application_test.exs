defmodule T3.ApplicationTest do
  use ExUnit.Case, async: false

  test "child specs allow disabling defaults and configuring Finch" do
    old_oauth = Application.get_env(:t3, :start_oauth_store)
    old_finch = Application.get_env(:t3, :start_finch)
    old_opts = Application.get_env(:t3, :finch_opts)

    on_exit(fn ->
      restore(:start_oauth_store, old_oauth)
      restore(:start_finch, old_finch)
      restore(:finch_opts, old_opts)
    end)

    Application.put_env(:t3, :start_oauth_store, false)
    Application.put_env(:t3, :start_finch, true)
    Application.put_env(:t3, :finch_opts, name: __MODULE__)

    assert [{Finch, opts}] = T3.Application.child_specs()
    assert opts == [name: __MODULE__]

    Application.put_env(:t3, :start_finch, false)
    Application.put_env(:t3, :start_oauth_store, true)

    assert [{ConduitMcp.Client.OAuth.TokenStore.ETS, name: T3.OAuth.Store}] =
             T3.Application.child_specs()
  end

  defp restore(key, nil), do: Application.delete_env(:t3, key)
  defp restore(key, value), do: Application.put_env(:t3, key, value)
end
