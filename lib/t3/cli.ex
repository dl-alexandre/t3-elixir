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
    @type t :: %__MODULE__{exit_status: non_neg_integer() | nil, output: binary() | nil}
  end

  @doc "Configure the executable, working directory, environment, deadline and output limit."
  @spec new() :: t()
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    client = struct!(__MODULE__, default_executable(opts))

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
  @spec run(t(), [String.t()]) :: {:ok, Result.t()} | {:error, Error.t()}
  @spec run(t(), [String.t()], keyword()) :: {:ok, Result.t()} | {:error, Error.t()}
  def run(%__MODULE__{} = client, args, opts \\ []) do
    started = System.monotonic_time()
    :telemetry.execute([:t3, :cli, :run, :start], %{system_time: System.system_time()}, %{})

    try do
      result =
        with {:ok, pid} <-
               stream(
                 client,
                 args,
                 opts |> Keyword.put_new(:input, "") |> Keyword.put(:owner, self())
               ) do
          await(pid)
        end

      :telemetry.execute(
        [:t3, :cli, :run, :stop],
        %{duration: System.monotonic_time() - started},
        %{outcome: if(match?({:ok, _}, result), do: :ok, else: :error)}
      )

      result
    rescue
      error ->
        :telemetry.execute(
          [:t3, :cli, :run, :exception],
          %{duration: System.monotonic_time() - started},
          %{error: error.__struct__}
        )

        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        :telemetry.execute(
          [:t3, :cli, :run, :exception],
          %{duration: System.monotonic_time() - started},
          %{error: kind}
        )

        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @doc "Start a linked runner; :owner defaults to caller. Stdin stays open unless :input is supplied."
  @spec stream(t(), [String.t()]) :: GenServer.on_start() | {:error, Error.t()}
  @spec stream(t(), [String.t()], keyword()) :: GenServer.on_start() | {:error, Error.t()}
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
  @spec write(pid(), iodata()) :: term()
  def write(pid, data), do: GenServer.call(pid, {:write, IO.iodata_to_binary(data)}, :infinity)

  @doc "Close stdin while continuing to read output (EOF for commands reading `-`)."
  @spec close_stdin(pid()) :: term()
  def close_stdin(pid), do: GenServer.call(pid, :close_stdin, :infinity)

  @doc "Return the OS process ID, or an error with code :process_exited if it already exited."
  @spec os_pid(pid()) :: term()
  def os_pid(pid), do: GenServer.call(pid, :os_pid)

  @doc "Stop a streaming invocation."
  @spec cancel(pid()) :: term()
  def cancel(pid), do: GenServer.call(pid, :cancel)

  @doc "Read version output without modifying T3."
  @spec version() :: {:ok, Result.t()} | {:error, Error.t()}
  @spec version(t()) :: {:ok, Result.t()} | {:error, Error.t()}
  def version(client \\ new()), do: run(client, ["--version"])
  @doc "Read top-level or subcommand help without invoking the operation."
  @spec help() :: {:ok, Result.t()} | {:error, Error.t()}
  @spec help(t()) :: {:ok, Result.t()} | {:error, Error.t()}
  @spec help(t(), [String.t()]) :: {:ok, Result.t()} | {:error, Error.t()}
  def help(client \\ new(), command \\ []), do: run(client, command ++ ["--help"])

  @doc "Discover commands actually advertised by this installed version's help."
  @spec commands() :: {:ok, [map()]} | {:error, Error.t()}
  @spec commands(t()) :: {:ok, [map()]} | {:error, Error.t()}
  @spec commands(t(), [String.t()]) :: {:ok, [map()]} | {:error, Error.t()}
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
  @spec families() :: [String.t()]
  def families,
    do:
      ~w(start serve app pair auth environment browser project thread feedback workflow up status service update install uninstall theme trace doctor policy triage connect)

  for family <-
        ~w(start serve app pair auth environment browser project thread feedback workflow up status service update install uninstall theme trace doctor policy triage connect) do
    @doc "Run the `t3 #{family}` command family. Requires support in the installed T3 version."
    @spec unquote(String.to_atom(family))(t()) ::
            {:ok, Result.t()} | {:error, Error.t()}
    @spec unquote(String.to_atom(family))(t(), [String.t()]) ::
            {:ok, Result.t()} | {:error, Error.t()}
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

  defp default_executable(opts) do
    if not Keyword.has_key?(opts, :executable) do
      case System.get_env("T3CODE_CLI_PATH") do
        path when is_binary(path) and path != "" -> Keyword.put(opts, :executable, path)
        _ -> opts
      end
    else
      opts
    end
  end
end
