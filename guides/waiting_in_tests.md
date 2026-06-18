# Waiting in tests

Tests are one of the most common places to reach for WaitForIt. Integration and end-to-end
tests routinely have to wait for an asynchronous or concurrent operation to finish before they
can make an assertion — a background job to run, a message to propagate, a record to land in the
database. WaitForIt replaces brittle `Process.sleep/1` calls and hand-rolled polling loops with
expressive waits that fail fast and read clearly.

## The quickest path: `WaitForIt.Test` assertions

For most tests, the `WaitForIt.Test` assertions are the most ergonomic option. They wait and
re-evaluate just like the core macros, but on timeout they fail with a normal
`ExUnit.AssertionError` — including the source expression and the last value seen — so failures
read like any other ExUnit failure.

```elixir
defmodule MyApp.SomeTest do
  use ExUnit.Case
  use WaitForIt.Test
end
```

```elixir
# Wait until an expression becomes truthy:
assert_eventually Repo.get(User, user_id).confirmed

# Wait until a pattern matches, binding out of it for later assertions:
assert_eventually {:ok, user} = fetch_user(user_id), timeout: 2_000
assert user.first_name == "Elijah"

# Assert something never happens within a window:
refute_eventually error_reported?()

# Assert something holds for the whole window:
assert_always circuit_closed?(), timeout: 500
```

These default to test-friendly timeouts (`assert_eventually` waits up to 1s; `refute_eventually`
and `assert_always` sample for 100ms). See `WaitForIt.Test` for details.

The rest of this guide covers the core macros directly, which you can also use in tests when you
want their exact return values or timeout semantics. The remaining examples assume:

```elixir
defmodule MyApp.SomeTest do
  use ExUnit.Case
  import WaitForIt
end
```

## Assert on a truthy result with `wait/2`

`wait/2` returns the truthy value that ended the wait, or the last falsy value on timeout, so it
drops straight into an assertion:

```elixir
assert wait(Repo.get(User, user_id))
```

Because pattern matching also works on the return value, you can make a stronger assertion:

```elixir
assert %User{first_name: "Elijah"} = wait(Repo.get(User, user_id), timeout: 1_000)
```

## Bind a result with `match_wait/3`

When you are waiting for a tagged result and want the value out of it, `match_wait/3` is the most
direct form:

```elixir
{:ok, user} = match_wait({:ok, %User{}}, Repo.fetch(User, user_id), timeout: 1_000)
assert user.first_name == "Elijah"
```

On timeout `match_wait/3` raises a `MatchError`, which fails the test with the last value it saw.

## Branch on the outcome with `case_wait/3`

`case_wait/3` shines when more than one outcome is interesting, or when you want a custom failure:

```elixir
case_wait Repo.all(active_users_query), timeout: 2_000, interval: 50 do
  [only_user] ->
    assert only_user.id == 42

  [_ | _] = users ->
    assert length(users) == 2
else
  [] ->
    flunk("expected at least one active user, got none")
end
```

The optional `else` block runs only on timeout, and can pattern-match on the last value that was
evaluated before giving up.

## Tips

- **Keep timeouts tight.** A wait should be long enough to absorb normal jitter but short enough
  that a genuine failure surfaces quickly. Prefer an explicit `:timeout` over the 5-second
  default in tests.
- **Tune the interval for fast feedback.** A smaller `:interval` (e.g. `interval: 10`) makes a
  successful wait return sooner; the default of `100` ms is usually fine.
- **Reach for the `!` variants for crisp failures.** `wait!/2` and friends raise
  `WaitForIt.TimeoutError` with the wait type, timeout, and last value, which can make the cause
  of a failing test obvious at a glance.
- **Avoid catch-all clauses** in `case_wait/3` and `cond_wait/2` — a clause that always matches
  ends the wait on the first evaluation. Use an `else` block instead.
