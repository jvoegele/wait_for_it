defmodule WaitForIt.Helpers do
  @moduledoc false

  alias WaitForIt.ConditionVariable

  @tag :__wait_for_it_result__

  defmacro localized_name(name) do
    if name do
      quote do: :"#{__MODULE__}.#{unquote(name)}"
    end
  end

  defmacro make_function(nil), do: nil

  defmacro make_function(expression), do: quote do: fn -> unquote(expression) end

  defmacro make_case_function(cases) do
    quote do
      fn expr ->
        case expr do
          unquote(cases)
        end
      end
    end
  end

  defmacro make_cond_function(cond_clauses) do
    quote do
      fn ->
        cond do
          unquote(cond_clauses)
        end
      end
    end
  end

  def wait(expression, frequency, timeout, condition_var) do
    loop(frequency, timeout, condition_var, fn ->
      value = expression.()
      if value, do: {:break, value}, else: :loop
    end)
    |> handle_wait_result()
  end

  def case_wait(expression, frequency, timeout, condition_var, do_block, else_block) do
    loop(frequency, timeout, condition_var, fn ->
      try do
        {:break, do_block.(expression.())}
      rescue
        CaseClauseError -> :loop
      end
    end)
    |> handle_case_wait_result(else_block)
  end

  def cond_wait(frequency, timeout, condition_var, cond_block, else_block) do
    loop(frequency, timeout, condition_var, fn ->
      try do
        {:break, cond_block.()}
      rescue
        CondClauseError -> :loop
      end
    end)
    |> handle_cond_wait_result(else_block)
  end

  def condition_var_signal(condition_var) do
    init_condition_var(condition_var)
    ConditionVariable.signal(condition_var)
  end

  defp loop(frequency, timeout, nil, function) do
    time_bomb = start_time_bomb(self(), timeout)
    result = eval_loop(function, fn -> sleep(time_bomb, frequency) end)
    stop_time_bomb(time_bomb)
    result
  end

  defp loop(_frequency, timeout, condition_var, function) do
    init_condition_var(condition_var)
    start_time = now()
    eval_loop(function, fn -> sleep(condition_var, timeout, start_time) end)
  end

  defp eval_loop(function, sleeper) do
    case function.() do
      {:break, value} ->
        {@tag, value}

      :loop ->
        case sleeper.() do
          :loop -> eval_loop(function, sleeper)
          {:timeout, timeout} -> {@tag, {:timeout, timeout}}
        end
    end
  end

  defp start_time_bomb(waiting_pid, timeout) do
    {:ok, time_bomb} =
      Task.start(fn ->
        receive do
        after
          timeout -> send(waiting_pid, {self(), timeout})
        end
      end)

    time_bomb
  end

  defp stop_time_bomb(time_bomb) when is_pid(time_bomb), do: Process.exit(time_bomb, :kill)

  defp sleep(waiter, frequency) when is_pid(waiter) do
    receive do
      {^waiter, timeout} -> {:timeout, timeout}
    after
      frequency -> :loop
    end
  end

  defp sleep(condition_var, timeout, start_time) when is_atom(condition_var) do
    elapsed_time = now() - start_time
    remaining_time = timeout - elapsed_time

    case ConditionVariable.wait(condition_var, timeout: remaining_time) do
      :ok -> :loop
      :timeout -> {:timeout, timeout}
    end
  end

  defp init_condition_var(var) do
    {:ok, _pid} = ConditionVariable.Supervisor.named_condition_variable(var)
  end

  defp now, do: DateTime.to_unix(DateTime.utc_now(), :millisecond)

  defp handle_wait_result({@tag, {:timeout, timeout}}), do: {:timeout, timeout}
  defp handle_wait_result({@tag, value}), do: {:ok, value}

  defp handle_case_wait_result({@tag, {:timeout, timeout}}, nil), do: {:timeout, timeout}
  defp handle_case_wait_result({@tag, {:timeout, _timeout}}, else_block), do: else_block.()
  defp handle_case_wait_result({@tag, value}, _else_block), do: value

  defp handle_cond_wait_result({@tag, {:timeout, timeout}}, nil), do: {:timeout, timeout}
  defp handle_cond_wait_result({@tag, {:timeout, _timeout}}, else_block), do: else_block.()
  defp handle_cond_wait_result({@tag, value}, _else_block), do: value
end
