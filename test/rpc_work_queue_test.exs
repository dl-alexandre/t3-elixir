defmodule T3.RPC.WorkQueueTest do
  use ExUnit.Case, async: true

  defmodule NamedOwner do
    use GenServer
    def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: opts[:name])
    def init(opts), do: {:ok, opts[:test_owner]}

    def handle_info(message, owner) do
      send(owner, {:named_owner_message, self(), message})
      {:noreply, owner}
    end
  end

  test "capacity includes active work, preserves admission order and hides queued data" do
    owner = self()

    queue =
      start_supervised!(
        {T3.RPC.WorkQueue,
         owner: self(),
         capacity: 2,
         work: fn event ->
           send(owner, {:started, self(), event})

           receive do
             :finish -> :ok
           end
         end}
      )

    assert :ok = T3.RPC.WorkQueue.enqueue(queue, "private-event-a")
    assert_receive {:started, first, "private-event-a"}
    assert :ok = T3.RPC.WorkQueue.enqueue(queue, :second)
    assert {:error, :busy} = T3.RPC.WorkQueue.enqueue(queue, :third)
    refute inspect(:sys.get_status(queue)) =~ "private-event-a"
    send(first, :finish)
    assert_receive {:started, second, :second}
    assert :ok = T3.RPC.WorkQueue.enqueue(queue, :third)
    send(second, :finish)
    assert_receive {:started, third, :third}
    send(third, :finish)
  end

  test "timeout notifies the owner and admits the next item without retrying side effects" do
    owner = self()

    queue =
      start_supervised!(
        {T3.RPC.WorkQueue,
         owner: self(),
         capacity: 2,
         work_timeout: 40,
         work: fn
           :stall ->
             receive do
               :never -> :ok
             end

           :next ->
             send(owner, :next_processed)
             :ok
         end}
      )

    assert :ok = T3.RPC.WorkQueue.enqueue(queue, :stall)
    assert :ok = T3.RPC.WorkQueue.enqueue(queue, :next)
    assert_receive {:t3_work_queue, ^queue, {:failed, :stall}}
    assert_receive :next_processed
  end

  test "failed return notifies owner and shutdown kills an active worker" do
    owner = self()
    telemetry_id = {__MODULE__, self(), make_ref()}

    :ok =
      :telemetry.attach(
        telemetry_id,
        [:t3, :rpc, :work_queue, :failure],
        &T3.TelemetryTestHandler.handle/4,
        self()
      )

    queue =
      start_supervised!(
        {T3.RPC.WorkQueue,
         owner: self(),
         work: fn
           :fail ->
             {:error, :failed}

           :block ->
             send(owner, {:worker, self()})

             receive do
               :never -> :ok
             end
         end}
      )

    assert :ok = T3.RPC.WorkQueue.enqueue(queue, :fail)
    assert_receive {:t3_work_queue, ^queue, {:failed, :fail}}
    assert_receive {:telemetry_event, [:t3, :rpc, :work_queue, :failure], %{count: 1}, %{}}
    assert :ok = T3.RPC.WorkQueue.enqueue(queue, :block)
    assert_receive {:worker, worker}
    monitor = Process.monitor(worker)
    stop_supervised!(T3.RPC.WorkQueue)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}
    :telemetry.detach(telemetry_id)
  end

  test "a restarted registered owner receives failures" do
    name = Module.concat(__MODULE__, "Owner#{System.unique_integer([:positive])}")
    owner = self()
    child = {NamedOwner, name: name, test_owner: owner}
    {:ok, supervisor} = Supervisor.start_link([child], strategy: :one_for_one)
    first = Process.whereis(name)
    monitor = Process.monitor(first)
    Process.exit(first, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^first, :killed}
    assert eventually(fn -> is_pid(Process.whereis(name)) and Process.whereis(name) != first end)

    queue =
      start_supervised!({T3.RPC.WorkQueue, owner: name, work: fn _ -> {:error, :failed} end})

    assert :ok = T3.RPC.WorkQueue.enqueue(queue, :private_event)

    assert_receive {:named_owner_message, new_owner,
                    {:t3_work_queue, ^queue, {:failed, :private_event}}}

    assert new_owner == Process.whereis(name)
    Supervisor.stop(supervisor)
  end

  defp eventually(fun, attempts \\ 200)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.(),
      do: true,
      else:
        (
          Process.sleep(10)
          eventually(fun, attempts - 1)
        )
  end
end
