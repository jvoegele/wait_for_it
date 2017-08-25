defmodule WaitForIt.ConditionVariableTest do
  use ExUnit.Case
  alias WaitForIt.ConditionVariable

  test "wait blocks until signal received" do
    :ok = ConditionVariable.start_link(:cond_wait)
    Task.async fn -> for _ <- 1..10, do: ConditionVariable.signal(:cond_wait) end
    :ok = ConditionVariable.wait(:cond_wait)
  end

  test "wait times out if no signal received" do
    :ok = ConditionVariable.start_link(:cond_wait)
    :timeout = ConditionVariable.wait(:cond_wait, timeout: 10)
  end
end
