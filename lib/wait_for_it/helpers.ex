defmodule WaitForIt.Helpers do
  alias __MODULE__
  alias WaitForIt.ConditionVariable

  defmacro condition_var_wait(expression, condition_var, timeout) do
    quote do
      local_name = Helpers._localized_name(unquote(condition_var))
      Helpers._init_condition_var(local_name)
      start_time = Helpers._now()
      end_time = start_time + unquote(timeout)

      Helpers._loop(true) do
        value = unquote(expression)
        if value do
          throw {:break, value}
        else
          elapsed_time = Helpers._now() - start_time
          remaining_time = unquote(timeout) - elapsed_time
          case ConditionVariable.wait(local_name, timeout: remaining_time) do
            :ok -> :loop
            :timeout -> throw {:timeout, unquote(timeout)}
          end
        end
      end
    end
  end

  defmacro polling_wait(expression, frequency, timeout) do
    quote do
      waiter = Helpers._start_waiter(self(), unquote(timeout))

      result = Helpers._loop(true) do
        value = unquote(expression)
        if value do
          throw {:break, value}
        else
          receive do
            {^waiter, timeout} -> throw {:timeout, timeout}
          after
            unquote(frequency) -> :loop
          end
        end
      end

      Process.exit(waiter, :normal)
      result
    end
  end

  defmacro condition_var_case_wait(expression, condition_var, timeout, block) do
    quote do
      local_name = Helpers._localized_name(unquote(condition_var))
      Helpers._init_condition_var(local_name)
      start_time = Helpers._now()
      end_time = start_time + unquote(timeout)

      Helpers._loop do
        value = unquote(expression)
        try do
          result = case value do
            unquote(block)
          end
          throw {:break, result}
        rescue
          CaseClauseError ->
            elapsed_time = Helpers._now() - start_time
            remaining_time = unquote(timeout) - elapsed_time
            case ConditionVariable.wait(local_name, timeout: remaining_time) do
              :ok -> :loop
              :timeout -> throw {:timeout, unquote(timeout)}
            end
        end
      end
    end
  end

  defmacro polling_case_wait(expression, frequency, timeout, block) do
    quote do
      waiter = Helpers._start_waiter(self(), unquote(timeout))

      result = Helpers._loop do
        value = unquote(expression)
        try do
          result = case value do
            unquote(block)
          end
          throw {:break, result}
        rescue
          CaseClauseError ->
            receive do
              {^waiter, timeout} -> throw {:timeout, timeout}
            after
              unquote(frequency) -> :loop
            end
        end
      end

      Process.exit(waiter, :normal)
      result
    end
  end

  defmacro condition_var_cond_wait(condition_var, timeout, block) do
    quote do
      local_name = Helpers._localized_name(unquote(condition_var))
      Helpers._init_condition_var(local_name)
      start_time = Helpers._now()
      end_time = start_time + unquote(timeout)

      Helpers._loop do
        try do
          result = cond do
            unquote(block)
          end
          throw {:break, result}
        rescue
          CondClauseError ->
            elapsed_time = Helpers._now() - start_time
            remaining_time = unquote(timeout) - elapsed_time
            case ConditionVariable.wait(local_name, timeout: remaining_time) do
              :ok -> :loop
              :timeout -> throw {:timeout, unquote(timeout)}
            end
        end
      end
    end
  end

  defmacro polling_cond_wait(frequency, timeout, block) do
    quote do
      waiter = Helpers._start_waiter(self(), unquote(timeout))

      result = Helpers._loop do
        try do
          result = cond do
            unquote(block)
          end
          throw {:break, result}
        rescue
          CondClauseError ->
            receive do
              {^waiter, timeout} -> throw {:timeout, timeout}
            after
              unquote(frequency) -> :loop
            end
        end
      end

      Process.exit(waiter, :normal)
      result
    end
  end

  defmacro condition_var_signal(condition_var) do
    quote do
      local_name = Helpers._localized_name(unquote(condition_var))
      Helpers._init_condition_var(local_name)
      ConditionVariable.signal(local_name)
    end
  end

  defmacro _loop(wrap_return_value \\ false, do: do_block) do
    quote do
      try do
        for _ <- Stream.cycle([:ok]) do
          unquote(do_block)
        end
      catch
        {:break, value} ->
          if unquote(wrap_return_value), do: {:ok, value}, else: value
        {:timeout, timeout} -> {:timeout, timeout}
      end
    end
  end

  def _init_condition_var(var) do
    :ok = ConditionVariable.start_link(var)
  end

  def _start_waiter(waiting_pid, timeout) do
    {:ok, waiter} = Task.start fn ->
      receive do
      after
        timeout -> send(waiting_pid, {self(), timeout})
      end
    end
    waiter
  end

  defmacro _now do
    quote do
      DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    end
  end

  defmacro _localized_name(name) do
    quote do
      :"#{__MODULE__}.#{unquote(name)}"
    end
  end
end
