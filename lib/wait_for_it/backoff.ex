defmodule WaitForIt.Backoff do
  @moduledoc """
  Backoff strategies for the `:interval` option of the waiting macros.

  By default, WaitForIt polls at a constant interval. When waiting on an external or struggling
  dependency, it is often better to back off — to poll less frequently as time goes on — so that
  the dependency is not hammered. The `:interval` option accepts either a constant number of
  milliseconds or a 1-arity function that receives the attempt number (starting at `1`) and
  returns the number of milliseconds to wait before the next evaluation. The functions in this
  module build such interval functions.

  The configured timeout still bounds the total wait: the actual sleep before each evaluation is
  the smaller of the backoff value and the time remaining before the deadline.

  ## Examples

      import WaitForIt

      # Exponential backoff starting at 50ms, doubling each attempt, capped at 1s, with jitter.
      wait(Repo.get(Post, id),
        timeout: :timer.seconds(30),
        interval: WaitForIt.Backoff.exponential(start: 50, max: 1_000, jitter: 0.1))
  """

  @typedoc """
  A function that maps an attempt number (starting at `1`) to a delay in milliseconds.
  """
  @type interval_fun :: (pos_integer() -> non_neg_integer())

  @doc """
  Returns an interval function that always waits the same number of `milliseconds`.

  This is equivalent to passing the integer directly as the `:interval` option, and exists for
  symmetry and readability.
  """
  @spec constant(non_neg_integer()) :: interval_fun()
  def constant(milliseconds) when is_integer(milliseconds) and milliseconds >= 0 do
    fn _attempt -> milliseconds end
  end

  @doc """
  Returns an interval function implementing exponential backoff.

  The delay for a given attempt is `start * factor ^ (attempt - 1)`, capped at `max`, with
  optional random jitter applied.

  ## Options

    * `:start` - the delay (in milliseconds) for the first attempt (default: `50`)
    * `:max` - the maximum delay (in milliseconds); delays are capped at this value (default: `2_000`)
    * `:factor` - the multiplier applied for each successive attempt (default: `2`)
    * `:jitter` - a fraction in the range `0.0..1.0` controlling random jitter; a value of `0.1`
      varies each delay by up to ±10% (default: `0.0`, i.e. no jitter)

  ## Examples

      iex> backoff = WaitForIt.Backoff.exponential(start: 100, factor: 2, max: 1000)
      iex> Enum.map(1..5, backoff)
      [100, 200, 400, 800, 1000]
  """
  @spec exponential(keyword()) :: interval_fun()
  def exponential(opts \\ []) do
    start = Keyword.get(opts, :start, 50)
    max = Keyword.get(opts, :max, 2_000)
    factor = Keyword.get(opts, :factor, 2)
    jitter = Keyword.get(opts, :jitter, 0.0)

    fn attempt when is_integer(attempt) and attempt >= 1 ->
      base = min(max, round(start * :math.pow(factor, attempt - 1)))
      apply_jitter(base, jitter)
    end
  end

  defp apply_jitter(base, jitter) when jitter <= 0.0, do: base

  defp apply_jitter(base, jitter) do
    delta = base * jitter
    max(0, round(base - delta + :rand.uniform() * 2 * delta))
  end
end
