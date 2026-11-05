defmodule T3.Tools do
  @moduledoc """
  One named function per known T3 MCP wire tool.

  Each function takes `(client, string_keyed_arguments \\ %{})` without changing
  the arguments. These canonical names provide complete discoverable coverage;
  category modules offer shorter names and existing convenience signatures.
  A wrapper's existence does not grant permission or an agent invocation context.
  Consult `T3.Catalog` and the server's discovered input schemas before use.
  """
  for tool <- T3.Catalog.tools() do
    @doc tool.description <> "\n\n" <> tool.context
    @spec unquote(tool.canonical_function)(T3.Client.t(), map()) ::
            {:ok, map()} | {:error, T3.Error.t()}
    def unquote(tool.canonical_function)(client, arguments \\ %{}) when is_map(arguments),
      do: T3.Client.call_tool(client, unquote(tool.name), arguments)
  end
end
