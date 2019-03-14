defmodule WaitForItTest do
  use ExUnit.Case
  use ExUnitProperties
  import WaitForIt

  defp increment_counter do
    counter = (Process.get(:counter) || 0) + 1
    Process.put(:counter, counter)
    counter
  end

  defp init_counter(initial) do
    Agent.start_link(fn -> initial end)
  end

  defp get_counter(counter_pid) do
    Agent.get(counter_pid, & &1)
  end

  defp increment_counter(counter_pid) do
    try do
      Agent.update(counter_pid, fn n -> n + 1 end)
    catch
      :exit, _ -> nil
    end
  end

  defp increment_task(counter_pid, opts) do
    sleep_time = Keyword.get(opts, :sleep_time, 0)
    max = Keyword.get(opts, :max, 1_000_000)
    condition_var = Keyword.get(opts, :signal)

    Task.start_link(fn ->
      for _ <- 1..max do
        increment_counter(counter_pid)
        if condition_var, do: signal(condition_var)
        Process.sleep(sleep_time)
      end
    end)
  end

  describe "wait/2" do
    test "waits for expression to be truthy" do
      {:ok, true} = wait(increment_counter() > 2)
      assert 3 == Process.get(:counter)
    end

    test "accepts a :frequency option" do
      wait(increment_counter() > 4, frequency: 1, pre_wait: 1)
      assert 5 == Process.get(:counter)
    end

    test "accepts a :timeout option" do
      timeout = 10
      {:timeout, ^timeout} = wait(increment_counter() > timeout, timeout: timeout, frequency: 1)
      assert Process.get(:counter) < timeout
    end

    test "accepts a :signal option" do
      {:ok, counter} = init_counter(0)
      _task = increment_task(counter, max: 1000, signal: :counter_wait)
      assert {:ok, true} == wait(get_counter(counter) > 99, signal: :counter_wait)
      assert get_counter(counter) > 99
    end

    test "times out if signal not received" do
      {:ok, counter} = init_counter(0)
      assert {:timeout, 10} == wait(get_counter(counter) > 99, signal: :counter_wait, timeout: 10)
    end
  end

  describe "case_wait/2" do
    test "waits for expression to match one of the given patterns" do
      {:ok, counter} = init_counter(0)
      _task = increment_task(counter, sleep_time: 1)

      result =
        case_wait get_counter(counter) do
          value when value >= 10 -> value
        end

      assert result >= 10
    end

    test "accepts a :frequency option" do
      case_wait increment_counter(), frequency: 1, pre_wait: 1 do
        5 -> 5
      end

      assert 5 == Process.get(:counter)
    end

    test "accepts a :timeout option" do
      timeout = 10

      {:timeout, ^timeout} =
        case_wait increment_counter(), timeout: timeout, frequency: 1 do
          11 -> 11
        end

      assert Process.get(:counter) < timeout
    end

    test "accepts a :signal option" do
      {:ok, counter} = init_counter(0)
      _task = increment_task(counter, max: 1000, signal: :counter_wait)

      count =
        case_wait get_counter(counter), signal: :counter_wait do
          value when value > 99 -> value
        end

      assert count > 99
      assert get_counter(counter) >= count
    end

    property "times out if signal not received" do
      check all timeout <- integer(5..50) do
        {:ok, counter} = init_counter(0)

        result =
          case_wait get_counter(counter), signal: :counter_wait, timeout: timeout do
            100 -> 100
          end

        assert result == {:timeout, timeout}
      end
    end

    test "accepts an else block" do
      {:ok, counter} = init_counter(0)

      result =
        case_wait get_counter(counter), signal: :counter_wait, timeout: 10 do
          100 -> 100
        else
          {:timeout, :else_clause}
        end

      assert result == {:timeout, :else_clause}
    end

    test "accepts an else block with case clauses" do
      result =
        case_wait increment_counter(), frequency: 5, timeout: 10 do
          100 -> 100
        else
          :foo -> :will_never_reach_here
          n when is_integer(n) -> {:else, n}
          :bar -> :will_never_reach_here
        end

      assert {:else, count} = result
      assert count < 10
    end
  end

  describe "cond_wait/1" do
    test "waits for one of the given expressions to be truthy" do
      :ok =
        cond_wait do
          2 + 2 == 5 -> 1984
          :answer == 42 -> :question
          increment_counter() == 3 -> :ok
        end

      assert 3 == Process.get(:counter)
    end

    test "accepts a :frequency option" do
      5 =
        cond_wait frequency: 1, pre_wait: 1 do
          (
            count = increment_counter()
            count > 4
          ) ->
            count

          2 + 2 == 5 ->
            1984

          :answer == 42 ->
            :question
        end

      assert 5 == Process.get(:counter)
    end

    test "accepts a :timeout option" do
      timeout = 10

      {:timeout, ^timeout} =
        cond_wait timeout: timeout, frequency: 1 do
          11 == increment_counter() -> :ok
        end

      assert Process.get(:counter) < timeout
    end

    test "accepts a :signal option" do
      {:ok, counter} = init_counter(0)
      _task = increment_task(counter, max: 1000, signal: :counter_wait)

      result =
        cond_wait signal: :counter_wait do
          get_counter(counter) > 99 -> :century
        end

      assert result == :century
      assert get_counter(counter) > 99
    end

    test "times out if signal not received" do
      {:ok, counter} = init_counter(0)
      timeout = 10

      result =
        cond_wait signal: :counter_wait, timeout: 10 do
          get_counter(counter) > 99 -> :will_never_get_here
        end

      assert result == {:timeout, timeout}
    end

    test "accepts an else block" do
      {:ok, _counter} = init_counter(0)

      result =
        cond_wait signal: :counter_wait, timeout: 10 do
          :answer == 42 -> true
        else
          {:timeout, :else_clause}
        end

      assert result == {:timeout, :else_clause}
    end
  end

  describe "multiple waiters using :signal option" do
    property "all wait until they receive the signal" do
      check all factor <- integer(1..10),
                waiter_count <- integer(1..20) do
        {:ok, counter} = init_counter(0)

        tasks =
          for i <- 1..waiter_count do
            Task.async(fn ->
              case_wait get_counter(counter), signal: :counter_wait do
                n when n > i * factor ->
                  {:ok, n}
              else
                {:error, get_counter(counter)}
              end
            end)
          end

        _task = increment_task(counter, signal: :counter_wait)

        for task <- tasks do
          assert {:ok, _} = Task.await(task)
        end
      end
    end

    property "death of waiting process does not affect other waiters" do
      check all waiter_count <- integer(3..50),
                kill_count <- integer(0..3),
                kill_reason <- member_of([:normal, :kill, :shutdown, :die]),
                kill_count <= waiter_count do
        {:ok, counter} = init_counter(0)

        {:ok, task_supervisor} = Task.Supervisor.start_link()

        tasks =
          for i <- 1..waiter_count do
            Task.Supervisor.async_nolink(task_supervisor, fn ->
              case_wait get_counter(counter), signal: :counter_wait do
                n when n > i * 3 ->
                  {:ok, n}
              else
                {:error, get_counter(counter)}
              end
            end)
          end

        tasks
        |> Enum.take_random(kill_count)
        |> Enum.each(fn task -> Process.exit(task.pid, kill_reason) end)

        _task = increment_task(counter, signal: :counter_wait)

        completed_tasks =
          tasks
          |> Enum.map(&Task.yield(&1, 500))
          |> Enum.filter(&filter_ok/1)

        expected_completed_count =
          if kill_reason == :normal, do: waiter_count, else: waiter_count - kill_count

        assert length(completed_tasks) == expected_completed_count
      end
    end

    defp filter_ok({:ok, _}), do: true
    defp filter_ok(_), do: false
  end
end
