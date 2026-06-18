# Polling vs signaling

WaitForIt supports two waiting modes. Every form of waiting uses one or the other depending on
whether you pass the `:signal` option.

## Polling (the default)

By default, WaitForIt **polls**: it re-evaluates the waiting condition at a fixed interval until
the condition is met or the timeout elapses. The interval is controlled by the `:interval` option
(default `100` ms; the legacy name `:frequency` is still accepted).

```elixir
# Re-evaluate every 250 ms, for up to 30 seconds.
wait(Repo.get(Job, id).status == :done, interval: 250, timeout: :timer.seconds(30))
```

Polling is simple and requires no coordination with the code that changes the condition. It is the
right default when:

- you do not control (or do not want to couple to) the code that causes the change, or
- the thing you are waiting on is external (a file, an HTTP endpoint, a clock), or
- the cost of re-evaluating the condition is low.

The trade-off is latency and wasted work: the condition may become true the instant after a poll,
so you wait up to a full interval longer than necessary, and you re-evaluate even when nothing has
changed.

## Signaling

**Signal-based waiting** removes the polling loop. Instead of re-checking on a timer, the waiter
blocks until it receives a *signal* telling it to re-evaluate. You opt in with the `:signal`
option, naming a signal (any term, typically an atom):

```elixir
# CONSUMER — blocks until signaled, then re-checks the condition.
wait(Buffer.count() >= 4, signal: :buffer_filled)
```

A separate process emits the signal with `WaitForIt.signal/1` when it has done something that
might satisfy the condition:

```elixir
# PRODUCER — after doing work that might unblock waiters:
Buffer.put(item)
WaitForIt.signal(:buffer_filled)
```

Both sides share the same signal name, which is what binds the producer to the consumer.

A signal does **not** mean the condition is now true — it means "it's worth checking again." On
receiving the signal the waiter re-evaluates its condition; if satisfied it stops, otherwise it
keeps waiting for the next signal or the timeout. The `:timeout` option still bounds the total
wait. The `:interval` option is ignored in signal mode.

Signaling is the right choice when:

- you control the code that changes the condition and can emit a signal from it,
- you want minimal latency between the change and the waiter waking up, or
- re-evaluating the condition is expensive enough that polling would be wasteful.

## Choosing between them

| | Polling | Signaling |
| --- | --- | --- |
| Coupling | none | producer must call `WaitForIt.signal/1` |
| Latency | up to one `:interval` | immediate on signal |
| Wasted re-evaluations | yes | no |
| Best for | external/uncontrolled conditions | conditions you control |

When in doubt, start with polling. Reach for signaling once polling latency or overhead becomes a
problem and you control the code that drives the change.

---

**Previous:** [Waiting in tests](waiting_in_tests.md) · **Next:** [Composing waits](composing_waits.md)
