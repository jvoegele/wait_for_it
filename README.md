# WaitForIt

[![Hex.pm](https://img.shields.io/hexpm/v/wait_for_it.svg)](https://hex.pm/packages/wait_for_it)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wait_for_it)

<!-- README START -->

Various ways of waiting for things to happen.

WaitForIt lets you wait on the results of asynchronous or remote operations using intuitive,
familiar syntax built on Elixir's own control-flow constructs (`if`, `case`, `cond`, and `with`).
It is equally at home coordinating concurrent processes in production code and taming flaky timing
in tests.

```elixir
# Wait until a record shows up, and bind it directly:
{:ok, user} = WaitForIt.match_wait({:ok, %User{}}, Repo.fetch(User, id), timeout: 2_000)
```

Elixir provides several language and standard library features — such as `Process.sleep/1`,
`receive/1`/`after`, and `Task.async/1`/`Task.await/2` — that can be used to implement waiting, but
they are inconvenient for the purpose. WaitForIt builds on top of them to provide convenient,
expressive facilities for waiting on specific conditions. This is most obviously useful in tests
that must wait for concurrent or asynchronous activity to complete, but it is just as useful
anywhere concurrent processes coordinate their activity — asynchronous event handling,
producer-consumer processes, and time-based activity.

To use WaitForIt, `require WaitForIt` or `import WaitForIt`.

If you are just getting started, the task-focused guides walk through the most common scenarios:
[Waiting in tests](guides/waiting_in_tests.md), [Polling vs signaling](guides/polling_vs_signaling.md),
[Composing waits](guides/composing_waits.md), [Recipes](guides/recipes.md), and
[Telemetry](guides/telemetry.md).

## The five forms of waiting

| Form | Waits until… | Looks like |
| ---- | ------------ | ---------- |
| `wait/2` | an expression is truthy | a bare expression |
| `match_wait/3` | an expression matches a pattern (binding out of it) | a `<-` clause |
| `case_wait/3` | an expression matches one of several clauses | a `case` expression |
| `cond_wait/2` | one of several expressions is truthy | a `cond` expression |
| `with_wait/3` | several composed waits all succeed | a `with` expression |

Each form has a `!` variant (`wait!/2`, `match_wait!/3`, …) that raises `WaitForIt.TimeoutError`
on timeout instead of returning a falsy value or raising the matching built-in error.

#### wait

`wait/2` waits until a given expression evaluates to a truthy value.

```elixir
# Wait up to one minute for a file to exist, then print its contents.
if WaitForIt.wait(File.exists?("data.csv"), timeout: :timer.minutes(1)) do
  IO.puts(File.read!("data.csv"))
else
  IO.warn("Stopped waiting for the file to exist")
end
```

#### match_wait

`match_wait/3` waits until a given expression matches a given pattern, and binds out of it. It is
the most convenient form when waiting for a tagged result such as `{:ok, value}`.

```elixir
{:ok, user} = WaitForIt.match_wait({:ok, %User{}}, Repo.fetch(User, id), timeout: 2_000)
```

#### case_wait

`case_wait/3` waits until a given expression matches one of the given case clauses. It looks and
acts like a `case/2` expression, except that it can take an optional `else` clause.

```elixir
WaitForIt.case_wait(File.stat("data"), timeout: :timer.seconds(30)) do
  {:ok, %File.Stat{type: :directory}} ->
    File.write!("data/greeting.txt", "Hello, world!")
else
  {:ok, %File.Stat{type: type}} ->
    IO.warn("Expected 'data' to be a directory but its type is #{inspect(type)}")

  {:error, reason} ->
    IO.warn("Could not stat 'data': #{inspect(reason)}")
end
```

#### cond_wait

`cond_wait/2` waits until any one of the given expressions evaluates to a truthy value. It looks
and acts like a `cond/1` expression, except that it can take an optional `else` clause.

```elixir
WaitForIt.cond_wait(timeout: :timer.seconds(10), interval: 500) do
  File.exists?("data/process.json") -> IO.puts("Processing...")
  NaiveDateTime.utc_now().second == 0 -> IO.puts("Top of the minute!")
else
  IO.warn("Stopped waiting since neither condition ever became truthy")
end
```

#### with_wait

`with_wait/3` composes several waits in a pipeline. It looks and acts like a `with/1` expression,
except that its `<~` clauses *wait* until their expression matches.

```elixir
WaitForIt.with_wait on(
  {:ok, account} <~ {load_account(token), timeout: 2_000},
  {:ok, balance} <~ fetch_balance(account)
) do
  {:ok, balance}
else
  not_ready -> {:error, {:timed_out, not_ready}}
end
```

## Options

All forms of waiting accept the same options:

| Option | Default | Description |
| ------ | ------- | ----------- |
| `:timeout` | `5_000` | total time to wait, in milliseconds, before giving up |
| `:interval` | `100` | polling interval, in milliseconds, between re-evaluations (alias: `:frequency`) |
| `:pre_wait` | `0` | delay before the first evaluation, in milliseconds |
| `:signal` | — | disable polling and re-evaluate only when the named signal is received |

See the **Polling-based waiting** and **Signal-based waiting** sections below for the `:interval`
and `:signal` options. The `:interval` option may also be a `WaitForIt.Backoff` function for
exponential or custom backoff.

> #### `:frequency` is now `:interval` {: .info}
>
> The `:frequency` option has been renamed to `:interval`, which more accurately describes a time
> value in milliseconds. `:frequency` continues to work as an alias and is slated for removal in a
> future major version. If both are given, `:interval` takes precedence.

## Timeout behavior

There is really only **one rule** to learn here:

> On timeout, each form behaves exactly as its built-in Elixir counterpart would on a final
> evaluation in which nothing matched.

That is the whole design. A `case_wait` that times out raises `CaseClauseError` for the same
reason a `case` does when no clause matches; a `with_wait` that times out returns the last
unmatched value for the same reason a `with` does; and so on. If you already know how the native
construct behaves when its expression doesn't match, you already know how the waiting form behaves
when it gives up — there is nothing WaitForIt-specific to memorize.

Two consistent additions sit on top of that rule:

- An optional **`else` clause** (on the forms whose native counterpart raises) turns a timeout into
  a value instead of an error — the deliberate escape hatch when you'd rather handle "gave up" than
  rescue it. It is the same idea as `with`'s `else` and `receive`'s `after`.
- A **`!` variant** of every form (`wait!/2`, `match_wait!/3`, …) replaces whatever the non-bang
  form would do with a single, uniform `WaitForIt.TimeoutError`. Reach for it when you want a
  timeout-specific error regardless of which form you're using.

The table below is reference, not new rules — each row is just the rule above made concrete:

| Construct | Native counterpart | Counterpart when nothing matches | On timeout (no `else`) | With `else` | Bang variant |
| --------- | ------------------ | -------------------------------- | ---------------------- | ----------- | ------------ |
| `wait/2` | truthiness / polling `if` | (yields the falsy value) | returns the last falsy value | _(no `else`)_ | `TimeoutError` |
| `match_wait/3` | `=` (match operator) | raises `MatchError` | raises `MatchError` | _(no `else`)_ | `TimeoutError` |
| `case_wait/3` | `case` | raises `CaseClauseError` | raises `CaseClauseError` | evaluates `else` | `TimeoutError` |
| `cond_wait/2` | `cond` | raises `CondClauseError` | raises `CondClauseError` | evaluates `else` | `TimeoutError` |
| `with_wait/3` | `with` | returns the unmatched value | returns the last value | evaluates `else` | `TimeoutError` |

The forms differ from one another only because their native counterparts differ — `=`, `case`,
`cond`, and `with` themselves disagree about whether an unmatched value raises or is returned.
WaitForIt deliberately inherits that behavior rather than papering over it, so that each form stays
a faithful, waiting version of the construct you already reach for.

> #### `with_wait` and the `<~` clause {: .info}
>
> `with_wait/3` is the one form with a wrinkle, because its `<~` (wait-for-match) clauses add
> something `with` has no equivalent for. A `<~` clause that never matches before the timeout flows
> to the `else` clause if one is present (otherwise the last value is returned), and `with_wait!/3`
> raises `WaitForIt.TimeoutError` for it. Ordinary `<-` clauses behave exactly as they do in a
> native `with`. See the [Composing waits](guides/composing_waits.md) guide for details.

## Waitable expressions and waiting conditions

A _waitable expression_ is any Elixir expression that can be evaluated one or more times to produce
a value. A _waiting condition_ decides, from that value, whether to keep waiting or to halt with a
result. For `wait/2` the waiting condition is implicit (the truthiness of the expression); for
`case_wait/3` and `with_wait/3` it is the case clauses or `<~` patterns; for `cond_wait/2` it is
the truthiness of each branch.

Because a waitable expression is re-evaluated until its waiting condition is met, idempotent
expressions are of little use — they would either halt immediately or never halt. It is expected
that the value may change on each re-evaluation, and that evaluation may have side effects. Any
such side effects must be safe to repeat, since the expression may be evaluated an indeterminate
number of times while waiting.

## Polling-based waiting

By default, WaitForIt **polls**: it re-evaluates the waitable expression at a fixed interval until
the waiting condition is met or the timeout elapses. The interval is controlled by the `:interval`
option (default `100` ms; the legacy alias `:frequency` is also accepted).

The `:interval` option may also be a 1-arity function of the attempt number, which enables backoff
strategies — for example, polling less aggressively as time goes on so as not to hammer a
struggling dependency. See `WaitForIt.Backoff` for ready-made strategies such as exponential
backoff with jitter.

## Signal-based waiting

Signal-based waiting removes the polling loop: instead of re-checking on a timer, a waiter blocks
until it receives a *signal* telling it to re-evaluate. Opt in with the `:signal` option, naming a
signal (any term, typically an atom), and have the code that changes the condition call
`signal/1`.

Imagine a producer-consumer problem in which a consumer waits for items to appear in a buffer while
a separate producer occasionally places items in the buffer:

```elixir
# CONSUMER process
WaitForIt.wait(Buffer.count() >= 4, signal: :buffer_filled)

# PRODUCER process — after putting some things in the buffer, signal waiters
Buffer.put(item)
WaitForIt.signal(:buffer_filled)
```

Both sides share the same signal name, which binds the producer to the consumer. A signal does not
mean the condition is now satisfied — only that waiters should re-evaluate. The wait halts when its
condition is met, or continues until the next signal or the timeout.

See the [Polling vs signaling](guides/polling_vs_signaling.md) guide for guidance on choosing
between the two modes.

## Telemetry

Every wait emits [`:telemetry`](https://hexdocs.pm/telemetry) events under the
`[:wait_for_it, :wait]` prefix — `:start`, `:stop`, and `:exception` — so you can observe how long
waits take, how many evaluations they require, and how often they time out. The `:stop` event
reports the wait `duration`, the number of `evaluations`, and whether the wait `:matched` or hit a
`:timeout`.

See the [Telemetry](guides/telemetry.md) guide for the full measurement and metadata reference,
plus examples of attaching handlers and wiring up `Telemetry.Metrics`.

## Using WaitForIt in tests

Tests — especially integration and end-to-end tests — are one of the most common places to wait on
asynchronous work. The `WaitForIt.Test` module provides ExUnit assertions (`assert_eventually/2`,
`refute_eventually/2`, and `assert_always/2`) that wait and re-evaluate and, on timeout, fail with
a regular `ExUnit.AssertionError` that includes the source expression and the last value seen:

```elixir
defmodule MyApp.SomeTest do
  use ExUnit.Case
  use WaitForIt.Test

  test "the user is eventually confirmed" do
    assert_eventually {:ok, %User{confirmed: true}} = Repo.fetch(User, user_id)
  end
end
```

The waiting macros can also be used directly in tests when you want their exact return values or
timeout semantics — `wait/2`, for example, returns its value and so drops straight into an
`assert`. See the [Waiting in tests](guides/waiting_in_tests.md) guide for a full walkthrough.

## A note on "catch-all" clauses

It is common to include "catch-all" clauses in normal `case/2` and `cond/1` expressions — a final
`_` clause, or a final always-truthy `true` condition. When using `case_wait/3` and `cond_wait/2`,
*avoid* such catch-all clauses: because they always match, they would halt the wait on the very
first evaluation. Use an `else` clause instead, which is only evaluated on timeout and lets you
customize the behavior and return value when a wait gives up.

<!-- README END -->

## Installation

Add `wait_for_it` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wait_for_it, "~> 2.2"}
  ]
end
```

## Documentation

Full documentation is on [HexDocs](https://hexdocs.pm/wait_for_it). The guides cover common
scenarios, and read well in order:

1. [Waiting in tests](guides/waiting_in_tests.md) — ExUnit assertions and using the waiting macros
   in tests.
2. [Polling vs signaling](guides/polling_vs_signaling.md) — the two waiting modes and when to use
   each.
3. [Composing waits](guides/composing_waits.md) — chaining several waits with `with_wait/3`.
4. [Recipes](guides/recipes.md) — ready-made patterns for databases, processes, HTTP, and more.
5. [Telemetry](guides/telemetry.md) — observing waits in production.

## License

Apache License 2.0. See [LICENSE](LICENSE).
