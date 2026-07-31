defmodule WaitForIt.UntilTest do
  use ExUnit.Case, async: true

  defp counter do
    n = (Process.get(:counter) || 0) + 1
    Process.put(:counter, n)
    n
  end

  describe "until/2" do
    test "returns {:ok, value} with the truthy value that ended the wait" do
      assert {:ok, 3} = WaitForIt.until(fn -> if counter() >= 3, do: 3 end, interval: 1)
      assert Process.get(:counter) == 3
    end

    test "returns {:timeout, last_value} on timeout, carrying the last falsy value" do
      assert {:timeout, false} =
               WaitForIt.until(fn -> false end, timeout: 5, interval: 1)

      assert {:timeout, nil} =
               WaitForIt.until(fn -> nil end, timeout: 5, interval: 1)
    end

    test "distinguishes a matched value structurally, even when it is a {:timeout, _} tuple" do
      # A matched value may be any term, including one shaped like the timeout result. The outcome
      # must be decided by whether the wait matched, not by inspecting the value.
      assert {:ok, {:timeout, :matched}} =
               WaitForIt.until(fn -> {:timeout, :matched} end, timeout: 5, interval: 1)
    end

    test "honors :pre_wait before the first evaluation" do
      assert {:ok, 1} = WaitForIt.until(fn -> 1 end, pre_wait: 5)
    end

    test "accepts timeout: :infinity and returns {:ok, value}" do
      assert {:ok, 30} =
               WaitForIt.until(fn -> if counter() >= 30, do: 30 end,
                 timeout: :infinity,
                 interval: 1
               )

      assert Process.get(:counter) == 30
    end

    test "raises when given something other than a zero-arity function" do
      # `apply/3` keeps the deliberately-wrong arity opaque to the compile-time type checker.
      assert_raise FunctionClauseError, fn ->
        apply(WaitForIt, :until, [fn _x -> true end])
      end
    end
  end

  describe "until!/2" do
    test "returns the bare truthy value on success" do
      assert 42 == WaitForIt.until!(fn -> 42 end, interval: 1)
    end

    test "raises WaitForIt.TimeoutError on timeout" do
      error =
        assert_raise WaitForIt.TimeoutError, fn ->
          WaitForIt.until!(fn -> false end, timeout: 5, interval: 1)
        end

      assert error.message =~ "until"
    end
  end
end
