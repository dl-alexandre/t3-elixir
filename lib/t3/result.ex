defmodule T3.Result do
  @moduledoc "Read structured tool data from MCP structuredContent or a JSON text block."
  def data(%{"structuredContent" => data}) when is_map(data), do: {:ok, data}

  def data(%{"content" => blocks}) when is_list(blocks) do
    Enum.find_value(blocks, fn
      %{"type" => "text", "text" => text} when is_binary(text) ->
        case JSON.decode(text) do
          {:ok, data} when is_map(data) -> {:ok, data}
          _ -> nil
        end

      _ ->
        nil
    end) || invalid()
  end

  def data(_), do: invalid()

  defp invalid,
    do: {:error, %T3.Error{kind: :protocol, message: "tool result contains no JSON object"}}
end
