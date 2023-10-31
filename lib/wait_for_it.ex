defmodule WaitForIt do
  @moduledoc ~S"""
  Provides various ways of waiting for things to happen.

  ## Overview

  Elixir is a functional programming language with an emphasis on immmutability of data. However,
  when dealing with shared state or interacting with external systems, *change happens*.

  WaitForIt provides various ways of waiting for such changes to happen.

  While Elixir provides features such as `Process.sleep/1` and `receive/1`/`after`
  that can be used to implement waiting, they are inconvenient to use for this purpose. WaitForIt
  builds on top of these language features to provide convenient and easy-to-use facilities for
  waiting on specific conditions. While this is likely most useful for test code in which tests
  must wait for concurrent or asynchronous activities to complete, it is also useful in any
  scenario where concurrent processes must coordinate their activity. Examples include
  asynchronous event handling, producer-consumer processes, and time-based activity.

  ## Quick start

  There are three distinct forms of waiting provided. Jump to the docs for each for more
  information.

  1. The `wait/2` macro waits until a given expression evaluates to a truthy value.
  2. The `case_wait/3` macro waits until a given expression evaluates to a value that
     matches any one of the given case clauses (looks like an Elixir `case/2` expression).
  3. The `cond_wait/2` macro waits until any one of the given expressions evaluates to a truthy
     value (looks like an Elixir `cond/1` expression).

  All three forms accept the same set of options to control their behavior:

  * `:timeout` - the amount of time to wait (in milliseconds) before giving up
  * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time
  * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
  * `:signal` - disable polling and use a signal of the given name instead

  See [Polling-based waiting](#module-polling-based-waiting) for more information on the
  `:frequency` option and [Signal-based waiting](#module-signal-based-waiting) for more
  information on the `:signal` option.

  ## Waitable expressions and waiting conditions

  _Waitable expressions_ and _waiting conditions_ are fundamental concepts in WaitForIt.

  A _waitable expression_ is any arbitrary Elixir expression that can be evaluated one or more
  times to produce a value.

  A _waiting condition_ is a conditional expression that indicates whether waiting should continue
  or be halted with a particular value.

  In the case of `wait/2`, there is a single waitable expression, which is passed as the first
  argument of the macro, and an implicit waiting condition, which is based on the truthiness
  of waitable expression. For example:

      WaitForIt.wait(2 + 2 == 5, timeout: 200)

  In this example the waitable expression is `2 + 2 == 5` and the implicit waiting condition is
  the truthiness of that expression. The waitable expression is repeatedly evaluated until the
  value that it produces satisfies the waiting condition. In this case, the value of evaluating
  the expression is always `false` so it will never satisfy the waiting condition of a truthy
  value, and will therefore result in a timeout.

  For `case_wait/3`, there is a single waitable expression and one or more explicit waiting
  conditions expressed as case clauses. For example:

      WaitForIt.case_wait(File.stat("data.csv"), timeout: :timer.seconds(10)) do
        {:ok, %File.Stat{} = file_stat} -> IO.inspect(file_stat)
      end

  In this example the waitable expression is `File.stat("data.csv")`, which, upon evaluation,
  results in a value of either `{:ok, %FileStat{}}` or `{:error, reason}`. There is also one
  explicit waiting condition, which is the case clause `{:ok, %File.Stat{} = file_stat}`.
  The waitable expression will be repeatedly evaluated until it produces a value satisfying the
  lone waiting condition. In other words, it will wait until the file exists or a timeout occurs.

  For `cond_wait/2`, there can be one or more waitable expressions and each one is paired with an
  implicit waiting condition, which is the truthiness of the waitable expression value.
  For example:

      WaitForIt.cond_wait(timeout: :timer.hours(1)) do
        Date.utc_today().day == 1 -> IO.puts("It's the first day of the month")
        NaiveDateTime.utc_now().minute == 30 -> IO.puts("It's half past the hour")
      end

  In this example, there are two waitable expressions: `Date.utc_today().day == 1` and
  `NaiveDateTime.utc_now().minute == 30`. Each of these is paired with an implicit waiting
  condition, which is the truthiness of the value produced by evaluating the expression.

  ### Idempotency of waitable expressions

  Waitable expressions are by their nature subject to change with repeated evaluations over time.
  Therefore, idempotent expressions are of little use in the context of waiting, since waiting
  would either halt immediately (if the expression already saitisfies the waiting conditions)
  or never halt at all (if it does not satisfy the waiting conditions).

  It is important, however, that any side-effects that can occur during evaluation of the
  expression are safe and predictable, since the expression may be evaluated an inderminate
  number of times while waiting.

  ## Polling-based waiting

  By default, WaitForIt uses a polling-based waiting mode in which waitable expressions are
  periodically re-evaluated until waiting conditions have been met or a timeout has occurred.
  The frequency at which waitable expressions are evaluated can be controlled by the `:frequency`
  option, which specifies the delay between evaluations in milliseconds and is supported by all
  forms of waiting.

  > #### Polling "frequency" {: .neutral}
  >
  > The term "frequency" is something of a misnomer as it is used here, since it is a time value
  > (milliseconds) rather than a rate. A more accurate term would be `:polling_interval`, or
  > perhaps simply `:interval`, but `:frequency` is already in use.
  >
  > For the curious, the actual frequency in Hertz can be derived from the value of the
  > `:frequency` option using this formula: `1 / (:frequency / 1000)`
  >
  > Thus a `:frequency` value of 100 yields a frequency of 10 Hz.

  ## Signal-based waiting

  Signal-based waiting obviates the need for polling by using a signaling mechanism to indicate
  that waiting conditions should be re-evaluated in response to some event. With signal-based
  waiting, instead of periodically re-evaluating conditions at a particular frequency, a signal
  is sent to waiters to indicate when waiting conditions should be re-evaluated. It is expected
  that the `signal/1` function will be used to unblock the waiting code in order to re-evaluate
  the waiting conditions.

  To use signal-based waiting instead of polling-based waiting use the `:signal` option that is
  supported by all forms of waiting. The value of the `:signal` option is an arbitrary term
  (typically an atom or a tuple of atoms) that serves as the binding between the waiting
  conditions and the asynchronous code that can alter the outcome of those waiting conditions.
  When the `:signal` option is used, WaitForIt will automatically wait until a matching signal is
  received and then re-evaluate waiting conditions. If the waiting conditions are saitisfied then
  the wait is halted, if not then the wait continues until the next signal is received or a
  timeout occurs.

  By way of example, imagine a typical producer-consumer problem in which a consumer process waits
  for items to appear in some buffer while a separate producer process occasionally place items in
  the buffer. In this scenario, the consumer process might use the `wait/2` macro with the
  `:signal` option to wait until there are some items in the buffer and the producer process would
  use the `signal/1` function to tell the consumer that it might be time for it to check the
  buffer again.

      # CONSUMER
      # assume the existence of a `buffer_size` function
      WaitForIt.wait buffer_size() >= 4, signal: :wait_for_buffer

      # PRODUCER
      # put some things in buffer, then:
      WaitForIt.signal(:wait_for_buffer)

  Notice that the same signal name `:wait_for_buffer` is used by both the consumer and the
  producer, which is what allows the producer to signal to the consumer that waiting conditions
  should be re-evaluated. It is important to realize that just because a signal has been emitted
  does not necessarily mean that any waiting conditions have been satisfied. Rather, a signal
  indicates that waiters should re-evaluate their waiting conditions to determine if they should
  continue to wait or not.

  ## Using WaitForIt in tests

  One common use case for waiting on the results of asynchronous operations is in tests,
  particularly in integration or end-to-end tests. This section will present examples of using
  the various forms of waiting in test code. All examples assume that the `WaitForIt` module has
  been imported in the test module, such as follows:

      defmodule MyTest do
        use ExUnit.Case
        import WaitForIt
      end

  The `wait/2` macro can be used directly in assertions, since it returns the truthy or falsy
  value that the waitable expression evaluated to (i.e. a truthy value for successful waits or a
  falsy value for timeouts). For example, to assert that a particular database record is
  eventually inserted into the database can be as simple as:

      assert wait(Repo.get(User, user_id))

  Alternatively, pattern-matching can be used in some cases to make stronger assertions, such as:

      assert %User{first_name: "Elijah"} = wait(Repo.get(User, user_id), timeout: 1_000)

  The `case_wait/3` macro offers greater flexibility in the sense that it allows for matching on
  any one of a series of case clauses and also allows for the use of an `else` block if none of
  the case clauses eventually match. For example, to assert that a particular database record is
  eventually inserted and that it has particular values:

      case_wait Repo.get(User, user_id), timeout: 1_000 do
        %User{id: ^user_id} = user ->
          assert user.first_name == "Elijah"
          assert Date.compare(user.birth_date, ~D[2023-07-20]) == :eq
      else
        unexpected ->
          flunk("Expected a User record for Elijah, got something else: #{inspect(unexpected)}")
      end

  Or to test if exactly one or two records are returned for a particular query, something like
  the following can be used:

      case_wait Repo.all(some_query), timeout: 2_000, frequency: 500 do
        [only_thing] -> assert only_thing.id == 42
        [thing1, thing2] -> assert thing1.id == 1 and thing2.id == 2
      else
        [] -> flunk("expected one or two things, got no things")
        [_ | _] = things -> flunk("expected one or two things, got #{length(things)} things")
      end
  """

  @typedoc """
  Type to represent an expression that can be waited on.
  """
  @type wait_expression :: Macro.t()

  @typedoc """
  Options that can be used to control waiting behavior.
  """
  @type wait_opt ::
          {:timeout, non_neg_integer()}
          | {:frequency, non_neg_integer()}
          | {:pre_wait, non_neg_integer()}
          | {:signal, atom() | nil}

  @typedoc """
  Options that can be used to control waiting behavior.

  See `t:wait_opt/0`.
  """
  @type wait_opts :: [wait_opt()]

  @doc ~S"""
  Wait until the given `expression` evaluates to a truthy value.

  Returns the truthy value that ended the wait, or the last falsy value evaluated if a timeout
  occurred.

  > #### Warning {: .warning}
  >
  > The value returned from this macro has changed as of version 2.0.
  >
  > In previous versions, `{:ok, value}` would be returned for the success case, and
  > `{:timeout, timeout_milliseconds}` would be returned for the timeout case.
  >
  > As of version 2.0, the final value of the wait expression is returned directly, which will
  > be a truthy value for the success case and a falsy value for the timeout case. This allows
  > the `wait/2` macro to be used in conditional expressions, such as in `if/2`/`else` expressions,
  > or in assertions in tests.
  >
  > If you are migrating from version 1.x and rely on the return value, you can enable the
  > previous behavior by using the `WaitForIt.V1.wait/2` macro instead.

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time
    * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
    * `:signal` - disable polling and use a signal of the given name instead

  ## Examples

  Wait until the top of the hour:

      WaitForIt.wait Time.utc_now.minute == 0, frequency: 60_000, timeout: 60_000 * 60

  Wait up to one minute for a particular record to appear in the database:

      if data = WaitForIt.wait Repo.get(Post, 42), frequency: 1000, timeout: :timer.seconds(60) do
        IO.inspect(data)
      else
        IO.puts("Gave up after #{timeout} milliseconds")
      end

  Assert that a database record is created by some asynchronous process:

      do_some_async_work()
      assert %Post{id: 42} = WaitForIt.wait Repo.get(Post, 42)
  """
  defmacro wait(expression, opts \\ []) do
    quote do
      require WaitForIt.Waitable.BasicWait

      waitable = WaitForIt.Waitable.BasicWait.create(unquote(expression))
      WaitForIt.Waiting.wait(waitable, unquote(opts), __ENV__)
    end
  end

  @doc """
  The same as `wait/2` but raises a `WaitForIt.TimeoutError` exception if it fails.
  """
  defmacro wait!(expression, opts \\ []) do
    quote do
      require WaitForIt.Waitable.BasicWait

      waitable = WaitForIt.Waitable.BasicWait.create(unquote(expression))
      WaitForIt.Waiting.wait!(waitable, unquote(opts), __ENV__)
    end
  end

  @doc ~S"""
  Wait until the given `expression` matches one of the case clauses in the given block.

  Returns the value of the matching clause, the value of the optional `else` clause,
  or the last evaluated value of the expression in the event of a timeout.

  The `do` block passed to this macro must be a series of case clauses exactly like a built-in
  Elixir `case/2` expression. Just like a `case/2` expression, the clauses will attempt to be
  matched from top to bottom and the first one that matches will provide the resulting value of the
  expression. The difference with `case_wait/3` is that if none of the clauses initially matches it
  will wait and periodically re-evaluate the clauses until one of them does match or a timeout
  occurs.

  An optional `else` clause may also be used to provide the value in case of a timeout. If an
  `else` clause is provided and a timeout occurs, then the `else` clause will be evaluated and
  the resulting value of the `else` clause becomes the value of the `case_wait/3` expression. If no
  `else` clause is provided and a timeout occurs, then the value of the `case_wait/3` expression is
  the last evaluated value of the expression.

  The optional `else` clause may also take the form of match clauses, such as those in a case
  expression. In this form, the `else` clause can match on the final value of the expression that
  was evaluated before the timeout occurred. See the examples below for an example of this.

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time
    * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
    * `:signal` - disable polling and use a signal of the given name instead

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
        count =
          WaitForIt.case_wait Time.utc_now.minute, frequency: 60_000, timeout: 60_000 * 60 do
            15 -> 1
            30 -> 2
            45 -> 3
            0 -> 4
          end

        IO.puts(String.duplicate(" ding ding ding dong ", count))

        # Recursively call to wait for the next time to ring the bells...
        church_bell_chimes()
      end
  """
  defmacro case_wait(expression, opts \\ [], blocks) do
    case_clauses = Keyword.get(blocks, :do)
    else_block = Keyword.get(blocks, :else)

    quote do
      require WaitForIt.Waitable.CaseWait

      waitable =
        WaitForIt.Waitable.CaseWait.create(
          unquote(expression),
          unquote(case_clauses),
          unquote(else_block)
        )

      WaitForIt.Waiting.wait(waitable, unquote(opts), __ENV__)
    end
  end

  @doc """
  The same as `case_wait/3` but raises a `WaitForIt.TimeoutError` exception if it fails.
  """
  defmacro case_wait!(expression, opts \\ [], blocks) do
    case_clauses = Keyword.get(blocks, :do)
    else_block = Keyword.get(blocks, :else)

    quote do
      require WaitForIt.Waitable.CaseWait

      waitable =
        WaitForIt.Waitable.CaseWait.create(
          unquote(expression),
          unquote(case_clauses),
          unquote(else_block)
        )

      WaitForIt.Waiting.wait!(waitable, unquote(opts), __ENV__)
    end
  end

  @doc ~S"""
  Wait until one of the expressions in the given block evaluates to a truthy value.

  Returns the value corresponding with the matching expression, the value of the optional `else`
  clause, or `nil` in the event of a timeout.

  The `do` block passed to this macro must be a series of expressions exactly like a built-in
  Elixir `cond/1` expression. Just like a `cond/1` expression, the embedded expresions will be
  evaluated from top to bottom and the first one that is truthy will provide the resulting value of
  the expression. The difference with `cond_wait/2` is that if none of the expressions is initially
  truthy it will wait and periodically re-evaluate them until one of them becomes truthy or a
  timeout occurs.

  An optional `else` clause may also be used to provide the value in case of a timeout. If an
  `else` clause is provided and a timeout occurs, then the `else` clause will be evaluated and
  the resulting value of the `else` clause becomes the value of the `cond_wait/2` expression. If no
  `else` clause is provided and a timeout occurs, then the value of the `cond_wait/2` expression is
  `nil`.

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time
    * `:frequency` - the polling frequency (in milliseconds) at which to re-evaluate conditions
    * `:signal` - disable polling and use a signal of the given name instead

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

        # Recursively call to wait for the next sensor readings...
        sound_the_alarm()
      end
  """
  defmacro cond_wait(opts \\ [], blocks) do
    cond_clauses = Keyword.get(blocks, :do)
    else_block = Keyword.get(blocks, :else)

    quote do
      require WaitForIt.Waitable.CondWait

      waitable =
        WaitForIt.Waitable.CondWait.create(
          unquote(cond_clauses),
          unquote(else_block)
        )

      WaitForIt.Waiting.wait(waitable, unquote(opts), __ENV__)
    end
  end

  @doc """
  The same as `cond_wait/2` but raises a `WaitForIt.TimeoutError` exception if it fails.
  """
  defmacro cond_wait!(opts \\ [], blocks) do
    cond_clauses = Keyword.get(blocks, :do)
    else_block = Keyword.get(blocks, :else)

    quote do
      require WaitForIt.Waitable.CondWait

      waitable =
        WaitForIt.Waitable.CondWait.create(
          unquote(cond_clauses),
          unquote(else_block)
        )

      WaitForIt.Waiting.wait!(waitable, unquote(opts), __ENV__)
    end
  end

  # defmacro match_wait(pattern, expression, opts \\ []) do
  #   quote do
  #     require WaitForIt.Waitable.MatchWait
  #
  #     waitable = WaitForIt.Waitable.MatchWait.create(unquote(pattern), unquote(expression))
  #     WaitForIt.Waiting.wait(waitable, unquote(opts), __ENV__)
  #   end
  # end

  # defmacro with_wait(with_clauses, blocks) do
  #   # TODO:
  #   # Implement this macro.
  #   #
  #   # Consider using `<~` for waiting version of the `<-` operator.
  #   # Figure out how to pass waiting options (e.g. timeout & frequency) to the individual 
  #   # expressions in the with_clauses. Should the RHS be a 2-tuple of the form
  #   # `{expression, wait_opts}`? Or should there be another named macro that builds such a tuple?
  #   #
  #   # Implementation ideas:
  #   # Collect all of the with_clauses and group by `<~` (waiting) and `<-` non-waiting clauses.
  #   # Waiting clauses use the same waiting semantics as the other wait forms in this module.
  #   # Non-waiting clauses are perhaps evaluated immediatelY? But what if there are dependencies
  #   # between clauses? Can we figure that out? Or perhaps we don't need to if we still evaluate all
  #   # of the clauses serially, applying waiting semantics whenever applicable.
  # end

  @doc """
  Send a signal to indicate that any processes waiting on the signal should re-evaluate their
  waiting conditions.
  """
  def signal(signal) do
    Registry.dispatch(WaitForIt.SignalRegistry, signal, fn waiters ->
      for {pid, _env} <- waiters, do: send(pid, {:wait_for_it_signal, signal})
    end)
  end
end
