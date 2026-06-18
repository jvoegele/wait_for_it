defmodule WaitForIt.Waiting do
  @moduledoc false

  alias WaitForIt.Waitable

  @default_wait_opts [
    timeout: 5_000,
    frequency: 100,
    pre_wait: 0
  ]

  def wait(waitable, wait_opts, env) do
    wait_loop(waitable, merge_wait_opts(wait_opts), env)
  end

  def wait!(waitable, wait_opts, env) do
    wait_opts = merge_wait_opts(Keyword.put_new(wait_opts, :on_timeout, :raise))
    wait_loop(waitable, wait_opts, env)
  end

  defp merge_wait_opts(user_specified_opts) do
    Keyword.merge(@default_wait_opts, user_specified_opts)
  end

  # A single, unified wait loop drives both polling-based and signal-based waiting.
  #
  # The total time budget is captured once as a monotonic deadline so that the timeout is
  # immune to wall-clock adjustments (NTP steps, container migration, etc.). Each iteration
  # evaluates the waitable; if it has not yet halted, control blocks until either the next
  # evaluation is due (a polling tick or a received signal) or the deadline is reached.
  defp wait_loop(waitable, wait_opts, env) do
    pre_wait(wait_opts[:pre_wait])

    signal = wait_opts[:signal]
    deadline = monotonic_now() + wait_opts[:timeout]

    if signal, do: register_for_signal(signal, env)

    try do
      eval_loop(waitable, wait_opts, env, deadline)
    after
      if signal, do: unregister_from_signal(signal)
    end
  end

  defp eval_loop(waitable, wait_opts, env, deadline) do
    case Waitable.evaluate(waitable, env) do
      {:halt, value} ->
        value

      {:cont, value} ->
        case wait_for_next_evaluation(wait_opts, deadline) do
          :loop -> eval_loop(waitable, wait_opts, env, deadline)
          :timeout -> on_timeout(waitable, value, wait_opts, env)
        end
    end
  end

  defp on_timeout(waitable, last_value, wait_opts, env) do
    if wait_opts[:on_timeout] == :raise do
      Waitable.Raise.raise_timeout_error(waitable, last_value, wait_opts[:timeout], env)
    else
      Waitable.handle_timeout(waitable, last_value, env)
    end
  end

  # Blocks until it is time to re-evaluate the waitable (`:loop`) or the deadline has passed
  # (`:timeout`). Signal-based waiting blocks on the mailbox; polling-based waiting sleeps for
  # one interval. In both cases the remaining time bounds the wait so the deadline is honored.
  defp wait_for_next_evaluation(wait_opts, deadline) do
    remaining = deadline - monotonic_now()

    cond do
      remaining <= 0 -> :timeout
      wait_opts[:signal] -> wait_for_signal(wait_opts[:signal], remaining)
      true -> wait_for_tick(wait_opts[:frequency], remaining)
    end
  end

  defp wait_for_signal(signal, remaining) do
    receive do
      {:wait_for_it_signal, ^signal} -> :loop
    after
      remaining -> :timeout
    end
  end

  # When at least one full interval remains, sleep one interval and re-evaluate. Otherwise sleep
  # out the remaining time and report a timeout without a further evaluation.
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
end
