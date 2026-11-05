defmodule Mix.Tasks.T3.Interfaces do
  use Mix.Task
  @shortdoc "Print the SDK interface inventory without connecting to T3"
  @moduledoc """
  `mix t3.interfaces` prints the known interface families and operation counts.
  `mix t3.interfaces --json` prints their complete catalogs as JSON.
  This command does not contact T3 or execute its CLI.
  """
  @impl true
  def run(args) do
    Mix.Task.run("compile")
    interfaces = T3.interfaces()

    if "--json" in args do
      # Module atoms intentionally become strings; the inventory contains no credentials.
      interfaces |> serializable() |> JSON.encode!() |> Mix.shell().info()
    else
      Enum.each([:mcp, :http, :http_raw, :rpc, :web_socket, :cli], fn surface ->
        Mix.shell().info(
          "#{surface}: #{length(Map.fetch!(interfaces, surface))} #{if surface == :cli, do: "command families", else: "operations"}"
        )
      end)

      Mix.shell().info("Upstream: #{T3.Catalog.upstream_ref()}")
    end
  end

  defp serializable(value) when is_map(value),
    do: Map.new(value, fn {key, val} -> {to_string(key), serializable(val)} end)

  defp serializable(value) when is_list(value), do: Enum.map(value, &serializable/1)

  defp serializable(value) when is_atom(value) and value not in [nil, true, false],
    do: Atom.to_string(value)

  defp serializable(value), do: value
end
