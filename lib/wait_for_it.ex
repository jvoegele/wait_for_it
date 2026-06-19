defmodule WaitForIt do
  # The module documentation is the demarcated section of the README, kept as the single source
  # of truth so the two never drift. `@external_resource` recompiles this module when the README
  # changes.
  @readme Path.expand("./README.md")
  @external_resource @readme
  @moduledoc @readme
             |> File.read!()
             |> String.split("<!-- README START -->")
             |> Enum.at(1)
             |> String.split("<!-- README END -->")
             |> List.first()

  @typedoc """
  Type to represent an expression that can be waited on.
  """
  @type wait_expression :: Macro.t()

  @typedoc """
  Options that can be used to control waiting behavior.
  """
  @type wait_opt ::
          {:timeout, non_neg_integer()}
          | {:interval, non_neg_integer()}
          | {:frequency, non_neg_integer()}
          | {:pre_wait, non_neg_integer()}
          | {:signal, atom() | nil}

  @typedoc """
  Options that can be used to control waiting behavior.

  See `t:wait_opt/0`.
  """
  @type wait_opts :: [wait_opt()]

  @type signal :: atom() | {atom(), atom()} | {atom(), atom(), atom()} | list(atom()) | term()

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
    * `:interval` - the polling interval in milliseconds, or a `WaitForIt.Backoff` function, at which to re-evaluate conditions (alias: `:frequency`)
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
  @doc section: :wait
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
  @doc section: :wait
  defmacro wait!(expression, opts \\ []) do
    quote do
      require WaitForIt.Waitable.BasicWait

      waitable = WaitForIt.Waitable.BasicWait.create(unquote(expression))
      WaitForIt.Waiting.wait!(waitable, unquote(opts), __ENV__)
    end
  end

  @doc ~S"""
  Wait until the given `expression` matches one of the case clauses in the given block.

  Returns the value of the matching clause, or the value of the optional `else` clause in the
  event of a timeout.

  The `do` block passed to this macro must be a series of case clauses exactly like a built-in
  Elixir `case/2` expression. Just like a `case/2` expression, the clauses will attempt to be
  matched from top to bottom and the first one that matches will provide the resulting value of the
  expression. The difference with `case_wait/3` is that if none of the clauses initially matches it
  will wait and periodically re-evaluate the clauses until one of them does match or a timeout
  occurs.

  An optional `else` clause may also be used to provide the value in case of a timeout. If an
  `else` clause is provided and a timeout occurs, then the `else` clause will be evaluated and
  the resulting value of the `else` clause becomes the value of the `case_wait/3` expression. If no
  `else` clause is provided and a timeout occurs, then a `CaseClauseError` is raised, exactly as
  if a normal Elixir `case/2` expression were being used.

  The optional `else` clause may also take the form of match clauses, such as those in the `else`
  clause of a `with/1` expression. In this form, the `else` clause can match on the final value
  of the expression that was evaluated before the timeout occurred. See the examples below for an
  example of this.

  > #### Beware "catch-all" clauses {: .warning}
  >
  > `case_wait/3` expressions should *not* include a final "catch-all" clause, such as `_`, which
  > would always match. Instead, an `else` clause can be used to customize the behavior and
  > return value in the event of a waiting timeout.
  >
  > See [A note on "catch-all" clauses](#module-a-note-on-catch-all-clauses) in the module docs
  > for further information.

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time
    * `:interval` - the polling interval in milliseconds, or a `WaitForIt.Backoff` function, at which to re-evaluate conditions (alias: `:frequency`)
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

  Wait until the process mailbox is small enough before flooding it with more messages:

      WaitForIt.case_wait Process.info(stream_pid, :message_queue_len),
        frequency: 10,
        timeout: 60_000 do
        {:message_queue_len, len} when len < 500 ->
          send_chunk(conn, chunk)
      else
        len ->
          raise "Timeout while sending stream response. [message_queue_len: #{len}]"
      end

  > #### Production-ready {: .info}
  >
  > The above example is a real-world use of WaitForIt that was used to solve an issue with chunked
  > HTTP responses using [plug_cowboy](https://github.com/elixir-plug/plug_cowboy). The underlying
  > issue has since been fixed but this example is a good illustration of using WaitForIt to
  > solve a production problem.
  >
  > See https://github.com/elixir-plug/plug_cowboy/issues/10 for background and further details,
  > if interested.

  """
  @doc section: :case_wait
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
  @doc section: :case_wait
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

  Returns the value corresponding with the matching expression, or the value of the optional
  `else` clause in the event of a timeout.

  The `do` block passed to this macro must be a series of expressions exactly like a built-in
  Elixir `cond/1` expression. Just like a `cond/1` expression, the embedded expresions will be
  evaluated from top to bottom and the first one that is truthy will provide the resulting value of
  the expression. The difference with `cond_wait/2` is that if none of the expressions is initially
  truthy it will wait and periodically re-evaluate them until one of them becomes truthy or a
  timeout occurs.

  An optional `else` clause may also be used to provide the value in case of a timeout. If an
  `else` clause is provided and a timeout occurs, then the `else` clause will be evaluated and
  the resulting value of the `else` clause becomes the value of the `cond_wait/2` expression. If no
  `else` clause is provided and a timeout occurs, then a `CondClauseError` is raised, exactly as
  if a normal Elixir `cond/1` expression were being used.

  > #### Beware "catch-all" clauses {: .warning}
  >
  > `cond_wait/2` expressions should *not* include a final "catch-all" clause, such as `true`,
  > which would always match. Instead, an `else` clause can be used to customize the behavior and
  > return value in the event of a waiting timeout.
  >
  > See [A note on "catch-all" clauses](#module-a-note-on-catch-all-clauses) in the module docs
  > for further information.

  ## Options

  See the WaitForIt module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time
    * `:interval` - the polling interval in milliseconds, or a `WaitForIt.Backoff` function, at which to re-evaluate conditions (alias: `:frequency`)
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
  @doc section: :cond_wait
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
  @doc section: :cond_wait
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

  @doc ~S"""
  Wait until the given `expression` matches the given `pattern`.

  Returns the value that the expression evaluated to when it matched the pattern. The `pattern`
  may include a guard, exactly like the left-hand side of a `case/2` clause or a `<-` clause in
  `with/1`.

  Where `wait/2` waits for a *truthy* value, `match_wait/3` waits for a value that *matches a
  pattern* and binds out of it. It is the most convenient form when you are waiting for a tagged
  result such as `{:ok, value}` and want `value` directly.

  > #### Beware bound variables in the pattern {: .warning}
  >
  > Just like `case/2`, variables in the pattern are *binding* unless pinned with `^`. The
  > pattern is only a waiting condition, not an assertion about a specific value, so prefer
  > guards (`when ...`) to express conditions on the matched value.

  ## Options

  See the `WaitForIt` module documentation for further discussion of these options.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:pre_wait` - wait for the given number of milliseconds before evaluating conditions for the first time
    * `:interval` - the polling interval (in milliseconds) at which to re-evaluate conditions
    * `:signal` - disable polling and use a signal of the given name instead

  ## Examples

  Wait until a database record exists and bind it directly:

      {:ok, user} = match_wait({:ok, %User{}}, Repo.fetch(User, id), timeout: 2_000)

  Wait until a value satisfies a guard, then use the bound variable:

      count = match_wait(n when n > 99, get_counter(), signal: :counter_wait)

  On timeout (with no matching value), a `MatchError` is raised, exactly as if a normal
  pattern match had failed. Use `match_wait!/3` to raise a `WaitForIt.TimeoutError` instead.
  """
  @doc section: :match_wait
  defmacro match_wait(pattern, expression, opts \\ []) do
    quote do
      require WaitForIt.Waitable.MatchWait

      waitable = WaitForIt.Waitable.MatchWait.create(unquote(pattern), unquote(expression))
      WaitForIt.Waiting.wait(waitable, unquote(opts), __ENV__)
    end
  end

  @doc """
  The same as `match_wait/3` but raises a `WaitForIt.TimeoutError` exception on timeout.
  """
  @doc section: :match_wait
  defmacro match_wait!(pattern, expression, opts \\ []) do
    quote do
      require WaitForIt.Waitable.MatchWait

      waitable = WaitForIt.Waitable.MatchWait.create(unquote(pattern), unquote(expression))
      WaitForIt.Waiting.wait!(waitable, unquote(opts), __ENV__)
    end
  end

  @doc ~S"""
  Compose several waits in a `with`-style pipeline.

  `with_wait` looks and behaves like an Elixir `with/1` expression, except that its clauses can
  *wait*. The clauses are wrapped in `on(...)`, and each clause is one of:

    * `pattern <- expression` - an ordinary `with` clause, evaluated once. If it matches, bind and
      continue; otherwise route to the `else` block.
    * `pattern <~ expression` - a *wait-for-match* clause: re-evaluate `expression` until it
      matches `pattern`, then bind and continue.
    * `pattern <~ {expression, opts}` - a wait-for-match clause with per-clause options (such as
      `timeout:`/`interval:`/`signal:`) that override the global options.

  Global options for every `<~` clause may be given between the `on(...)` wrapper and the block:
  `with_wait on(...), timeout: 2_000 do ... end`.

  On success, the `do` block is evaluated and its value returned. If any clause fails to match —
  including a `<~` clause that *times out* — control transfers to the `else` block (or, if there
  is no `else`, the non-matching value becomes the result), exactly like `with/1`. A `<~` timeout
  is therefore indistinguishable from an ordinary non-match: the last evaluated value flows to
  `else`.

  > #### `<~` precedence {: .warning}
  >
  > `<~` binds more tightly than `when` and the comparison operators, so guards and right-hand
  > sides that use those operators must be parenthesized:
  >
  >     ({:ok, n} when n > 5) <~ poll()
  >     found <~ (Enum.find(items, &ready?/1) != nil)
  >
  > Simple clauses such as `{:ok, x} <~ fetch(id)` and `{:ok, x} <~ {fetch(id), timeout: 100}`
  > need no parentheses. For a wait dominated by a single complex condition, prefer `case_wait/3`.

  ## Examples

      with_wait on(
        {:ok, token}   <-  authenticate(user),
        {:ok, account} <~  {load_account(token), timeout: 2_000},
        {:ok, balance} <~  fetch_balance(account)
      ), interval: 50 do
        {:ok, balance}
      else
        {:error, reason} -> {:error, reason}
        still_pending -> {:still_waiting, still_pending}
      end
  """
  @doc section: :with_wait
  defmacro with_wait(clauses, opts \\ [], blocks) do
    WaitForIt.WithWait.build(clauses, opts, blocks, :return_last_value)
  end

  @doc """
  The same as `with_wait/3` but a `<~` clause that times out raises a `WaitForIt.TimeoutError`
  instead of routing to the `else` block.

  An `else` block is still honored for ordinary `<-` clauses that do not match.
  """
  @doc section: :with_wait
  defmacro with_wait!(clauses, opts \\ [], blocks) do
    WaitForIt.WithWait.build(clauses, opts, blocks, :raise)
  end

  @doc false
  # Internal building block for `with_wait` clauses: waits until `expression` matches `pattern`,
  # returning the matched value. The timeout behavior is controlled by the `:on_timeout` option
  # carried in `opts` (`:return_last_value` for `with_wait`, `:raise` for `with_wait!`).
  defmacro __wait_clause__(pattern, expression, opts) do
    match_pattern = WaitForIt.Evaluation.ignore_pattern_bindings(pattern)

    quote do
      require WaitForIt.Waitable.MatchWait

      waitable =
        WaitForIt.Waitable.MatchWait.create(unquote(match_pattern), unquote(expression))

      WaitForIt.Waiting.wait(waitable, unquote(opts), __ENV__)
    end
  end

  @doc ~S"""
  Wait until the given zero-arity function returns a truthy value.

  This is the functional (non-macro) counterpart of `wait/2`. Where `wait/2` captures an
  expression to re-evaluate, `until/2` re-invokes the function you supply — which makes it the
  natural choice when the condition is computed at runtime, built dynamically, or passed in as a
  function value.

  Unlike `wait/2`, which returns the bare truthy/falsy value, `until/2` returns a tagged result so
  that success and timeout are always unambiguous:

    * `{:ok, value}` - the function returned the truthy `value` that ended the wait
    * `{:timeout, last_value}` - the wait timed out; `last_value` is the last (falsy) value seen

  ## Options

  Accepts the same options as the other waiting forms. See the WaitForIt module documentation for
  further discussion.

    * `:timeout` - the amount of time to wait (in milliseconds) before giving up
    * `:pre_wait` - wait for the given number of milliseconds before evaluating for the first time
    * `:interval` - the polling interval in milliseconds, or a `WaitForIt.Backoff` function (alias: `:frequency`)
    * `:signal` - disable polling and use a signal of the given name instead

  ## Examples

      case WaitForIt.until(fn -> Repo.get(Post, id) end, timeout: :timer.seconds(5)) do
        {:ok, post} -> post
        {:timeout, _} -> raise "post #{id} never appeared"
      end

  Because the condition is an ordinary value, it can be built up first and passed in:

      ready? = fn -> Enum.all?(deps, &Service.healthy?/1) end
      {:ok, _} = WaitForIt.until(ready?, timeout: :timer.seconds(30))
  """
  @doc section: :until
  @spec until((-> term()), wait_opts()) :: {:ok, term()} | {:timeout, term()}
  def until(fun, opts \\ []) when is_function(fun, 0) do
    waitable = %WaitForIt.Waitable.FunctionWait{fun: fun}

    case WaitForIt.Waiting.wait_outcome(waitable, opts, nil) do
      {:matched, value} -> {:ok, value}
      {:timeout, last_value} -> {:timeout, last_value}
    end
  end

  @doc """
  The same as `until/2` but raises a `WaitForIt.TimeoutError` on timeout.

  On success it returns the truthy value directly (not wrapped in an `:ok` tuple), mirroring the
  other bang variants.
  """
  @doc section: :until
  @spec until!((-> term()), wait_opts()) :: term()
  def until!(fun, opts \\ []) when is_function(fun, 0) do
    waitable = %WaitForIt.Waitable.FunctionWait{fun: fun}
    WaitForIt.Waiting.wait!(waitable, opts, nil)
  end

  @doc """
  Send a signal to indicate that any processes waiting on the signal should re-evaluate their
  waiting conditions.
  """
  @doc section: :signal
  @spec signal(signal()) :: :ok
  def signal(signal) do
    Registry.dispatch(WaitForIt.SignalRegistry, signal, fn waiters ->
      for {pid, _env} <- waiters, do: send(pid, {:wait_for_it_signal, signal})
    end)
  end
end
