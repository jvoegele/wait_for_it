defmodule WaitForIt.V1.ConditionVariableTest do
  use ExUnit.Case
  alias WaitForIt.V1.ConditionVariable

  @moduletag :legacy

  describe "start_link/0" do
    test "starts a new process and returns {:ok, pid}" do
      {:ok, pid} = ConditionVariable.start_link()
      assert is_pid(pid)
    end
  end

  describe "start_link/1" do
    test "registers new process" do
      {:ok, pid} = ConditionVariable.start_link(name: :new_condition_var)
      assert [{pid, nil}] == Registry.lookup(ConditionVariable.registry(), :new_condition_var)
    end

    test "returns {:error, {:already_started, pid}} if already registered" do
      {:ok, pid} = ConditionVariable.start_link(name: :condition_var)
      assert {:error, {:already_started, ^pid}} = ConditionVariable.start_link(name: :condition_var)
    end
  end

  test "wait blocks until signal received" do
    {:ok, _pid} = ConditionVariable.start_link(name: :cond_wait)
    Task.async(fn -> for _ <- 1..10, do: ConditionVariable.signal(:cond_wait) end)
    :ok = ConditionVariable.wait(:cond_wait)
  end

  test "wait times out if no signal received" do
    {:ok, _pid} = ConditionVariable.start_link(name: :cond_wait)
    :timeout = ConditionVariable.wait(:cond_wait, timeout: 10)
  end

  test "self destructs after idle timeout" do
    idle_timeout = 10
    {:ok, pid} = ConditionVariable.start_link(idle_timeout: idle_timeout)
    assert Process.alive?(pid)
    Process.sleep(idle_timeout + 1)
    assert Process.alive?(pid)
    ConditionVariable.signal(pid)
    Process.sleep(idle_timeout + 1)
    refute Process.alive?(pid)
  end
end
