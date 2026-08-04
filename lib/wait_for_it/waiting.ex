defmodule WaitForIt.Waiting do
  @moduledoc false

  alias WaitForIt.Waitable

  @telemetry_event [:wait_for_it, :wait]

  @default_wait_opts [
    timeout: 5_000,
    interval: 100,
    pre_wait: 0
  ]

  def wait(waitable, wait_opts, env) do
    wait_opts = merge_wait_opts(wait_opts)

    case run(waitable, wait_opts, env) do
      {:matched, value} -> value
      {:timeout, last_value} -> on_timeout(waitable, last_value, wait_opts, env)
    end
  end

  def wait!(waitable, wait_opts, env) do
    wait(waitable, Keyword.put_new(wait_opts, :on_timeout, :raise), env)
  end

  # Runs the wait loop and returns the structured outcome — `{:matched, value}` or
  # `{:timeout, last_value}` — without applying any timeout handling. Used by the functional
  # `WaitForIt.until/2` API, which maps the outcome to a tagged tuple of its own. Distinguishing
  # the outcomes structurally (rather than by the value's shape) matters because a matched value
  # may itself be any term, including a `{:timeout, _}` tuple.
  def wait_outcome(waitable, wait_opts, env) do
    run(waitable, merge_wait_opts(wait_opts), env)
  end

  defp merge_wait_opts(user_specified_opts) do
    Keyword.merge(@default_wait_opts, normalize_interval(user_specified_opts))
  end

  # `:interval` is the preferred option name; `:frequency` is supported as a legacy alias. If
  # both are given, `:interval` wins. (`:frequency` is slated for removal in a future major.)
  defp normalize_interval(opts) do
    case {Keyword.has_key?(opts, :interval), Keyword.fetch(opts, :frequency)} do
      {true, {:ok, _}} ->
        IO.warn("WaitForIt received both :interval and :frequency; using :interval")
        Keyword.delete(opts, :frequency)

      {false, {:ok, frequency}} ->
        opts |> Keyword.delete(:frequency) |> Keyword.put(:interval, frequency)

      _ ->
        opts
    end
  end

  # A single, unified wait loop drives both polling-based and signal-based waiting, wrapped in
  # `:telemetry` start/stop/exception events.
  #
  # The total time budget is captured once as a monotonic deadline so that the timeout is
  # immune to wall-clock adjustments (NTP steps, container migration, etc.). Each iteration
  # evaluates the waitable; if it has not yet halted, control blocks until either the next
  # evaluation is due (a polling tick or a received signal) or the deadline is reached.
  #
  # A `:timeout` of `:infinity` yields an `:infinity` deadline, which is never reached: the loop
  # waits until the condition is met (or the process is killed), and never produces a `:timeout`
  # outcome.
  defp run(waitable, wait_opts, env) do
    metadata = telemetry_metadata(waitable, wait_opts, env)
    start_time = System.monotonic_time()

    :telemetry.execute(
      @telemetry_event ++ [:start],
      %{system_time: System.system_time(), monotonic_time: start_time},
      metadata
    )

    signal = wait_opts[:signal]

    {result, last_value, evaluations} =
      try do
        pre_wait(wait_opts[:pre_wait])
        if signal, do: register_for_signal(signal, env)
        eval_loop(waitable, wait_opts, env, deadline_for(wait_opts[:timeout]), 1)
      rescue
        exception ->
          emit_exception(metadata, start_time, :error, exception, __STACKTRACE__)
          reraise exception, __STACKTRACE__
      catch
        kind, reason ->
          emit_exception(metadata, start_time, kind, reason, __STACKTRACE__)
          :erlang.raise(kind, reason, __STACKTRACE__)
      after
        if signal, do: unregister_from_signal(signal)
      end

    :telemetry.execute(
      @telemetry_event ++ [:stop],
      %{duration: System.monotonic_time() - start_time, evaluations: evaluations},
      Map.merge(metadata, %{result: result, last_value: last_value})
    )

    {result, last_value}
  end

  # Returns `{:matched | :timeout, last_value, evaluation_count}`. A timeout is a normal outcome
  # reported here (and as a `:stop` telemetry event); only an unexpected crash during evaluation
  # surfaces as an exception.
  defp eval_loop(waitable, wait_opts, env, deadline, attempt) do
    case Waitable.evaluate(waitable, env) do
      {:halt, value} ->
        {:matched, value, attempt}

      {:cont, value} ->
        case wait_for_next_evaluation(wait_opts, deadline, attempt) do
          :loop -> eval_loop(waitable, wait_opts, env, deadline, attempt + 1)
          :timeout -> {:timeout, value, attempt}
        end
    end
  end

  defp on_timeout(waitable, last_value, wait_opts, env) do
    case wait_opts[:on_timeout] do
      :raise ->
        Waitable.Raise.raise_timeout_error(waitable, last_value, wait_opts[:timeout], env)

      # Used by `with_wait` clauses: a timeout yields the last (non-matching) value so the
      # enclosing `with` routes it to the `else` block, exactly like an ordinary non-match.
      :return_last_value ->
        last_value

      _ ->
        Waitable.handle_timeout(waitable, last_value, env)
    end
  end

  # Blocks until it is time to re-evaluate the waitable (`:loop`) or the deadline has passed
  # (`:timeout`). Signal-based waiting blocks on the mailbox; polling-based waiting sleeps for
  # one interval. In both cases the remaining time bounds the wait so the deadline is honored.
  defp wait_for_next_evaluation(wait_opts, deadline, attempt) do
    remaining = remaining_time(deadline)

    cond do
      remaining != :infinity and remaining <= 0 -> :timeout
      wait_opts[:signal] -> wait_for_signal(wait_opts[:signal], remaining)
      true -> wait_for_tick(interval_for(wait_opts[:interval], attempt), remaining)
    end
  end

  # An `:infinity` timeout is carried through the loop as an `:infinity` deadline (and hence an
  # `:infinity` remaining time), which every blocking primitive below already understands.
  defp deadline_for(:infinity), do: :infinity
  defp deadline_for(timeout), do: monotonic_now() + timeout

  defp remaining_time(:infinity), do: :infinity
  defp remaining_time(deadline), do: deadline - monotonic_now()

  # The `:interval` option is either a constant number of milliseconds or a 1-arity function of
  # the attempt number (see `WaitForIt.Backoff`), allowing for backoff strategies.
  defp interval_for(interval, _attempt) when is_integer(interval), do: interval
  defp interval_for(interval, attempt) when is_function(interval, 1), do: interval.(attempt)

  defp wait_for_signal(signal, remaining) do
    receive do
      {:wait_for_it_signal, ^signal} -> :loop
    after
      remaining -> :timeout
    end
  end

  # When at least one full interval remains, sleep one interval and re-evaluate. Otherwise sleep
  # out the remaining time and report a timeout without a further evaluation. With no deadline
  # there is always another interval to sleep.
  defp wait_for_tick(interval, :infinity) do
    Process.sleep(interval)
    :loop
  end

  defp wait_for_tick(interval, remaining) when interval < remaining do
    Process.sleep(interval)
    :loop
  end

  defp wait_for_tick(_interval, remaining) do
    Process.sleep(remaining)
    :timeout
  end

  defp pre_wait(0), do: :ok
  defp pre_wait(time), do: Process.sleep(time)

  defp monotonic_now, do: System.monotonic_time(:millisecond)

  defp register_for_signal(signal, env) do
    Registry.register(WaitForIt.SignalRegistry, signal, env)
  end

  defp unregister_from_signal(signal) do
    Registry.unregister(WaitForIt.SignalRegistry, signal)
  end

  # `:wait_context` is set by constructs that desugar to another construct's waitable, so that
  # handlers can tell them apart: a `with_wait` `<~` clause is a `match_wait` like any other, but
  # carries `%{construct: :with_wait, clause: index}`. It is `nil` for a directly-written wait.
  defp telemetry_metadata(waitable, wait_opts, env) do
    %{
      wait_type: Waitable.wait_type(waitable),
      wait_context: wait_opts[:wait_context],
      timeout: wait_opts[:timeout],
      interval: wait_opts[:interval],
      signal: wait_opts[:signal],
      env: WaitForIt.Env.to_map(env)
    }
  end

  defp emit_exception(metadata, start_time, kind, reason, stacktrace) do
    :telemetry.execute(
      @telemetry_event ++ [:exception],
      %{duration: System.monotonic_time() - start_time},
      Map.merge(metadata, %{kind: kind, reason: reason, stacktrace: stacktrace})
    )
  end
end
