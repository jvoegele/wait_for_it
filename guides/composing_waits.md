# Composing waits

A single wait answers one question: "has *this* become true yet?" Real workflows often need to
chain several such questions, where each step depends on the previous one and any step might fail
or time out. `WaitForIt.with_wait/3` composes waits into a single `with`-style pipeline.

## The shape

```elixir
with_wait on(
  {:ok, token}   <-  authenticate(user),                    # one-shot match (no waiting)
  {:ok, account} <~  {load_account(token), timeout: 2_000}, # wait, with per-clause options
  {:ok, balance} <~  fetch_balance(account)                 # wait, with global/default options
), interval: 50 do
  {:ok, balance}
else
  {:error, reason} -> {:error, reason}
  still_pending    -> {:still_waiting, still_pending}
end
```

It reads like `with/1`, with two clause arrows:

- **`<-`** — an ordinary `with` clause: evaluated **once**. Matches → bind and continue; doesn't
  match → route to `else`.
- **`<~`** — a **wait-for-match** clause: re-evaluate the right-hand side until it matches the
  pattern, then bind and continue.

The clauses are wrapped in `on(...)` (a purely syntactic wrapper — there is no `on` function), and
global options for every `<~` clause go between the wrapper and the block.

## How failure and timeout flow

`with_wait` mirrors `with/1`:

- If every clause matches (waiting as needed), the `do` block runs and its value is the result.
- If a `<-` clause doesn't match, control goes to `else` with the non-matching value.
- If a `<~` clause **times out**, its last evaluated value flows to `else` too — a timeout is
  treated exactly like a non-match. With no `else`, that last value becomes the result.

This is what makes composition clean: a stalled step and a wrong-shaped step are handled the same
way, in one place.

```elixir
# If load_account/1 never returns {:ok, _} within 2s, `:still_loading` (its last value) flows
# to the else block.
with_wait on({:ok, account} <~ {load_account(token), timeout: 2_000}) do
  account
else
  :still_loading -> {:error, :account_timeout}
end
```

## Options

Every `<~` clause accepts the usual options — `:timeout`, `:interval` (including a
`WaitForIt.Backoff` function), `:pre_wait`, and `:signal`. Per-clause options override the global
options:

```elixir
with_wait on(
  {:ok, a} <~ slow_thing(),                       # uses the global timeout: 5_000
  {:ok, b} <~ {flaky_thing(), timeout: 500}       # this one gives up after 500ms
), timeout: 5_000 do
  {a, b}
end
```

## Guards and the `<~` precedence rule

`<~` binds more tightly than `when` and the comparison operators, so guards and comparison-heavy
right-hand sides must be parenthesized:

```elixir
# Wait until a counter exceeds a threshold:
with_wait on(({:ok, n} when n > 5) <~ read_counter()) do
  n
end

# Parenthesize a comparison on the right-hand side:
with_wait on(found <~ (Enum.find(items, &ready?/1) != nil)) do
  found
end
```

Simple clauses such as `{:ok, x} <~ fetch(id)` and `{:ok, x} <~ {fetch(id), timeout: 100}` need no
parentheses. If a wait is dominated by a single complex condition, `case_wait/3` is often clearer.

## Raising instead of routing: `with_wait!`

`with_wait!/3` is identical except that a `<~` clause that times out raises a
`WaitForIt.TimeoutError`. An `else` block is still honored for ordinary `<-` non-matches.

```elixir
{:ok, balance} =
  with_wait! on(
    {:ok, account} <~ load_account(token),
    {:ok, balance} <~ fetch_balance(account)
  ), timeout: 2_000 do
    {:ok, balance}
  end
```

## Observability

Each `<~` clause runs as its own wait, so it emits the standard
`[:wait_for_it, :wait, :start | :stop | :exception]` telemetry events. See the
[Telemetry guide](telemetry.md).
