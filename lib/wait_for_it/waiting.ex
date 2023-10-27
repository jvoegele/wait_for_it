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

  def wait_loop(waitable, wait_opts, env) do
    pre_wait(wait_opts[:pre_wait])

    if wait_opts[:signal] do
      signaling_wait_loop(waitable, wait_opts, env)
    else
      polling_wait_loop(waitable, wait_opts, env)
    end
  end

  defp polling_wait_loop(waitable, wait_opts, env) do
    time_bomb = start_time_bomb(self(), wait_opts[:timeout])
    wait_for_tick = fn -> wait_for_tick(wait_opts[:frequency], time_bomb) end

    try do
      eval_loop(waitable, wait_opts, env, wait_for_tick)
    after
      stop_time_bomb(time_bomb)
    end
  end

  defp signaling_wait_loop(waitable, wait_opts, env) do
    signal = wait_opts[:signal]
    register_for_signal(signal, env)
    wait_for_signal = fn -> wait_for_signal(signal, wait_opts[:timeout], now()) end

    try do
      eval_loop(waitable, wait_opts, env, wait_for_signal)
    after
      unregister_from_signal(signal)
    end
  end

  defp eval_loop(waitable, wait_opts, env, sleeper_fun) do
    case Waitable.evaluate(waitable, env) do
      {:cont, value} ->
        case sleeper_fun.() do
          :loop ->
            eval_loop(waitable, wait_opts, env, sleeper_fun)

          {:timeout, timeout} ->
            if wait_opts[:on_timeout] == :raise do
              raise WaitForIt.TimeoutError, timeout: timeout, wait_type: :wait!, last_value: value
            else
              Waitable.handle_timeout(waitable, value, env)
            end
        end

      {:halt, value} ->
        value
    end
  end

  defp pre_wait(0), do: :ok
  defp pre_wait(time), do: Process.sleep(time)

  defp now, do: System.system_time(:millisecond)

  defp start_time_bomb(waiting_pid, timeout) do
    {:ok, time_bomb_pid} =
      Task.start(fn ->
        Process.sleep(timeout)
        send(waiting_pid, {self(), timeout})
      end)

    time_bomb_pid
  end

  defp stop_time_bomb(time_bomb) when is_pid(time_bomb), do: Process.exit(time_bomb, :kill)

  defp wait_for_tick(tick_time, time_bomb) when is_integer(tick_time) and is_pid(time_bomb) do
    receive do
      {^time_bomb, timeout} -> {:timeout, timeout}
    after
      tick_time -> :loop
    end
  end

  defp register_for_signal(signal, env) do
    Registry.register(WaitForIt.SignalRegistry, signal, env)
  end

  defp unregister_from_signal(signal) do
    Registry.unregister(WaitForIt.SignalRegistry, signal)
  end

  defp wait_for_signal(signal, timeout, start_time) do
    elapsed_time = now() - start_time
    remaining_time = timeout - elapsed_time

    receive do
      {:wait_for_it_signal, ^signal} -> :loop
    after
      remaining_time -> {:timeout, timeout}
    end
  end
end
