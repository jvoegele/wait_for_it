defmodule WaitForIt.BackoffTest do
  use ExUnit.Case, async: true

  doctest WaitForIt.Backoff

  alias WaitForIt.Backoff

  describe "constant/1" do
    test "always returns the same value" do
      f = Backoff.constant(42)
      assert Enum.map(1..5, f) == [42, 42, 42, 42, 42]
    end
  end

  describe "exponential/1" do
    test "grows exponentially and caps at :max" do
      f = Backoff.exponential(start: 10, factor: 3, max: 500)
      assert Enum.map(1..5, f) == [10, 30, 90, 270, 500]
    end

    test "uses documented defaults (start: 50, factor: 2, max: 2000)" do
      f = Backoff.exponential()
      assert Enum.map(1..7, f) == [50, 100, 200, 400, 800, 1600, 2000]
    end

    test "jitter keeps values within +/- the configured fraction" do
      f = Backoff.exponential(start: 1000, factor: 1, max: 1000, jitter: 0.1)

      for _ <- 1..1000 do
        value = f.(1)
        assert value >= 900 and value <= 1100
      end
    end

    test "jitter never produces a negative delay" do
      f = Backoff.exponential(start: 0, jitter: 0.5)
      assert f.(1) == 0
    end
  end
end
