defmodule WaitForIt.Test do
  @moduledoc ~S"""
  Assertions for waiting on asynchronous and concurrent activity in ExUnit tests.

  These macros build on the WaitForIt waiting machinery but, instead of returning a falsy value
  or raising a `WaitForIt.TimeoutError` on timeout, they fail the test with a regular
  `ExUnit.AssertionError` — so failures read like any other ExUnit failure, complete with the
  source expression and the last value that was seen before giving up.

  ## Usage

  Bring the assertions into your test module with either `import` or `use`:

      defmodule MyApp.SomeTest do
        use ExUnit.Case
        use WaitForIt.Test
      end

  ## Available assertions

    * `assert_eventually/2` - wait until an expression becomes truthy (or matches a pattern).
    * `refute_eventually/2` - assert that an expression never becomes truthy within the window.
    * `assert_always/2` - assert that an expression stays truthy for the whole window.

  All of them accept the same options as the other WaitForIt macros (`:timeout`, `:interval`,
  `:pre_wait`, `:signal`); see the `WaitForIt` module documentation. The defaults are tuned for
  tests and differ per assertion (noted on each).
  """

  @doc """
  Convenience: `use WaitForIt.Test` is equivalent to `import WaitForIt.Test`.
  """
  defmacro __using__(_opts) do
    quote do
      import WaitForIt.Test
    end
  end

  @doc ~S"""
  Asserts that the given `expression` *eventually* succeeds, waiting and re-evaluating until it
  does or the timeout elapses.

  Two forms are supported:

    * a plain expression, which must eventually evaluate to a truthy value, and
    * a match expression of the form `pattern = expression`, which waits until the right-hand
      side matches `pattern` and then binds the pattern's variables into the surrounding scope,
      exactly like `assert pattern = expression`.

  Returns the value that ended the wait. On timeout, fails with an `ExUnit.AssertionError` that
  includes the source expression and the last value that was evaluated.

  Defaults to `timeout: 1_000` and `interval: 10`.

  ## Examples

      # Truthy form:
      assert_eventually Repo.get(User, id).confirmed

      # Match form (binds `user` for later use):
      assert_eventually {:ok, user} = fetch_user(id), timeout: 2_000
      assert user.name == "Elijah"
  """
  defmacro assert_eventually(expression, opts \\ [])

  defmacro assert_eventually({:=, _, [pattern, rhs]} = expression, opts) do
    # The pattern's variables are bound from the *final* match below, not from the waiting test,
    # so feed `match_wait!` a binding-free copy (variables replaced with `_`, pins preserved) to
    # avoid spurious "unused variable" warnings at the call site.
    test_pattern = WaitForIt.Evaluation.ignore_pattern_bindings(pattern)

    quote do
      require WaitForIt

      value =
        try do
          WaitForIt.match_wait!(
            unquote(test_pattern),
            unquote(rhs),
            WaitForIt.Test.__opts__(unquote(opts), 1_000, 10)
          )
        rescue
          error in WaitForIt.TimeoutError ->
            WaitForIt.Test.__assert_timeout__(unquote(Macro.escape(expression)), error, :match)
        end

      unquote(pattern) = value
    end
  end

  defmacro assert_eventually(expression, opts) do
    quote do
      require WaitForIt

      try do
        WaitForIt.wait!(unquote(expression), WaitForIt.Test.__opts__(unquote(opts), 1_000, 10))
      rescue
        error in WaitForIt.TimeoutError ->
          WaitForIt.Test.__assert_timeout__(unquote(Macro.escape(expression)), error, :truthy)
      end
    end
  end

  @doc ~S"""
  Asserts that the given `expression` *never* becomes truthy within the wait window.

  Re-evaluates the expression until it becomes truthy (a failure) or the timeout elapses (a
  success). Because confirming the negative requires waiting out the whole window, this assertion
  always waits up to its timeout when it passes; keep the timeout short.

  Defaults to `timeout: 100` and `interval: 10`.

  ## Examples

      refute_eventually error_reported?()
  """
  defmacro refute_eventually(expression, opts \\ []) do
    quote do
      require WaitForIt

      outcome =
        try do
          {:became_truthy,
           WaitForIt.wait!(unquote(expression), WaitForIt.Test.__opts__(unquote(opts), 100, 10))}
        rescue
          WaitForIt.TimeoutError -> :stayed_falsy
        end

      case outcome do
        :stayed_falsy ->
          false

        {:became_truthy, value} ->
          WaitForIt.Test.__refute_failure__(unquote(Macro.escape(expression)), value)
      end
    end
  end

  @doc ~S"""
  Asserts that the given `expression` stays truthy for the entire wait window.

  Re-evaluates the expression until it becomes falsy (a failure) or the timeout elapses (a
  success). Because waiting is poll-based, a brief falsy blip *between* evaluations may be missed;
  tune `:interval` to sample as often as you need.

  Defaults to `timeout: 100` and `interval: 10`.

  ## Examples

      assert_always circuit_closed?(), timeout: 500
  """
  defmacro assert_always(expression, opts \\ []) do
    quote do
      require WaitForIt

      outcome =
        try do
          {:became_falsy,
           WaitForIt.match_wait!(
             falsy when falsy in [false, nil],
             unquote(expression),
             WaitForIt.Test.__opts__(unquote(opts), 100, 10)
           )}
        rescue
          WaitForIt.TimeoutError -> :stayed_truthy
        end

      case outcome do
        :stayed_truthy ->
          true

        {:became_falsy, value} ->
          WaitForIt.Test.__always_failure__(unquote(Macro.escape(expression)), value)
      end
    end
  end

  @doc false
  def __opts__(opts, default_timeout, default_interval) do
    opts = Keyword.put_new(opts, :timeout, default_timeout)

    if Keyword.has_key?(opts, :interval) or Keyword.has_key?(opts, :frequency) do
      opts
    else
      Keyword.put(opts, :interval, default_interval)
    end
  end

  @doc false
  @spec __assert_timeout__(Macro.t(), WaitForIt.TimeoutError.t(), :truthy | :match) :: no_return()
  def __assert_timeout__(expression, %WaitForIt.TimeoutError{} = error, kind) do
    description =
      case kind do
        :truthy -> "be truthy"
        :match -> "match the pattern"
      end

    raise ExUnit.AssertionError,
      message:
        "Expected expression to eventually #{description}, but it timed out after " <>
          "#{error.timeout}ms.\n\nlast value: #{inspect(error.last_value)}",
      expr: expression
  end

  @doc false
  @spec __refute_failure__(Macro.t(), term()) :: no_return()
  def __refute_failure__(expression, value) do
    raise ExUnit.AssertionError,
      message:
        "Expected expression to never become truthy within the wait, but it did.\n\n" <>
          "value: #{inspect(value)}",
      expr: expression
  end

  @doc false
  @spec __always_failure__(Macro.t(), term()) :: no_return()
  def __always_failure__(expression, value) do
    raise ExUnit.AssertionError,
      message:
        "Expected expression to remain truthy for the entire wait, but it became falsy.\n\n" <>
          "value: #{inspect(value)}",
      expr: expression
  end
end
