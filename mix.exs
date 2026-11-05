defmodule T3.MixProject do
  use Mix.Project

  def project do
    [
      app: :t3,
      version: "0.1.0",
      name: "T3",
      source_url: "https://github.com/dl-alexandre/t3-elixir",
      homepage_url: "https://github.com/dl-alexandre/t3-elixir",
      elixir: "~> 1.20",
      docs: [
        main: "readme",
        extras: ["README.md", "INTERFACES.md", "CHANGELOG.md", "LIVE_TESTING.md", "RELEASE.md"]
      ],
      description: "Elixir SDK for T3 Code MCP, HTTP, WebSocket RPC and CLI",
      package: [
        licenses: ["MIT"],
        maintainers: ["dl-alexandre"],
        links: %{
          "GitHub" => "https://github.com/dl-alexandre/t3-elixir",
          "T3 integration documentation" =>
            "https://github.com/pingdotgg/t3code/blob/main/docs/user/outside-agents.md"
        },
        files:
          ~w(lib priv examples mix.exs README.md INTERFACES.md LIVE_TESTING.md RELEASE.md LICENSE CHANGELOG.md .formatter.exs)
      ],
      start_permanent: Mix.env() == :prod,
      elixirc_paths: if(Mix.env() == :test, do: ["lib", "test/support"], else: ["lib"]),
      deps: [
        {:conduit_mcp, "~> 0.11.0"},
        {:finch, "~> 0.24"},
        {:mint_web_socket, "~> 1.0"},
        {:exile, "~> 0.15.0"},
        {:multipart, "~> 0.6.1"},
        {:ex_doc, "~> 0.40", only: :dev, runtime: false}
      ]
    ]
  end

  def application, do: [extra_applications: [:logger, :crypto], mod: {T3.Application, []}]
end
