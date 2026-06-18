# WaitForIt

[![Hex.pm](https://img.shields.io/hexpm/v/wait_for_it.svg)](https://hex.pm/packages/wait_for_it)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/wait_for_it)

Various ways of waiting for things to happen.

WaitForIt lets you wait on the results of asynchronous or remote operations using intuitive,
familiar syntax built on Elixir's own control-flow constructs (`if`, `case`, `cond`). It is
equally at home coordinating concurrent processes in production code and taming flaky timing in
tests.

```elixir
# Wait until a record shows up, and bind it directly:
{:ok, user} = WaitForIt.match_wait({:ok, %User{}}, Repo.fetch(User, id), timeout: 2_000)

# Wait until an expression is truthy:
if WaitForIt.wait(File.exists?("data.csv"), timeout: :timer.minutes(1)) do
  IO.puts(File.read!("data.csv"))
end
```

## Why WaitForIt?

Elixir gives you `Process.sleep/1`, `receive`/`after`, and `Task.await/2`, but reaching for them
every time you need to wait for a condition is tedious and error-prone. WaitForIt wraps that
machinery in a handful of expressive macros so that "wait until X" reads like the code you'd
already write — no hand-rolled polling loops, no sprinkled `Process.sleep/1` calls in tests.

## The five forms of waiting

| Form | Waits until… | Looks like |
| ---- | ------------ | ---------- |
| [`wait/2`](https://hexdocs.pm/wait_for_it/WaitForIt.html#wait/2) | an expression is truthy | a bare expression |
| [`match_wait/3`](https://hexdocs.pm/wait_for_it/WaitForIt.html#match_wait/3) | an expression matches a pattern (binding out of it) | a `<-` clause |
| [`case_wait/3`](https://hexdocs.pm/wait_for_it/WaitForIt.html#case_wait/3) | an expression matches one of several clauses | a `case` expression |
| [`cond_wait/2`](https://hexdocs.pm/wait_for_it/WaitForIt.html#cond_wait/2) | one of several expressions is truthy | a `cond` expression |
| [`with_wait/3`](https://hexdocs.pm/wait_for_it/WaitForIt.html#with_wait/3) | several composed waits all succeed | a `with` expression |

Each form has a `!` variant (`wait!/2`, `match_wait!/3`, …) that raises `WaitForIt.TimeoutError`
on timeout instead of returning a falsy value or raising the matching built-in error.

## Options

All forms accept the same options:

| Option | Default | Description |
| ------ | ------- | ----------- |
| `:timeout` | `5_000` | total time to wait, in milliseconds, before giving up |
| `:interval` | `100` | polling interval, in milliseconds, between re-evaluations (alias: `:frequency`) |
| `:pre_wait` | `0` | delay before the first evaluation, in milliseconds |
| `:signal` | — | disable polling and re-evaluate only when the named signal is received |

See [Polling vs signaling](guides/polling_vs_signaling.md) for when to reach for `:signal`.

## Installation

Add `wait_for_it` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:wait_for_it, "~> 2.2"}
  ]
end
```

Then `require WaitForIt` (or `import WaitForIt`) where you want to use it.

## Guides

Start here and read in order, or jump to whatever fits the task at hand:

1. [Waiting in tests](guides/waiting_in_tests.md) — the most common entry point: ExUnit
   assertions and using the waiting macros in tests.
2. [Polling vs signaling](guides/polling_vs_signaling.md) — the two waiting modes and when to use
   each.
3. [Composing waits](guides/composing_waits.md) — chaining several waits with `with_wait/3`.
4. [Recipes](guides/recipes.md) — ready-made patterns for databases, processes, HTTP, and more.
5. [Telemetry](guides/telemetry.md) — observing waits in production.

Full API documentation is on [HexDocs](https://hexdocs.pm/wait_for_it).

## License

Apache License 2.0. See [LICENSE](LICENSE).
