# WaitForIt usage rules

Waiting on asynchronous or remote work, using syntax built on Elixir's own control-flow
constructs. Most useful in tests that must wait for concurrent activity, and anywhere processes
coordinate.

```elixir
{:ok, user} = WaitForIt.match_wait({:ok, %User{}}, Repo.fetch(User, id), timeout: 2_000)
```

`require WaitForIt` or `import WaitForIt` before using any of it — the five waiting forms are
macros.

## The one rule

> On timeout, each form behaves exactly as its built-in Elixir counterpart would on a final
> evaluation in which nothing matched.

That is the whole design. There is nothing WaitForIt-specific to memorise: a `case_wait` that
times out raises `CaseClauseError` for the same reason a `case` does; a `with_wait` returns the
last unmatched value for the same reason a `with` does.

| Form | Waits until | Native counterpart | On timeout (no `else`) |
| --- | --- | --- | --- |
| `wait/2` | an expression is truthy | truthiness | returns the last falsy value |
| `match_wait/3` | an expression matches a pattern (and binds out of it) | `=` | raises `MatchError` |
| `case_wait/3` | one of several clauses matches | `case` | raises `CaseClauseError` |
| `cond_wait/2` | one of several expressions is truthy | `cond` | raises `CondClauseError` |
| `with_wait/3` | several composed waits all succeed | `with` | returns the last value |

Two consistent additions:

  * An **`else` clause** (on `case_wait`, `cond_wait`, `with_wait`) turns a timeout into a value.
  * A **`!` variant** of every form (`wait!/2`, `match_wait!/3`, …) replaces whatever the
    non-bang form would do with a uniform `WaitForIt.TimeoutError`.

## Options

Every form takes the same ones:

| Option | Default | Meaning |
| --- | --- | --- |
| `:timeout` | `5_000` | total ms to wait before giving up, or `:infinity` |
| `:interval` | `100` | ms between re-evaluations, or a `WaitForIt.Backoff` function |
| `:pre_wait` | `0` | ms to wait before the first evaluation |
| `:signal` | — | disable polling; re-evaluate only when this signal arrives |

Use `:interval`. `:frequency` is a deprecated alias kept for compatibility and slated for
removal in a future major — do not write it in new code.

## The traps

### Waiting blocks the calling process — never wait inside a GenServer callback

A wait is a polling loop in the caller's own process. While it runs, that process does nothing
else.

```elixir
def handle_call(:fetch, _from, state) do
  # ❌ the entire server is blocked for up to 5 seconds; every other caller queues behind this
  {:ok, v} = WaitForIt.match_wait({:ok, _}, remote_fetch(), timeout: 5_000)
  {:reply, v, state}
end
```

Worse, the defaults collide: `WaitForIt`'s default `:timeout` is 5000ms and `GenServer.call/3`'s
default timeout is also 5000ms, so the caller gives up at almost exactly the moment the wait
does — you get a confusing `:timeout` exit from the *caller* rather than the wait's own timeout
behaviour.

Wait in the process that can afford to block: the caller, a `Task`, or a test. If a server must
wait, do it in a spawned task and `handle_info` the result.

### Signals are node-local

`signal/1` dispatches through a local `Registry`, so a signal sent on one node never reaches a
waiter on another. In a distributed application, a wait blocked on `signal: :thing` will sit
there until its timeout while the producer on another node happily signals into the void.

Polling has no such limitation — it re-evaluates the expression, and the expression can consult
anything (a database, a replicated table, a `:global` process). **If the condition can be
changed from another node, poll.**

### Never write a catch-all clause in `case_wait` or `cond_wait`

This is the single most common mistake, and it silently disables the waiting.

```elixir
# ❌ `_` matches on the very first evaluation, so this never waits at all
WaitForIt.case_wait Repo.get(Job, id) do
  %Job{status: :done} -> :finished
  _ -> :not_yet
end

# ✅ `else` runs only on timeout
WaitForIt.case_wait Repo.get(Job, id), timeout: 10_000 do
  %Job{status: :done} -> :finished
else
  _ -> :gave_up
end
```

The same applies to a final `true ->` in `cond_wait`. A clause that always matches halts the
wait on the first evaluation; `else` is evaluated *only* when the wait gives up.

### The expression is re-evaluated, so its side effects must be repeatable

