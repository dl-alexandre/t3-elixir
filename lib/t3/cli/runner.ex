defmodule T3.CLI.Runner do
  @moduledoc false
  use GenServer
  alias T3.{CLI, Error}
  alias Exile.Process, as: External

  def start_link(client, executable, args, owner, opts),
    do: GenServer.start_link(__MODULE__, {client, executable, args, owner, opts})

  @impl true
  def init({client, executable, args, owner, opts}) do
    Process.flag(:trap_exit, true)
    timer = Process.send_after(self(), :deadline, client.timeout)

    external_opts = [
      env: Enum.reject(client.env, &is_nil(elem(&1, 1))),
      stderr: :redirect_to_stdout
    ]

    unset = for {key, nil} <- client.env, do: key

    command =
      if unset == [],
        do: [executable | args],
        else:
          [System.find_executable("env") | Enum.flat_map(unset, &["-u", &1])] ++
            [executable | args]

    external_opts =
      if client.cwd, do: Keyword.put(external_opts, :cd, client.cwd), else: external_opts

    with {:ok, process} <- External.start_link(command, external_opts),
         {:ok, os_pid} <- External.os_pid(process) do
      runner = self()

      reader =
        spawn_link(fn ->
          receive do
            {:start, process} -> read_loop(runner, process)
          end
        end)

      writer =
        spawn_link(fn ->
          receive do
            {:start, process} -> write_loop(runner, process)
          end
        end)

      :ok = External.change_pipe_owner(process, :stdout, reader)
      :ok = External.change_pipe_owner(process, :stdin, writer)
      send(reader, {:start, process})
      send(writer, {:start, process})

      if Keyword.has_key?(opts, :input),
        do: send(writer, {:finite_input, IO.iodata_to_binary(Keyword.fetch!(opts, :input))})

      {:ok,
       %{
         process: process,
         os_pid: os_pid,
         reader: reader,
         writer: writer,
         owner: owner,
         monitor: Process.monitor(owner),
         timer: timer,
         writes: %{},
         bytes: 0,
         output: [],
         max: client.max_output_bytes,
         eof?: false,
         exit_status: nil
       }}
    else
      {:error, _} ->
        {:stop, %Error{kind: :cli, code: :launch_failed, message: "Cannot launch T3 executable"}}
    end
  rescue
    _ in [ArgumentError, ErlangError] ->
      {:stop, %Error{kind: :cli, code: :launch_failed, message: "Cannot launch T3 executable"}}
  catch
    :exit, _ ->
      {:stop, %Error{kind: :cli, code: :launch_failed, message: "Cannot launch T3 executable"}}
  end

  @impl true
  def handle_info({:output, data}, state) do
    if state.bytes + byte_size(data) > state.max do
      fail(state, :output_limit, "T3 CLI output limit exceeded")
    else
      send(state.owner, {:t3_cli, self(), {:data, data}})
      send(state.reader, :read_more)
      {:noreply, %{state | bytes: state.bytes + byte_size(data), output: [data | state.output]}}
    end
  end

  def handle_info(:output_eof, state), do: finish(%{state | eof?: true})

  def handle_info({ref, {:ok, status}}, %{process: %{exit_ref: ref}} = state),
    do: finish(%{state | exit_status: status})

  def handle_info({ref, {:error, _}}, %{process: %{exit_ref: ref}} = state),
    do: fail(state, :process_failed, "T3 CLI process failed")

  def handle_info({:write_result, ref, result}, state) do
    case Map.pop(state.writes, ref) do
      {nil, _} ->
        {:noreply, state}

      {from, writes} ->
        GenServer.reply(from, result)
        {:noreply, %{state | writes: writes}}
    end
  end

  def handle_info({:pipe_error, _}, state), do: fail(state, :pipe_failed, "T3 CLI pipe failed")
  def handle_info(:deadline, state), do: fail(state, :timeout, "T3 CLI command timed out")

  def handle_info({:DOWN, ref, :process, _, _}, %{monitor: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:EXIT, pid, reason}, state) do
    cond do
      pid == state.process.pid and reason != :normal ->
        fail(state, :process_failed, "T3 CLI process failed")

      pid in [state.reader, state.writer] and reason != :normal ->
        fail(state, :pipe_failed, "T3 CLI pipe failed")

      true ->
        {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  @impl true
  def handle_call(:os_pid, _from, state), do: {:reply, {:ok, state.os_pid}, state}
  def handle_call({:write, data}, from, state), do: write_request(state, from, {:write, data})
  def handle_call(:close_stdin, from, state), do: write_request(state, from, :close)

  def handle_call(:cancel, _from, state) do
    send(state.owner, {:t3_cli, self(), {:error, error(:cancelled, "T3 CLI command cancelled")}})
    {:stop, :normal, :ok, state}
  end

  @impl true
  def terminate(_, state) do
    Process.cancel_timer(state.timer)
    Enum.each(state.writes, fn {_, from} -> GenServer.reply(from, {:error, :closed}) end)
    # Exile's separately supervised watcher also cleans up if this runner is killed.
    safely(fn -> External.kill(state.process, :sigkill) end)
    for pid <- [state.reader, state.writer], Process.alive?(pid), do: Process.exit(pid, :kill)
    safely(fn -> External.await_exit(state.process, 500) end)
    :ok
  end

  @impl true
  def format_status(status) do
    Map.update(status, :state, nil, fn state ->
      Map.take(state, [:os_pid, :bytes, :max, :eof?, :exit_status])
    end)
  end

  defp write_request(state, from, action) do
    if Process.alive?(state.writer) do
      ref = make_ref()
      send(state.writer, {action, ref})
      {:noreply, %{state | writes: Map.put(state.writes, ref, from)}}
    else
      {:reply, {:error, :stdin_closed}, state}
    end
  end

  defp read_loop(runner, process) do
    case safely(fn -> External.read(process, 65_536) end) do
      {:ok, data} ->
        send(runner, {:output, IO.iodata_to_binary(data)})

        receive do
          :read_more -> read_loop(runner, process)
        end

      :eof ->
        send(runner, :output_eof)

      _ ->
        send(runner, {:pipe_error, :stdout})
    end
  end

  defp write_loop(runner, process) do
    receive do
      {{:write, data}, ref} ->
        result = safely(fn -> External.write(process, data) end)
        send(runner, {:write_result, ref, result})
        write_loop(runner, process)

      {:close, ref} ->
        result = safely(fn -> External.close_stdin(process) end)
        send(runner, {:write_result, ref, result})
        write_loop(runner, process)

      {:finite_input, data} ->
        result =
          safely(fn ->
            if data != "", do: External.write(process, data)
            External.close_stdin(process)
          end)

        if data != "" and result != :ok, do: send(runner, {:pipe_error, :stdin})
        write_loop(runner, process)
    end
  end

  defp safely(fun) do
    fun.()
  catch
    :exit, _ -> {:error, :closed}
  end

  defp finish(%{eof?: true, exit_status: status} = state) when is_integer(status) do
    result = %CLI.Result{
      exit_status: status,
      output: state.output |> Enum.reverse() |> IO.iodata_to_binary()
    }

    send(state.owner, {:t3_cli, self(), {:exit, result}})
    {:stop, :normal, state}
  end

  defp finish(state), do: {:noreply, state}

  defp fail(state, code, message) do
    send(state.owner, {:t3_cli, self(), {:error, error(code, message)}})
    {:stop, :normal, state}
  end

  defp error(code, message), do: %Error{kind: :cli, code: code, message: message}
end
