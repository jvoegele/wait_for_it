# Telemetry

Every wait performed by WaitForIt is instrumented with [`:telemetry`](https://hexdocs.pm/telemetry)
events, so you can observe waiting in production: how long waits take, how many evaluations they
need, and how often they time out.

## Events

WaitForIt emits a standard telemetry span under the `[:wait_for_it, :wait]` prefix.

### `[:wait_for_it, :wait, :start]`

Emitted when a wait begins.

- **Measurements:** `%{system_time, monotonic_time}`
- **Metadata:** `%{wait_type, timeout, interval, signal, env}`

### `[:wait_for_it, :wait, :stop]`

Emitted when a wait finishes — whether the waiting condition was met or the wait timed out.

- **Measurements:** `%{duration, evaluations}`
  - `duration` is in native time units (use `System.convert_time_unit/3` to convert).
  - `evaluations` is the number of times the waitable expression was evaluated.
- **Metadata:** `%{wait_type, timeout, interval, signal, env, result, last_value}`
  - `result` is `:matched` (the condition was met) or `:timeout`.

### `[:wait_for_it, :wait, :exception]`

Emitted only if evaluating the waitable expression raises, throws, or exits unexpectedly. A
timeout is **not** an exception: it is reported as a `:stop` event with `result: :timeout`.

- **Measurements:** `%{duration}`
- **Metadata:** `%{wait_type, timeout, interval, signal, env, kind, reason, stacktrace}`

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
