defmodule T3.CLI do
  @moduledoc """
  Shell-free access to the installed T3 command line interface, using Exile.

  `run/2` collects bounded output; `stream/3` delivers
  `{:t3_cli, runner, {:data, binary}}`, then either
  `{:t3_cli, runner, {:exit, result}}` or `{:t3_cli, runner, {:error, error}}`.
  Long-running servers can use `stream/3` with an appropriate finite timeout.
  Cancelling kills the directly invoked executable; detached grandchildren are not managed.
  Requires Linux or macOS and a C toolchain to build Exile's native code.
  Pipes support stdin and EOF; arbitrary inherited descriptors (such as
  `--bootstrap-fd`) and terminal/PTY-only interaction are not provided.
  CLI capabilities vary by installed version. No command is executed by construction.

      cli = T3.CLI.new()
      T3.CLI.run(cli, ["thread", "send", thread_id, "-"], input: "Review these changes")

      {:ok, runner} = T3.CLI.stream(cli, ["thread", "send", thread_id, "-"])
      :ok = T3.CLI.write(runner, "Review these changes")
      :ok = T3.CLI.close_stdin(runner)
      # Receive {:t3_cli, runner, {:data, bytes}}, then {:exit, result} / {:error, error}.

  """
  alias T3.Error
  @derive {Inspect, only: [:executable, :cwd, :timeout, :max_output_bytes]}
  defstruct executable: "t3", cwd: nil, env: [], timeout: 30_000, max_output_bytes: 1_048_576
  @type t :: %__MODULE__{}

  defmodule Result do
    @moduledoc "A completed CLI invocation. stdout and stderr share the output field."
    @derive {Inspect, only: [:exit_status]}
    defstruct [:exit_status, :output]
  end

  @doc "Configure the executable, working directory, environment, deadline and output limit."
  def new(opts \\ []) do
    client = struct!(__MODULE__, opts)

    unless is_binary(client.executable) and client.executable != "",
      do: raise(ArgumentError, "executable must be a nonempty string")

    unless is_nil(client.cwd) or (is_binary(client.cwd) and File.dir?(client.cwd)),
      do: raise(ArgumentError, "cwd must be an existing directory")

    unless is_integer(client.timeout) and client.timeout > 0,
      do: raise(ArgumentError, "timeout must be a positive integer")

    unless is_integer(client.max_output_bytes) and client.max_output_bytes > 0,
      do: raise(ArgumentError, "max_output_bytes must be a positive integer")

    unless is_list(client.env) and
             Enum.all?(client.env, fn
               {k, v} -> is_binary(k) and (is_binary(v) or is_nil(v))
               _ -> false
             end),
           do: raise(ArgumentError, "env must contain string key/value pairs (nil unsets)")

    client
  end

  @doc "Run T3 with literal arguments. Optional :input iodata is written then stdin closes; default input is empty."
  def run(%__MODULE__{} = client, args, opts \\ []) do
    with {:ok, pid} <-
           stream(
             client,
             args,
             opts |> Keyword.put_new(:input, "") |> Keyword.put(:owner, self())
           ) do
      await(pid)
    end
  end

  @doc "Start a linked runner; :owner defaults to caller. Stdin stays open unless :input is supplied."
  def stream(%__MODULE__{} = client, args, opts \\ []) do
    unless is_list(args) and Enum.all?(args, &is_binary/1),
      do: raise(ArgumentError, "arguments must be a list of strings")

    case System.find_executable(client.executable) do
      nil ->
        {:error, %Error{kind: :cli, code: :not_found, message: "T3 executable not found"}}

      executable ->
        T3.CLI.Runner.start_link(
          client,
          executable,
          args,
          Keyword.get(opts, :owner, self()),
          opts
        )
    end
  end

  @doc "Write iodata to the streaming command's stdin."
  def write(pid, data), do: GenServer.call(pid, {:write, IO.iodata_to_binary(data)}, :infinity)

  @doc "Close stdin while continuing to read output (EOF for commands reading `-`)."
  def close_stdin(pid), do: GenServer.call(pid, :close_stdin, :infinity)

  @doc "Return the OS process ID, or an error with code :process_exited if it already exited."
  def os_pid(pid), do: GenServer.call(pid, :os_pid)

  @doc "Stop a streaming invocation."
  def cancel(pid), do: GenServer.call(pid, :cancel)

  @doc "Read version output without modifying T3."
  def version(client \\ new()), do: run(client, ["--version"])
  @doc "Read top-level or subcommand help without invoking the operation."
  def help(client \\ new(), command \\ []), do: run(client, command ++ ["--help"])

  @doc "Discover commands actually advertised by this installed version's help."
  def commands(client \\ new(), command \\ []) do
    with {:ok, result} <- help(client, command) do
      commands =
        case String.split(result.output, "SUBCOMMANDS", parts: 2) do
          [_, section] ->
            Regex.scan(~r/^\s{2}([a-z][a-z0-9-]*)\s{2,}([^\n]*)/m, section)
            |> Enum.map(fn [_, name, description] ->
              %{name: name, description: String.trim(description)}
            end)

          _ ->
            []
        end

      {:ok, commands}
    end
  end

  @doc "Known command families; commands/2 discovers the installed executable's actual support."
  def families,
    do:
      ~w(start serve app pair auth browser project service update uninstall theme trace doctor triage connect thread)

  for family <-
        ~w(start serve app pair auth browser project service update uninstall theme trace doctor triage connect thread) do
    @doc "Run the `t3 #{family}` command family. Requires support in the installed T3 version."
    def unquote(String.to_atom(family))(client, arguments \\ []),
      do: run(client, [unquote(family) | arguments])
  end

  defp await(pid) do
    receive do
      {:t3_cli, ^pid, {:data, _}} ->
        await(pid)

      {:t3_cli, ^pid, {:exit, %Result{exit_status: 0} = result}} ->
        {:ok, result}

      {:t3_cli, ^pid, {:exit, %Result{} = result}} ->
        {:error,
         %Error{
           kind: :cli,
           code: result.exit_status,
           message: "T3 CLI command failed",
           details: result
         }}

      {:t3_cli, ^pid, {:error, error}} ->
        {:error, error}
    end
  end
end
