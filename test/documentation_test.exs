defmodule T3.DocumentationTest do
  use ExUnit.Case, async: true

  @docs [
    "README.md",
    "INTERFACES.md",
    "LIVE_TESTING.md",
    "RELEASE.md",
    "CONTRIBUTING.md",
    "docs/AUTHENTICATION.md",
    "docs/BOARD_READER.md",
    "docs/BOARD_EVENTS.md",
    "docs/STREAM_CONTRACT.md",
    "docs/TROUBLESHOOTING.md"
  ]

  test "Elixir guide examples parse and reference existing SDK functions" do
    for file <- @docs,
        [snippet] <-
          Regex.scan(~r/```elixir\s*\n(.*?)```/s, File.read!(file), capture: :all_but_first) do
      assert {:ok, ast} = Code.string_to_quoted(snippet), "invalid Elixir example in #{file}"

      Macro.prewalk(ast, fn
        {{:., _, [{:__aliases__, _, [:T3 | rest]}, function]}, _, args} = node
        when is_atom(function) and is_list(args) ->
          module = Module.concat([T3 | rest])
          assert Code.ensure_loaded?(module), "missing #{inspect(module)} in #{file}"

          assert function_exported?(module, function, length(args)),
                 "missing #{inspect(module)}.#{function}/#{length(args)} in #{file}"

          node

        node ->
          node
      end)
    end
  end

  test "relative documentation links resolve inside the checkout" do
    for file <- @docs,
        [target] <-
          Regex.scan(~r/\[[^\]]+\]\(([^)]+)\)/, File.read!(file), capture: :all_but_first),
        not String.starts_with?(target, ["https://", "http://", "mailto:", "#"]) do
      target = target |> String.split("#", parts: 2) |> hd()

      assert File.exists?(Path.expand(target, Path.dirname(Path.expand(file)))),
             "broken link #{target} in #{file}"
    end
  end
end
