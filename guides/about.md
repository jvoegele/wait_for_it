# About WaitForIt

WaitForIt is an Elixir library for waiting on things that have not happened yet — a record to
land in the database, a background job to finish, a process to register, a buffer to fill. It
provides five waiting forms, each one shaped like an Elixir control-flow construct you already
use, plus ExUnit assertions built on the same machinery.

## The ideas

### Waiting deserves better than `Process.sleep/1`

Elixir gives you everything needed to build waiting — `Process.sleep/1`, `receive`/`after`,
`Task.async/1` and `Task.await/2`. What it does not give you is a convenient way to *express* the
thing you are waiting for.

So the same three shapes get rewritten in project after project. A `Process.sleep(500)` that
guesses, and is either flaky or slow depending on which way it guessed. A hand-rolled recursive
polling loop, ten lines of plumbing that obscures the one line that matters. Or a restructuring
of the whole flow around messages, which is often the right answer but is not always available —
the other side may be a database, an HTTP endpoint, or a library you do not control.

WaitForIt's premise is that the condition itself is the interesting part, and everything around it
— the loop, the deadline, the interval, the last-value bookkeeping — is not.

### Borrow the syntax rather than invent it

The library adds no new vocabulary of its own for control flow. Each waiting form is a waiting
version of something already in the language:

| Form | Mirrors |
| --- | --- |
| `wait/2` | truthiness, as tested by `if` |
| `match_wait/3` | the match operator, `=` |
| `case_wait/3` | `case` |
| `cond_wait/2` | `cond` |
| `with_wait/3` | `with` |

This is what keeps the surface area small. You do not learn five constructs; you learn that each
familiar one has a patient sibling.

### One rule for what happens when a wait gives up

The same borrowing decides timeout behavior:

> On timeout, each form behaves exactly as its built-in Elixir counterpart would on a final
> evaluation in which nothing matched.

A `case_wait` raises `CaseClauseError`, a `match_wait` raises `MatchError`, a `with_wait` returns
the last unmatched value — each for exactly the reason its native counterpart does. The forms
disagree with one another about whether an unmatched value raises or is returned, because `=`,
`case`, `cond`, and `with` themselves disagree. WaitForIt inherits that rather than papering over
it, so each form stays a faithful waiting version of the thing it mirrors.

Two deliberate additions sit on top, both with native precedent: an `else` block that turns a
timeout into a value (as `with`'s `else` and `receive`'s `after` do), and a `!` variant of every
form that raises a uniform `WaitForIt.TimeoutError` instead.

### Two ways to wait, one syntax

Polling asks again on a timer and needs no cooperation from anyone, which is why it is the
default. Signaling parks the waiter on its mailbox until the code that changes the condition says
so, which is faster and cheaper but couples the two sides.

Both are the same `:signal` option away from each other, and no other part of the call changes.
See [Polling vs signaling](polling_vs_signaling.md).

### Production-grade, not just test-grade

Waiting in a test suite is the most common use, but not the only one. The library treats waits as
something that can run in a live system: timeouts are computed from a single monotonic deadline,
so a clock adjustment mid-wait cannot skew them; every wait emits `:telemetry` events carrying
duration, evaluation count, outcome, and source location; and the polling interval accepts a
backoff function so a struggling dependency is not hammered while you wait on it.

## History

WaitForIt was first released in August 2017, with `wait`, `case_wait`, and `cond_wait`, and with
both polling and condition-variable signaling in place from the start. The 1.x line added `else`
clauses, the `:pre_wait` option, and `wait!` over the following years.

**2.0** (November 2023) rewrote the internals and changed what the macros return: instead of
`{:ok, value}` / `{:timeout, ms}` tuples, each form returns the value its native counterpart
would, which is what made `wait/2` usable directly in an `if` or an `assert`. The 1.x behavior
remains available, unchanged, in `WaitForIt.V1`.

**2.2** (June 2026) began a modernization pass: a single monotonic deadline for every wait,
`:telemetry` instrumentation, the `WaitForIt.Backoff` strategies, the `with_wait/3` composition
form, the `WaitForIt.Test` ExUnit assertions, and the first task-focused guides. **2.3** added the
functional `until/2`, for conditions built at runtime rather than written at compile time, and
**2.4** added `timeout: :infinity` and per-construct telemetry attribution. The releases since have
gone to documentation, agent-facing usage rules, and tooling rather than to new waiting API.

The full list is in the [Changelog](changelog.html).

## License

WaitForIt is released under the Apache 2.0 license, and developed at
[github.com/jvoegele/wait_for_it](https://github.com/jvoegele/wait_for_it). Issues and pull
requests are welcome.
