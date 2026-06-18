# Recipes

Practical patterns for common waiting problems. All examples assume `import WaitForIt`.

## Wait for a database record

Wait until a record exists, binding it directly:

```elixir
{:ok, order} = match_wait({:ok, %Order{}}, Repo.fetch(Order, order_id), timeout: :timer.seconds(5))
```

Or, if you only need to assert it eventually appears:

```elixir
order = wait(Repo.get(Order, order_id), timeout: :timer.seconds(5))
```

## Wait for a record to reach a state

`case_wait/3` is a natural fit when a record moves through states and you want to react to each
terminal outcome:

```elixir
case_wait Repo.reload(job).status, timeout: :timer.seconds(30), interval: 250 do
  :completed -> {:ok, job}
  :failed -> {:error, :job_failed}
else
  status -> {:error, {:timeout, status}}
end
```

## Wait for a process or named entity to register

Wait for a process to be registered (for example via `Registry` or a named `GenServer`):

```elixir
pid = wait(Process.whereis(MyApp.Worker), timeout: 2_000)
```

```elixir
match_wait([{pid, _}] when is_pid(pid), Registry.lookup(MyApp.Registry, :worker), timeout: 2_000)
```

## Poll an external HTTP endpoint until ready

Useful when bringing up a dependency (a service, a container) that becomes ready asynchronously:

```elixir
case_wait Req.get(health_url), timeout: :timer.seconds(30), interval: 500 do
  {:ok, %{status: 200}} -> :ready
else
  _ -> raise "service did not become healthy in time"
end
```

## Producer/consumer backpressure with signaling

When you control the producer, signaling avoids polling latency. The consumer blocks until the
buffer has enough items; the producer signals after adding to it:

```elixir
# CONSUMER
messages =
  case_wait Queue.get_messages(queue), signal: :queue_filled, timeout: :timer.seconds(30) do
    msgs when length(msgs) >= 5 -> msgs
  else
    msgs -> msgs
  end

# PRODUCER
Queue.put(queue, message)
WaitForIt.signal(:queue_filled)
```

See [Polling vs signaling](polling_vs_signaling.md) for the trade-offs.

## Wait for several conditions at once

`cond_wait/2` waits until any one of several independent conditions becomes truthy:

```elixir
cond_wait timeout: :timer.seconds(10) do
  File.exists?("ready.flag") -> :ready_by_flag
  System.monotonic_time(:second) >= deadline -> :ready_by_deadline
else
  :gave_up
end
```

## Guard against runaway mailboxes

A real-world use: pause before pushing more work onto a process whose mailbox is filling up:

```elixir
case_wait Process.info(worker_pid, :message_queue_len), interval: 10, timeout: 60_000 do
  {:message_queue_len, len} when len < 500 -> send_next_chunk()
else
  {:message_queue_len, len} -> raise "worker overwhelmed (#{len} queued messages)"
end
```

---

**Previous:** [Composing waits](composing_waits.md) · **Next:** [Telemetry](telemetry.md)
