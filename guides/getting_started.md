# Getting started

This guide takes you from an empty `mix.exs` to your first wait — in application code and in a
test — in a few minutes. It assumes no prior knowledge of WaitForIt.

For the complete API reference, see the `WaitForIt` module.

## Installation

Add `wait_for_it` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wait_for_it, "~> 2.5"}
  ]
end
```

Then run `mix deps.get`. WaitForIt's only dependency is `:telemetry`. Its application starts a
small supervision tree used by signal-based waiting, so there is nothing for you to add to your
own supervision tree.

The waiting forms are macros, so each module that uses them needs `require WaitForIt` (to call
them as `WaitForIt.wait(...)`) or `import WaitForIt` (to call them bare). The examples below
assume `import WaitForIt`.

One optional step, worth doing now: the macros read best without parentheses, and WaitForIt
exports formatter rules that keep `mix format` from adding them. Add it to `import_deps` in your
`.formatter.exs`:

```elixir
[
  import_deps: [:wait_for_it],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

## The big idea

Asynchronous work finishes when it finishes. Code that needs the result has three bad options and
one good one.

The bad ones are familiar. `Process.sleep(500)` guesses: too short and it is flaky, too long and
every run pays for the worst case. A hand-rolled recursive polling loop works, but it is ten lines
of plumbing that says nothing about what you are waiting for. Restructuring everything around
messages is often right, but not always available — you may not control the other side at all.

The good option is to say what you are waiting *for* and let the library handle the rest:

```elixir
# Wait until the record shows up, then bind it. Gives up after 2 seconds.
{:ok, user} = match_wait({:ok, %User{}}, Repo.fetch(User, id), timeout: 2_000)
```

That returns as soon as the condition holds — not a fixed 500 ms later — and stops after 2
seconds if it never does.

The design idea that makes the rest of the library predictable: **every waiting form mirrors an
Elixir control-flow construct you already know.** `wait/2` is a polling `if`, `case_wait/3` is a
polling `case`, `cond_wait/2` a polling `cond`, `with_wait/3` a polling `with`. You already know
how they are spelled and what they do; the only new thing is that they keep looking.

## Your first wait

`wait/2` is the simplest form. It re-evaluates an expression until it is truthy, and returns
whatever ended the wait:

```elixir
import WaitForIt

# Re-evaluates every 100ms for up to 5 seconds (the defaults).
if wait(File.exists?("data.csv")) do
  IO.puts(File.read!("data.csv"))
else
  IO.warn("gave up waiting for data.csv")
end
```

On success `wait/2` returns the truthy value; on timeout it returns the last falsy value it saw —
which is what lets it drop straight into an `if`.

Two options control the loop, and every form accepts them:

```elixir
wait(Job.finished?(id), timeout: :timer.seconds(30), interval: 250)
```

  * `:timeout` — how long to keep trying before giving up. Default `5_000` ms.
  * `:interval` — how long to pause between attempts. Default `100` ms.

That is enough to be useful. Everything below is about picking a better-fitting form.

## Choosing a form

You picked `wait/2` above because "is it truthy yet?" was the whole question. When the question is
shaped differently, a different form says it more directly:

| You want to… | Use | Which mirrors |
| --- | --- | --- |
| know whether something became truthy | `wait/2` | truthiness, an `if` |
| pull a value out of a tagged result | `match_wait/3` | `=` |
| branch on which of several outcomes arrived | `case_wait/3` | `case` |
| wait for any one of several conditions | `cond_wait/2` | `cond` |
| chain several waits, each depending on the last | `with_wait/3` | `with` |
| build the condition at runtime, not compile time | `until/2` | (a plain function) |

`match_wait/3` is the one you will reach for most in practice, because most Elixir functions
answer with `{:ok, value}` or `{:error, reason}`:

```elixir
{:ok, order} = match_wait({:ok, %Order{}}, Repo.fetch(Order, id), timeout: 2_000)
```

And `case_wait/3` when more than one outcome is interesting:

```elixir
case_wait Repo.reload(job).status, timeout: :timer.seconds(30), interval: 250 do
  :completed -> {:ok, job}
  :failed -> {:error, :job_failed}
else
  status -> {:error, {:timeout, status}}
end
```

Note the `else` block. It runs **only on timeout**, and can match on the last value seen. Which
brings us to the one rule worth learning.

## The one rule about timeouts

> On timeout, each form behaves exactly as its built-in Elixir counterpart would on a final
> evaluation in which nothing matched.

A `case_wait` that gives up raises `CaseClauseError`, because that is what a `case` does when no
clause matches. A `match_wait` that gives up raises `MatchError`, because that is what `=` does.
A `with_wait` returns the last unmatched value, because that is what `with` does.

There is nothing WaitForIt-specific to memorize here — if you know the native construct, you
already know the waiting one. Two escape hatches sit on top:

  * an **`else` block** turns a timeout into a value instead of an error, and
  * a **`!` variant** of every form (`wait!/2`, `match_wait!/3`, …) raises a uniform
    `WaitForIt.TimeoutError` instead, carrying the wait type, the timeout, and the last value.

```elixir
# Raises WaitForIt.TimeoutError, with the last value seen, if the order never arrives.
order = match_wait!({:ok, %Order{}}, Repo.fetch(Order, id), timeout: 2_000)
```

## Your first wait in a test

Tests are where most people meet this library, and they get a dedicated module. `WaitForIt.Test`
provides ExUnit assertions that wait, and that fail like any other ExUnit assertion — with the
source expression and the last value seen — rather than raising a library-specific error:

```elixir
defmodule MyApp.CheckoutTest do
  use ExUnit.Case
  use WaitForIt.Test

  test "the order is eventually fulfilled" do
    start_checkout(order_id)

    assert_eventually {:ok, %Order{status: :fulfilled}} = Repo.fetch(Order, order_id)
  end
end
```

Three assertions are available, with timeouts already tuned for tests:

  * `assert_eventually/2` — becomes truthy, or matches, within the window (default 1 s).
  * `refute_eventually/2` — *never* becomes truthy within the window (default 100 ms).
  * `assert_always/2` — stays truthy for the whole window (default 100 ms).

Reach for these before the raw macros in tests. The [Waiting in tests](waiting_in_tests.md) guide
covers both, and the traps worth knowing.

## When polling is the wrong tool

Everything so far polls: WaitForIt re-runs your expression on a timer. That needs no cooperation
from the code you are waiting on, which is exactly why it is the default.

When you *do* control that code, you can do better. Pass a `:signal` and the waiter blocks on its
mailbox instead of a timer, waking only when the other side says something changed:

```elixir
# CONSUMER — parks until signaled, then re-checks.
wait(Buffer.count() >= 4, signal: :buffer_filled)

# PRODUCER — after doing something that might satisfy waiters.
Buffer.put(item)
WaitForIt.signal(:buffer_filled)
```

No polling latency, no wasted evaluations. See [Polling vs signaling](polling_vs_signaling.md).

## One thing to avoid

Do not put a catch-all clause in a `case_wait/3` or `cond_wait/2`:

```elixir
case_wait Repo.reload(job).status do
  :completed -> {:ok, job}
  _ -> {:error, :unknown}   # ❌ matches on the very first evaluation — this never waits
end
```

A clause that always matches ends the wait immediately. That is what `else` is for: it runs only
on timeout. The same trap has a quieter version — a bare variable pattern in `match_wait/3`
matches anything too. Both are covered in [Waiting in tests](waiting_in_tests.md).

## Where to go next

  * **[Waiting in tests](waiting_in_tests.md)** — the assertions in depth, and using the macros
    directly when you want their exact return values.
  * **[Polling vs signaling](polling_vs_signaling.md)** — the two modes, and choosing
    between them.
  * **[Composing waits](composing_waits.md)** — chaining several waits with `with_wait/3`.
  * **[Recipes](recipes.md)** — patterns for databases, processes, HTTP endpoints, and mailboxes.
  * **[Telemetry](telemetry.md)** — observing waits in production.
  * **[Cheatsheet](cheatsheet.cheatmd)** — every form, option, and default on one page.

---

**Next:** [Waiting in tests](waiting_in_tests.md)
