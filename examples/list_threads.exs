# Run: mix run examples/list_threads.exs
# Optional: T3_PROJECT_ID=<id> to select a project without the prompt.
defmodule T3.Examples.ListThreads do
  def run do
    client = T3.new(url: System.get_env("T3_MCP_URL", "http://127.0.0.1:3773/mcp"))

    with {:ok, client} <-
           T3.OAuth.login(client, open: &IO.puts("Approve read-only access in T3:\n#{&1}")),
         {:ok, client} <- T3.connect(client) do
      try do
        with {:ok, project_id} <- project_id(client),
             {:ok, result} <- T3.Threads.list(client, %{"projectId" => project_id, "limit" => 10}),
             {:ok, data} <- T3.Result.data(result) do
          IO.inspect(data, label: "T3 threads", limit: :infinity)
          :ok
        end
      after
        T3.Client.close(client)
      end
    end
  end

  defp project_id(client) do
    case System.get_env("T3_PROJECT_ID") do
      id when is_binary(id) and id != "" ->
        {:ok, id}

      _ ->
        with {:ok, projects} <- projects(client, %{}, []) do
          select(projects)
        end
    end
  end

  defp projects(client, args, acc) do
    with {:ok, result} <- T3.Projects.list(client, args),
         {:ok, %{"projects" => projects} = data} <- T3.Result.data(result) do
      case data["nextCursor"] do
        nil -> {:ok, acc ++ projects}
        cursor -> projects(client, %{"cursor" => cursor}, acc ++ projects)
      end
    end
  end

  defp select([]), do: {:error, %T3.Error{kind: :not_found, message: "No T3 projects found"}}

  defp select(projects) do
    Enum.with_index(projects, 1)
    |> Enum.each(fn {project, index} ->
      IO.puts("#{index}. #{project["title"]} (#{project["id"]})")
    end)

    input = IO.gets("Project number: ")

    with input when is_binary(input) <- input,
         {index, ""} when index > 0 <- Integer.parse(String.trim(input)),
         %{"id" => id} <- Enum.at(projects, index - 1) do
      {:ok, id}
    else
      _ -> {:error, %T3.Error{kind: :configuration, message: "Choose a valid project number"}}
    end
  end
end

case T3.Examples.ListThreads.run() do
  :ok ->
    :ok

  {:error, error} ->
    IO.puts(:stderr, Exception.message(error))
    System.halt(1)
end
