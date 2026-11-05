defmodule T3.Toolset do
  @moduledoc false
  defmacro __using__(opts) do
    category = Keyword.fetch!(opts, :category)
    excluded = Keyword.get(opts, :except, [])

    definitions =
      for tool <- T3.Catalog.tools(category), tool.function not in excluded do
        quote do
          @doc unquote(tool.description <> "\n\n" <> tool.context)
          @spec unquote(tool.function)(T3.Client.t(), map()) ::
                  {:ok, map()} | {:error, T3.Error.t()}
          def unquote(tool.function)(client, arguments \\ %{}) when is_map(arguments),
            do: T3.Client.call_tool(client, unquote(tool.name), arguments)
        end
      end

    quote do
      (unquote_splicing(definitions))
    end
  end
end
