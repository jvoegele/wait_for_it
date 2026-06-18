defmodule WaitForIt.WithWaitTest do
  use ExUnit.Case

  import WaitForIt

  # Process-local counter incremented on each call, to drive expressions that change over time.
  defp bump do
    n = (Process.get(:bump) || 0) + 1
    Process.put(:bump, n)
    n
  end

  # Wrappers that return values the compiler cannot constant-fold, so static match/guard warnings
  # are not emitted for the waiting tests.
  defp ok(value), do: {:ok, value}
  defp err(reason), do: {:error, reason}
  defp pending, do: :pending

  # Returns {:ok, n} once the counter reaches `threshold`, otherwise :pending.
  defp ready_at(threshold) do
    case bump() do
      n when n >= threshold -> {:ok, n}
      _ -> :pending
    end
  end

  describe "with_wait/3 success" do
    test "binds and returns the do block value when all clauses match" do
      result =
        with_wait on(
                    {:ok, a} <- ok(1),
                    {:ok, b} <~ ok(2)
                  ) do
          {a, b}
        end

      assert result == {1, 2}
    end

    test "a <~ clause waits until its expression matches" do
      result =
        with_wait on({:ok, n} <~ ready_at(3)), interval: 1 do
          n
        end

      assert result == 3
    end

    test "later clauses can use variables bound by earlier clauses" do
      result =
        with_wait on(
                    {:ok, x} <~ ok(10),
                    {:ok, y} <~ ok(x + 5)
                  ) do
          y
        end

      assert result == 15
    end
  end

  describe "with_wait/3 options" do
    test "per-clause options override the global options" do
      # Global timeout is effectively infinite; the per-clause timeout is what fires.
      result =
        with_wait on({:ok, _v} <~ {pending(), timeout: 20, interval: 1}), timeout: 60_000 do
          :matched
        else
          other -> {:timed_out, other}
        end

      assert result == {:timed_out, :pending}
    end
  end

  describe "with_wait/3 timeout and non-match" do
    test "a <~ timeout routes the last value to else" do
      result =
        with_wait on({:ok, _v} <~ pending()), timeout: 20, interval: 1 do
          :matched
        else
          other -> {:else, other}
        end

      assert result == {:else, :pending}
    end

    test "a <~ timeout returns the last value when there is no else" do
      result =
        with_wait on({:ok, _v} <~ pending()), timeout: 20, interval: 1 do
          :matched
        end

      assert result == :pending
    end

    test "an ordinary <- non-match routes to else" do
      result =
        with_wait on({:ok, x} <- err(:nope)) do
          x
        else
          {:error, reason} -> {:got_error, reason}
        end

      assert result == {:got_error, :nope}
    end
  end

  describe "with_wait/3 guards (parenthesized)" do
    test "waits until the guarded pattern matches" do
      result =
        with_wait on(({:ok, n} when n > 5) <~ ok(bump())), interval: 1 do
          n
        end

      assert result == 6
    end

    test "a guard failure on timeout routes to else" do
      result =
        with_wait on(({:ok, n} when n > 100) <~ ok(bump())), timeout: 20, interval: 1 do
          n
        else
          {:ok, n} -> {:too_small, n}
        end

      assert {:too_small, n} = result
      assert n < 100
    end
  end

  describe "with_wait!/3" do
    test "raises WaitForIt.TimeoutError when a <~ clause times out" do
      assert_raise WaitForIt.TimeoutError, fn ->
        with_wait! on({:ok, _v} <~ pending()), timeout: 20, interval: 1 do
          :matched
        end
      end
    end

    test "still routes an ordinary <- non-match to else without raising" do
      result =
        with_wait! on({:ok, x} <- err(:nope)) do
          x
        else
          {:error, reason} -> {:handled, reason}
        end

      assert result == {:handled, :nope}
    end
  end

  describe "with_wait/3 signaling" do
    test "a <~ clause supports a per-clause :signal" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      Task.start_link(fn ->
        Process.sleep(5)
        Agent.update(agent, fn _ -> 100 end)
        WaitForIt.signal(:with_wait_signal)
      end)

      result =
        with_wait on({:ok, n} <~ {tagged(agent), signal: :with_wait_signal}) do
          n
        end

      assert result == 100
    end
  end

  describe "with_wait/3 errors" do
    test "raises a helpful error when clauses are not wrapped in on(...)" do
      assert_raise ArgumentError, ~r/on\(/, fn ->
        Code.eval_string("import WaitForIt; with_wait foo do :x end")
      end
    end
  end

  defp tagged(agent) do
    case Agent.get(agent, & &1) do
      n when n >= 100 -> {:ok, n}
      _ -> :pending
    end
  end
end
