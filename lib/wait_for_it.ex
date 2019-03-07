defmodule WaitForIt do
  @moduledoc ~S"""
  WaitForIt provides macros for various ways to wait for things to happen.

  Since most Elixir systems are highly concurrent there must be a way to coordinate and synchronize
  the processes in the system. While the language provides features (such as `Process.sleep/1` and
  `receive`/`after`) that can be used to implement such synchronization, they are inconvenient to
  use for this purpose. `WaitForIt` builds on top of these language features to provide convenient
  and easy-to-use facilities for synchronizing concurrent activities. While this is likely most
  useful for test code in which tests must wait for concurrent or asynchronous activities to
  complete, it is also useful in any scenario where concurrent processes must coordinate their
  activity. Examples include asynchronous event handling, producer-consumer processes, and
  time-based activity.

  There are three distinct forms of waiting provided:

  1. The `wait` macro waits until a given expression evaluates to a truthy value.
  2. The `case_wait` macro waits until a given expression evaluates to a value that
     matches any one of the given case clauses (looks like an Elixir `case` expression).
  3. The `cond_wait` macro waits until any one of the given expressions evaluates to a truthy
     value (looks like an Elixir `cond` expression).

  All three forms accept the same set of options to control their behavior:

  * `:timeout` - the amount of time to wait (in milliseconds) before giving up
  * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
  * `:signal` - disable polling and use a condition variable of the given name instead

  The `:signal` option warrants further explanation. By default, all three forms of waiting use
  polling to periodically re-evaluate conditions to determine if waiting should continue. The
  frequency of polling is controlled by the `:frequency` option. However, if the `:signal` option
  is given it disables polling altogether. Instead of periodically re-evaluating conditions at a
  particular frequency, a _condition variable_ is used to signal when conditions should be
  re-evaluated. It is expected that the `signal` macro will be used to unblock the waiting code
  in order to re-evaluate conditions. For example, imagine a typical producer-consumer problem in
  which a consumer process waits for items to appear in some buffer while a separate producer
  process occasionally place items in the buffer. In this scenario, the consumer process might use
  the `wait` macro with the `:signal` option to wait until there are some items in the buffer and
  the producer process would use the `signal` macro to tell the consumer that it might be time for
  it to check the buffer again.

  ```
  # CONSUMER
  # assume the existence of a `buffer_size` function
  WaitForIt.wait buffer_size() >= 4, signal: :wait_for_buffer
  ```

  ```
  # PRODUCER
  # put some things in buffer, then:
  WaitForIt.signal(:wait_for_buffer)
  ```

  Notice that the same condition variable name `:wait_for_buffer` is used in both cases. It is
  important to note that when using condition variables for signaling like this, both the `wait`
  invocation and the `signal` invocation should be in the same Elixir module. This is because
  `WaitForIt` uses the calling module as a namespace for condition variable names to prevent
  accidental name collisions with other registered processes in the application. Also note that
  just because a condition variable has been signalled does not necessarily mean that any waiters
  on that condition variable can stop waiting. Rather, a signal indicates that waiters should
  re-evaluate their waiting conditions to determine if they should continue to wait or not.
  """

  alias WaitForIt.Helpers

  @doc ~S"""
  Wait until the given `expression` evaluates to a truthy value.

  Returns `{:ok, value}` or `{:timeout, timeout_milliseconds}`.

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
    * `:signal` - disable polling and use a condition variable of the given name instead

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
    condition_var = Keyword.get(opts, :signal)

    if condition_var do
      quote do
        require WaitForIt.Helpers

        _ =
          Helpers.condition_var_wait(
            unquote(expression),
            unquote(condition_var),
            unquote(timeout)
          )
      end
    else
      quote do
        require WaitForIt.Helpers
        Helpers.polling_wait(unquote(expression), unquote(frequency), unquote(timeout))
      end
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

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
    * `:signal` - disable polling and use a condition variable of the given name instead

  ## Examples

    Wait until queue has at least 5 messages, then return them:

      WaitForIt.case_wait Queue.get_messages(queue), timeout: 30_000, frequency: 100 do
        messages when length(messages) > 4 -> messages
      else
        # If after 30 seconds we still don't have 4 messages, return an empty list.
        []
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

    if condition_var do
      quote do
        require WaitForIt.Helpers

        _ =
          Helpers.condition_var_case_wait(
            unquote(expression),
            unquote(condition_var),
            unquote(timeout),
            unquote(do_block),
            unquote(else_block)
          )
      end
    else
      quote do
        require WaitForIt.Helpers

        Helpers.polling_case_wait(
          unquote(expression),
          unquote(frequency),
          unquote(timeout),
          unquote(do_block),
          unquote(else_block)
        )
      end
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

    if condition_var do
      quote do
        require WaitForIt.Helpers

        _ =
          Helpers.condition_var_cond_wait(
            unquote(condition_var),
            unquote(timeout),
            unquote(do_block),
            unquote(else_block)
          )
      end
    else
      quote do
        require WaitForIt.Helpers

        Helpers.polling_cond_wait(
          unquote(frequency),
          unquote(timeout),
          unquote(do_block),
          unquote(else_block)
        )
      end
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
      require WaitForIt.Helpers
      Helpers.condition_var_signal(unquote(condition_var))
    end
  end
end
