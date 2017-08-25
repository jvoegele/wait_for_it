defmodule WaitForIt.Helpers do
  alias __MODULE__
  alias WaitForIt.ConditionVariable

  defmacro condition_var_wait(expression, condition_var, timeout) do
    quote do
      local_name = Helpers.localized_name(unquote(condition_var))
      _ = Helpers.init_condition_var(local_name)
      try do
        start_time = Helpers.now()
        end_time = start_time + unquote(timeout)
        for _ <- Stream.cycle([:ok]) do
          value = unquote(expression)
          if value do
            throw {:break, value}
          else
            elapsed_time = Helpers.now() - start_time
            remaining_time = unquote(timeout) - elapsed_time
            case ConditionVariable.wait(local_name, timeout: remaining_time) do
              :ok -> :loop
              :timeout -> throw {:timeout, unquote(timeout)}
            end
          end
        end
      catch
        {:break, value} -> {:ok, value}
        {:timeout, timeout} -> {:timeout, timeout}
      end
    end
  end

  defmacro polling_wait(expression, frequency, timeout) do
    quote do
      waiter = Helpers.start_waiter(self(), unquote(timeout))

      result = try do
        for _ <- Stream.cycle([:ok]) do
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
      catch
        {:break, value} -> {:ok, value}
        {:timeout, timeout} -> {:timeout, timeout}
      end

      Process.exit(waiter, :normal)
      result
    end
  end

  defmacro condition_var_signal(condition_var) do
    quote do
      local_name = Helpers.localized_name(unquote(condition_var))
      Helpers.init_condition_var(local_name)
      ConditionVariable.signal(local_name)
    end
  end

  def init_condition_var(var) do
    :ok = ConditionVariable.start_link(var)
  end

  def start_waiter(waiting_pid, timeout) do
    {:ok, waiter} = Task.start fn ->
      receive do
      after
        timeout -> send(waiting_pid, {self(), timeout})
      end
    end
    waiter
  end

  defmacro now do
    quote do
      DateTime.utc_now() |> DateTime.to_unix(:millisecond)
    end
  end

  defmacro localized_name(name) do
    quote do
      :"#{__MODULE__}.#{unquote(name)}"
    end
  end
end
