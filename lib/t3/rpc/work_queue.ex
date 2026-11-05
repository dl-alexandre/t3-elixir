defmodule T3.RPC.WorkQueue do
  @moduledoc """
  Optional bounded, ordered, in-memory processing for reader chunks.

  Supervise this process before the reader. `:work` is a function receiving an
  event and returning `:ok`; it runs in an isolated worker. `enqueue/2` returns
  immediately after admission, so upstream ACK means accepted in memory, **not**
  processed or durable. A crash/kill of this queue can lose accepted work. Use a
  durable application queue inside the normal synchronous reader callback when
  processing must survive failures.

  `:capacity` (default 32) counts the running event plus queued events. A full
  queue returns `{:error, :busy}`, which Reader understands for chunk callbacks:
  it retains that chunk and withholds its ACK until admission succeeds. Only one
  worker runs, preserving admission order. `:work_timeout` defaults to 30 seconds.
  Worker failures/timeouts notify the required `:owner` PID or registered process as
  `{:t3_work_queue, queue, {:failed, event}}` and processing continues. Handle this
  notification explicitly if retries or reconciliation are required. Work is not
  retried automatically, because its side effects may already have occurred.

  Status output omits work, queued data and callback closures.
  """
  use GenServer

  def start_link(opts) do
    {server_opts, opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @doc "Admit work without waiting for execution, or return `{:error, :busy}`."
  def enqueue(server, event), do: GenServer.call(server, {:enqueue, event})

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    work = Keyword.fetch!(opts, :work)
    capacity = Keyword.get(opts, :capacity, 32)
    timeout = Keyword.get(opts, :work_timeout, 30_000)

    owner =
      case Keyword.fetch!(opts, :owner) do
        name when is_atom(name) -> Process.whereis(name)
        pid -> pid
      end

    if is_function(work, 1) and is_integer(capacity) and capacity > 0 and
         is_integer(timeout) and timeout > 0 and is_pid(owner) do
      {:ok,
       %{
         work: work,
         capacity: capacity,
         timeout: timeout,
         owner: owner,
         queue: :queue.new(),
         size: 0,
         active: nil
       }}
    else
      {:stop, %T3.Error{kind: :configuration, message: "invalid work queue configuration"}}
    end
  end

  @impl true
  def handle_call({:enqueue, _}, _, %{size: size, capacity: size} = state),
    do: {:reply, {:error, :busy}, state}

  def handle_call({:enqueue, event}, _, state) do
    state = %{state | queue: :queue.in(event, state.queue), size: state.size + 1}
    {:reply, :ok, start_next(state)}
  end

  @impl true
  def handle_info({:work_done, pid, result}, %{active: %{pid: pid} = active} = state) do
    Process.cancel_timer(active.timer)
    if result != :ok, do: notify_failure(state, active.event)
    {:noreply, finish(state)}
  end

  def handle_info({:work_timeout, pid}, %{active: %{pid: pid} = active} = state) do
    Process.exit(pid, :kill)
    notify_failure(state, active.event)
    {:noreply, finish(state)}
  end

  def handle_info({:EXIT, pid, _}, %{active: %{pid: pid} = active} = state) do
    Process.cancel_timer(active.timer)
    notify_failure(state, active.event)
    {:noreply, finish(state)}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp start_next(%{active: nil} = state) do
    case :queue.out(state.queue) do
      {{:value, event}, queue} ->
        owner = self()
        work = state.work
        {:ok, pid} = Task.start_link(fn -> send(owner, {:work_done, self(), work.(event)}) end)
        timer = Process.send_after(self(), {:work_timeout, pid}, state.timeout)
        %{state | queue: queue, active: %{pid: pid, timer: timer, event: event}}

      {:empty, _} ->
        state
    end
  end

  defp start_next(state), do: state
  defp finish(state), do: start_next(%{state | active: nil, size: state.size - 1})

  defp notify_failure(state, event),
    do: send(state.owner, {:t3_work_queue, self(), {:failed, event}})

  @impl true
  def terminate(_, %{active: %{pid: pid}}), do: Process.exit(pid, :kill)
  def terminate(_, _), do: :ok

  @impl true
  def format_status(status),
    do: %{status | state: :redacted, message: :redacted, reason: :redacted}
end