A waitable expression runs an indeterminate number of times. An idempotent expression is useless
here — it either halts immediately or never halts — so it is *expected* that the value changes
between evaluations, and any side effect must be safe to repeat. Do not put a POST, an insert, or
a counter increment in a waitable expression.

### `timeout: :infinity` removes all timeout behaviour

Not just "waits longer". Because such a wait can never time out: a `!` variant never raises, an
`else` clause never runs, and `until/2` never returns `{:timeout, last_value}`. The process
blocks until the condition is met or it dies. Reach for it only where something else bounds the
wait — a supervised process, a `Task` with its own timeout, or a caller that can shut it down.

### `with_wait` uses two different arrows

```elixir
WaitForIt.with_wait on(
  {:ok, account} <~ {load_account(token), timeout: 2_000},   # WAITS for the match
  {:ok, balance} <- fetch_balance(account)                    # one-shot, exactly like `with`
) do
  {:ok, balance}
else
  not_ready -> {:error, {:timed_out, not_ready}}
end
```

`<~` is wait-for-match; `<-` behaves exactly as in a native `with`. Per-clause options go in a
tuple: `{expr, opts}`. Note the `on(...)` wrapper — it is the one place the "looks like the
native construct" resemblance breaks.

### "The following clause will never match" is telling the truth

On Elixir 1.20+ you may see the type checker flag a `match_wait`/`with_wait` pattern as
unreachable. **Waiting changes values over time; it does not change types.** If the expression's
inferred type cannot produce the pattern, the wait can only ever time out, and the warning has
found a real bug.

The usual innocent cause is a test stub narrow enough for the compiler to pin down
(`defp pending, do: :pending` infers exactly `:pending`). Widen it rather than silencing the
warning:

```elixir
defp pending, do: Process.get(:__unset__, :pending)   # same value, type is now dynamic()
```

## Choosing a form

**`match_wait/3`** is the one to reach for by default when waiting on a tagged result — it waits
and binds in one expression.

**`until/2`** is the functional counterpart of `wait/2`, for when the condition is computed at
runtime or built dynamically and a macro cannot serve. It takes a zero-arity function and returns
a *tagged* result, so success and timeout are never ambiguous:

```elixir
case WaitForIt.until(fn -> Repo.get(Post, id) end, timeout: :timer.seconds(5)) do
  {:ok, post} -> post
  {:timeout, _last} -> raise "post #{id} never appeared"
end
```

`until!/2` returns the bare value and raises `WaitForIt.TimeoutError` instead.

## Polling and backoff

Polling is the default: re-evaluate every `:interval` ms. `:interval` also accepts a 1-arity
function of the attempt number, which is how you back off against a struggling dependency:

```elixir
WaitForIt.wait(Service.ready?(), interval: WaitForIt.Backoff.exponential(cap: 2_000, jitter: true))
```

Signal-based waiting removes the polling loop entirely — a waiter blocks until it receives a
named signal telling it to re-evaluate:

```elixir
# consumer
WaitForIt.wait(Buffer.count() >= 4, signal: :buffer_filled)

# producer, after changing the condition
Buffer.put(item)
WaitForIt.signal(:buffer_filled)
```

A signal does **not** mean the condition is now satisfied — only that waiters should re-check.
Both sides must agree on the signal name, and both must be on the same node.

## In tests

Prefer `WaitForIt.Test`'s assertions over `Process.sleep/1`. They wait, re-evaluate, and on
timeout fail with an ordinary `ExUnit.AssertionError` carrying the source expression and the last
value seen:

```elixir
defmodule MyApp.SomeTest do
  use ExUnit.Case
  use WaitForIt.Test

  test "the user is eventually confirmed" do
    assert_eventually {:ok, %User{confirmed: true}} = Repo.fetch(User, user_id)
  end
end
```

`assert_eventually/2` (truthy or `pattern = expr` binding form), `refute_eventually/2`, and
`assert_always/2` — the last for asserting something stays true for the duration rather than
becomes true.

The waiting macros work in tests too when you want their exact return values or timeout
semantics; `wait/2` returns its value and drops straight into an `assert`.

## Telemetry

Every wait emits `[:wait_for_it, :wait, :start | :stop | :exception]`. The `:stop` event reports
the `duration`, the number of `evaluations`, and whether the wait `:matched` or hit a `:timeout`
— which is how you find waits that are quietly timing out, or polling far more than they need to.

## Deprecated

`WaitForIt.V1` emits compile-time deprecation warnings and will be removed in 3.0. Do not write
new code against it.
