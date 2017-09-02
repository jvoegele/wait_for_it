defmodule WaitForIt.ConditionVariable.SupervisorTest do
  use ExUnit.Case
  alias WaitForIt.ConditionVariable

  describe "create_condition_variable/0" do
    test "starts a new child process and returns {:ok, pid}" do
      {:ok, pid} = ConditionVariable.Supervisor.create_condition_variable()
      assert is_pid(pid)
    end
  end

  describe "named_condition_variable/1" do
    test "registers new process" do
      {:ok, pid} = ConditionVariable.Supervisor.named_condition_variable(:new_condition_var)
      assert [{pid, nil}] == Registry.lookup(ConditionVariable.registry(), :new_condition_var)
    end

    test "returns {:ok, pid} with existing pid if already registered" do
      {:ok, pid} = ConditionVariable.Supervisor.named_condition_variable(:condition_var)
      assert {:ok, ^pid} = ConditionVariable.Supervisor.named_condition_variable(:condition_var)
    end
  end
end
