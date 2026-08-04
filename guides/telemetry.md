# Telemetry

Every wait performed by WaitForIt is instrumented with [`:telemetry`](https://hexdocs.pm/telemetry)
events, so you can observe waiting in production: how long waits take, how many evaluations they
need, and how often they time out.

## Events

WaitForIt emits a standard telemetry span under the `[:wait_for_it, :wait]` prefix.

### `[:wait_for_it, :wait, :start]`

Emitted when a wait begins.

- **Measurements:** `%{system_time, monotonic_time}`
- **Metadata:** `%{wait_type, wait_context, timeout, interval, signal, env}`

### `[:wait_for_it, :wait, :stop]`

Emitted when a wait finishes — whether the waiting condition was met or the wait timed out.

- **Measurements:** `%{duration, evaluations}`
  - `duration` is in native time units (use `System.convert_time_unit/3` to convert).
  - `evaluations` is the number of times the waitable expression was evaluated.
- **Metadata:** `%{wait_type, wait_context, timeout, interval, signal, env, result, last_value}`
  - `result` is `:matched` (the condition was met) or `:timeout`.

### `[:wait_for_it, :wait, :exception]`

Emitted only if evaluating the waitable expression raises, throws, or exits unexpectedly. A
timeout is **not** an exception: it is reported as a `:stop` event with `result: :timeout`.

- **Measurements:** `%{duration}`
- **Metadata:** `%{wait_type, wait_context, timeout, interval, signal, env, kind, reason, stacktrace}`

## The `env` metadata

Every event carries `env`, the source location of the wait — a plain map with
exactly these keys:

| key | |
|---|---|
| `:module` | the module containing the wait |
| `:function` | `{name, arity}`, or `nil` at module level |
| `:file` | absolute path |
| `:line` | line of the wait |
| `:context` | `:match`, `:guard`, or `nil` |
| `:context_modules` | modules being defined at that point |

It is enough to attribute an event to a call site, which is what a handler needs
it for:

```elixir
def handle_event([:wait_for_it, :wait, :stop], meas, %{env: env} = meta, _) do
  Logger.info("#{meta.result} at #{env.file}:#{env.line} after #{meas.duration}")
end
```

> #### This used to be the caller's whole `Macro.Env` {: .info}
>
> Before 2.5.0, `env` was the untrimmed `__ENV__` — roughly 1000 words (~8 KB),
> almost all of it the calling module's import table (`:functions`, `:macros`,
> `:requires`), which grows with the caller's imports and is of no use to a
> handler. It was embedded in the caller's compiled module once per wait and
> copied by every handler that forwarded metadata off-process.
>
> A handler reading anything outside the six keys above needs updating; one
> reading `env.file`/`env.line` does not. The same six fields have always been
> what `WaitForIt.TimeoutError` exposes — the telemetry path simply never applied
> the same cut.

## Wait context

`wait_type` names the *form* of waiting that ran, which is not always the form you wrote. A `<~`
clause in a `with_wait` desugars to a `match_wait`, so its events arrive as
`wait_type: :match_wait` — indistinguishable, on that key alone, from a `match_wait` you wrote
yourself.

The `wait_context` metadata tells the two apart:

- `nil` for a wait written directly (`wait`, `match_wait`, `case_wait`, `cond_wait`, `until`).
- `%{construct: :with_wait, clause: index}` for a `<~` clause of a `with_wait`/`with_wait!`, where
  `index` is the zero-based position of the clause within `on(...)`, counting every clause.

So for this pipeline:

```elixir
with_wait on(
            {:ok, user} <- fetch_user(id),
            {:ok, order} <~ latest_order(user),
            {:ok, ship} <~ shipment(order)
          ) do
  {user, order, ship}
end
```

the two waits report `%{construct: :with_wait, clause: 1}` and `%{construct: :with_wait, clause: 2}`
respectively — the `<-` clause is not a wait and emits nothing, but it still occupies index 0, so
the index always points at the clause as written.

This makes it possible to chart a whole `with_wait` pipeline as a unit, or to find *which* clause
is the slow one:

```elixir
def handle_event([:wait_for_it, :wait, :stop], meas, %{wait_context: %{clause: clause}} = meta, _) do
  Logger.info("with_wait clause #{clause} #{meta.result} after #{meas.duration}")
end

def handle_event([:wait_for_it, :wait, :stop], _meas, _meta, _config), do: :ok
```

## Attaching a handler

```elixir
:telemetry.attach_many(
  "wait-for-it-logger",
  [
    [:wait_for_it, :wait, :stop],
    [:wait_for_it, :wait, :exception]
  ],
  &MyApp.WaitForItHandler.handle_event/4,
  nil
)
```

```elixir
defmodule MyApp.WaitForItHandler do
  require Logger

  def handle_event([:wait_for_it, :wait, :stop], measurements, metadata, _config) do
    ms = System.convert_time_unit(measurements.duration, :native, :millisecond)

    Logger.info(
      "WaitForIt #{metadata.wait_type} #{metadata.result} after #{ms}ms " <>
        "(#{measurements.evaluations} evaluations)"
    )
  end

  def handle_event([:wait_for_it, :wait, :exception], _measurements, metadata, _config) do
    Logger.error("WaitForIt #{metadata.wait_type} crashed: #{inspect(metadata.reason)}")
  end
end
```

## Using `Telemetry.Metrics`

The events compose with [`Telemetry.Metrics`](https://hexdocs.pm/telemetry_metrics) for
dashboards and reporters. For example:

```elixir
import Telemetry.Metrics

[
  # Distribution of wait durations, tagged by the form of waiting and the outcome.
  distribution("wait_for_it.wait.stop.duration",
    unit: {:native, :millisecond},
    tags: [:wait_type, :result]
  ),
  # How many evaluations waits needed — useful for tuning :interval.
  summary("wait_for_it.wait.stop.evaluations", tags: [:wait_type]),
  # Count of timeouts vs matches.
  counter("wait_for_it.wait.stop.duration", tags: [:wait_type, :result])
]
```

Because metadata includes `result`, you can alert on a rising rate of `result: :timeout` for a
given `wait_type` — an early signal that a dependency is getting slow.

---

**Previous:** [Recipes](recipes.md)

That's the end of the guides. See the `WaitForIt` module for the complete API reference.
