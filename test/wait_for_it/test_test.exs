defmodule WaitForIt.TestTest do
  use ExUnit.Case
  use WaitForIt.Test

  # A process-local counter that increments by one on every call, used to drive expressions
  # whose value changes on each (re-)evaluation.
  defp bump do
    n = (Process.get(:bump) || 0) + 1
    Process.put(:bump, n)
    n
  end

  defp tagged_bump do
    case bump() do
      n when n >= 3 -> {:ok, n}
      _ -> :pending
    end
  end

  # Returns a value the compiler cannot constant-fold, so match/guard checks against it are not
  # flagged as statically determinable.
  defp never, do: :never

  describe "assert_eventually/2 (truthy form)" do
    test "passes once the expression becomes truthy" do
      assert assert_eventually(bump() >= 3, interval: 1) == true
      assert Process.get(:bump) == 3
    end

    test "fails with an ExUnit.AssertionError on timeout" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_eventually(bump() > 1_000, timeout: 20, interval: 1)
        end

      assert error.message =~ "eventually be truthy"
      assert error.message =~ "last value:"
    end
  end

  describe "assert_eventually/2 (match form)" do
    test "waits until the expression matches and binds pattern variables" do
      assert_eventually({:ok, n} = tagged_bump(), interval: 1)
      assert n == 3
    end

    test "fails with an ExUnit.AssertionError on timeout" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_eventually({:ok, _n} = never(), timeout: 20, interval: 1)
        end

      assert error.message =~ "match the pattern"
      assert error.message =~ "last value: :never"
    end
  end

  describe "refute_eventually/2" do
    test "passes when the expression never becomes truthy" do
      assert refute_eventually(bump() > 1_000, timeout: 20, interval: 1) == false
    end

    test "fails when the expression becomes truthy" do
      assert_raise ExUnit.AssertionError, fn ->
        refute_eventually(bump() >= 2, timeout: 100, interval: 1)
      end
    end
  end

  describe "assert_always/2" do
    test "passes when the expression stays truthy for the window" do
      assert assert_always(bump() > 0, timeout: 20, interval: 1) == true
    end

    test "fails when the expression becomes falsy" do
      error =
        assert_raise ExUnit.AssertionError, fn ->
          assert_always(bump() < 2, timeout: 100, interval: 1)
        end

      assert error.message =~ "became falsy"
    end
  end
end
