defmodule WaitForItTest do
  use ExUnit.Case
  doctest WaitForIt

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
    Agent.get(counter_pid, &(&1))
  end

  defp increment_counter(counter_pid) do
    Agent.update(counter_pid, fn(n) -> n + 1 end)
  end

  describe "wait/2" do
    test "waits for expression to be truthy" do
      {:ok, true} = wait increment_counter() > 2
      assert 3 == Process.get(:counter)
    end

    test "accepts a :frequency option" do
      wait increment_counter() > 4, frequency: 1
      assert 5 == Process.get(:counter)
    end

    test "accepts a :timeout option" do
      timeout = 10
      {:timeout, ^timeout} = wait increment_counter() > timeout, timeout: timeout, frequency: 1
      assert Process.get(:counter) < timeout
    end

    test "accepts a :signal option" do
      {:ok, counter} = init_counter(0)
      {:ok, _task} = Task.start_link(fn ->
        Enum.each(1..1000, fn(_) ->
          increment_counter(counter)
          signal(:counter_wait)
        end)
      end)
      assert {:ok, true} == wait get_counter(counter) > 99, signal: :counter_wait
      assert get_counter(counter) > 99
    end

    test "times out if signal not received" do
      {:ok, counter} = init_counter(0)
      assert {:timeout, 10} == wait get_counter(counter) > 99, signal: :counter_wait, timeout: 10
    end
  end

  describe "case_wait/2" do
  end

  describe "cond_wait/1" do
  end
end
