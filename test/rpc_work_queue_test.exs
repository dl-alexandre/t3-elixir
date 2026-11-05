defmodule T3.RPC.WorkQueueTest do
  use ExUnit.Case, async: true

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
    assert_receive {:started, first, "private-event-a"}, 1000
    assert :ok = T3.RPC.WorkQueue.enqueue(queue, :second)
    assert {:error, :busy} = T3.RPC.WorkQueue.enqueue(queue, :third)
    refute inspect(:sys.get_status(queue)) =~ "private-event-a"
    send(first, :finish)
    assert_receive {:started, second, :second}, 1000
    assert :ok = T3.RPC.WorkQueue.enqueue(queue, :third)
    send(second, :finish)
    assert_receive {:started, third, :third}, 1000
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
    assert_receive {:t3_work_queue, ^queue, {:failed, :stall}}, 1000
    assert_receive :next_processed, 1000
  end

  test "failed return notifies owner and shutdown kills an active worker" do
    owner = self()

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
    assert_receive {:t3_work_queue, ^queue, {:failed, :fail}}, 1000
    assert :ok = T3.RPC.WorkQueue.enqueue(queue, :block)
    assert_receive {:worker, worker}, 1000
    monitor = Process.monitor(worker)
    stop_supervised!(T3.RPC.WorkQueue)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 1000
  end
end
