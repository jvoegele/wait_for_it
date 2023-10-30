defmodule WaitForIt.V1 do
  @moduledoc deprecated:
               "This is a legacy module for backward compatibility only; new code should use the main WaitForIt module instead"

  @doc ~S"""
  Wait until the given `expression` evaluates to a truthy value.

  Returns `{:ok, value}` or `{:timeout, timeout_milliseconds}`.

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
    * `:signal` - disable polling and use a condition variable of the given name instead
    * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time

  ## Examples

    Wait until the top of the hour:

      WaitForIt.wait Time.utc_now.minute == 0, frequency: 60_000, timeout: 60_000 * 60

    Wait up to one minute for a particular record to appear in the database:

      case WaitForIt.wait Repo.get(Post, 42), frequency: 1000, timeout: 60_000 do
        {:ok, data} -> IO.inspect(data)
        {:timeout, timeout} -> IO.puts("Gave up after #{timeout} milliseconds")
      end
  """
  defmacro wait(expression, opts \\ []) do
    frequency = Keyword.get(opts, :frequency, 100)
    timeout = Keyword.get(opts, :timeout, 5_000)
    condition_var = Keyword.get(opts, :signal, nil)
    pre_wait = Keyword.get(opts, :pre_wait, 0)

    quote do
      require WaitForIt.V1.Helpers, as: Helpers
      Helpers.pre_wait(unquote(pre_wait))

      Helpers.wait(
        Helpers.make_function(unquote(expression)),
        unquote(frequency),
        unquote(timeout),
        Helpers.localized_name(unquote(condition_var))
      )
    end
  end

  @doc ~S"""
  Wait until the given `expression` evaluates to a truthy value.

  Returns the truthy value or raises a `WaitForIt.TimeoutError` if a timeout occurs.

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
    * `:signal` - disable polling and use a condition variable of the given name instead
    * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time
  """
  defmacro wait!(expression, opts \\ []) do
    frequency = Keyword.get(opts, :frequency, 100)
    timeout = Keyword.get(opts, :timeout, 5_000)
    condition_var = Keyword.get(opts, :signal, nil)
    pre_wait = Keyword.get(opts, :pre_wait, 0)

    quote do
      require WaitForIt.V1.Helpers, as: Helpers
      Helpers.pre_wait(unquote(pre_wait))

      Helpers.wait!(
        Helpers.make_function(unquote(expression)),
        unquote(frequency),
        unquote(timeout),
        Helpers.localized_name(unquote(condition_var))
      )
    end
  end

  @doc ~S"""
  Wait until the given `expression` matches one of the case clauses in the given block.

  Returns the value of the matching clause, the value of the optional `else` clause,
  or a tuple of the form `{:timeout, timeout_milliseconds}`.

  The `do` block passed to this macro must be a series of case clauses exactly like a built-in
  Elixir `case` expression. Just like a `case` expression, the clauses will attempt to be matched
  from top to bottom and the first one that matches will provide the resulting value of the
  expression. The difference with `case_wait` is that if none of the clauses initially matches it
  will wait and periodically re-evaluate the clauses until one of them does match or a timeout
  occurs.

  An optional `else` clause may also be used to provide the value in case of a timeout. If an
  `else` clause is provided and a timeout occurs, then the `else` clause will be evaluated and
  the resulting value of the `else` clause becomes the value of the `case_wait` expression. If no
  `else` clause is provided and a timeout occurs, then the value of the `case_wait` expression is a
  tuple of the form `{:timeout, timeout_milliseconds}`.

  The optional `else` clause may also take the form of match clauses, such as those in a case
  expression. In this form, the `else` clause can match on the final value of the expression that
  was evaluated before the timeout occurred. See the examples below for an example of this.

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
    * `:signal` - disable polling and use a condition variable of the given name instead
    * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time

  ## Examples

    Wait until queue has at least 5 messages, then return them:

      WaitForIt.case_wait Queue.get_messages(queue), timeout: 30_000, frequency: 100 do
        messages when length(messages) > 4 -> messages
      else
        # If after 30 seconds we still don't have 5 messages, just return the messages we do have.
        messages -> messages
      end

    A thermostat that keeps temperature in a small range:

      def thermostat(desired_temperature) do
        WaitForIt.case_wait get_current_temperature() do
          temp when temp > desired_temperature + 2 ->
            turn_on_air_conditioning()
          temp when temp < desired_temperature - 2 ->
            turn_on_heat()
        end
        thermostat(desired_temperature)
      end

    Ring the church bells every 15 minutes:

      def church_bell_chimes do
        count = WaitForIt.case_wait Time.utc_now.minute, frequency: 60_000, timeout: 60_000 * 60 do
          15 -> 1
          30 -> 2
          45 -> 3
          0 -> 4
        end
        IO.puts(String.duplicate(" ding ding ding dong ", count))
        church_bell_chimes()
      end
  """
  defmacro case_wait(expression, opts \\ [], blocks) do
    frequency = Keyword.get(opts, :frequency, 100)
    timeout = Keyword.get(opts, :timeout, 5_000)
    condition_var = Keyword.get(opts, :signal)
    do_block = Keyword.get(blocks, :do)
    else_block = Keyword.get(blocks, :else)
    pre_wait = Keyword.get(opts, :pre_wait, 0)

    quote do
      require WaitForIt.V1.Helpers, as: Helpers
      Helpers.pre_wait(unquote(pre_wait))

      Helpers.case_wait(
        Helpers.make_function(unquote(expression)),
        unquote(frequency),
        unquote(timeout),
        Helpers.localized_name(unquote(condition_var)),
        Helpers.make_case_function(unquote(do_block)),
        Helpers.make_else_function(unquote(else_block))
      )
    end
  end

  @doc ~S"""
  Wait until one of the expressions in the given block evaluates to a truthy value.

  Returns the value corresponding with the matching expression, the value of the optional `else`
  clause, or a tuple of the form `{:timeout, timeout_milliseconds}`.

  The `do` block passed to this macro must be a series of expressions exactly like a built-in
  Elixir `cond` expression. Just like a `cond` expression, the embedded expresions will be
  evaluated from top to bottom and the first one that is truthy will provide the resulting value of
  the expression. The difference with `cond_wait` is that if none of the expressions is initially
  truthy it will wait and periodically re-evaluate them until one of them becomes truthy or a
  timeout occurs.

  An optional `else` clause may also be used to provide the value in case of a timeout. If an
  `else` clause is provided and a timeout occurs, then the `else` clause will be evaluated and
  the resulting value of the `else` clause becomes the value of the `cond_wait` expression. If no
  `else` clause is provided and a timeout occurs, then the value of the `cond_wait` expression is a
  tuple of the form `{:timeout, timeout_milliseconds}`.

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
    * `:signal` - disable polling and use a condition variable of the given name instead
    * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time

  ## Examples

    Trigger an alarm when any sensors go beyond a threshold:

      def sound_the_alarm do
        WaitForIt.cond_wait timeout: 60_000 * 60 * 24 do
          read_sensor(:sensor1) > 9 -> IO.puts("Alarm: :sensor1 too high!")
          read_sensor(:sensor2) < 100 -> IO.puts("Alarm: :sensor2 too low!")
          read_sensor(:sensor3) < 0 -> IO.puts("Alarm: :sensor3 below zero!")
        else
          IO.puts("All is good...for now.")
        end
        sound_the_alarm()
      end
  """
  defmacro cond_wait(opts \\ [], blocks) do
    frequency = Keyword.get(opts, :frequency, 100)
    timeout = Keyword.get(opts, :timeout, 5_000)
    condition_var = Keyword.get(opts, :signal)
    do_block = Keyword.get(blocks, :do)
    else_block = Keyword.get(blocks, :else)
    pre_wait = Keyword.get(opts, :pre_wait, 0)

    quote do
      require WaitForIt.V1.Helpers, as: Helpers
      Helpers.pre_wait(unquote(pre_wait))

      Helpers.cond_wait(
        unquote(frequency),
        unquote(timeout),
        Helpers.localized_name(unquote(condition_var)),
        Helpers.make_cond_function(unquote(do_block)),
        Helpers.make_function(unquote(else_block))
      )
    end
  end

  @doc ~S"""
  Send a signal to the given condition variable to indicate that any processes waiting on the
  condition variable should re-evaluate their wait conditions.

  The caller of `signal` must be in the same Elixir module as any waiters on the same condition
  variable since the module is used as a namespace for condition variables. This is to prevent
  accidental name collisions as well as to enforce good practice for encapsulation.
  """
  defmacro signal(condition_var) do
    quote do
      require WaitForIt.V1.Helpers, as: Helpers
      Helpers.condition_var_signal(Helpers.localized_name(unquote(condition_var)))
    end
  end
end
