# Troubleshooting

## Why does the compiler say my pattern will never match?

On Elixir 1.20 and later you may see this at a `match_wait`/`with_wait` call site:

```
warning: the following clause will never match:

    {:ok, _} ->

because it attempts to match on the result of:

    value

which has type:

    dynamic(:pending)
```

### What it means

The waiting macros expand to a closure that evaluates the waitable expression
once and tests the pattern against that value, re-running the closure until it
matches or the timeout expires. Elixir's set-theoretic type checker infers a type
for the expression and compares it to the pattern. When the two are disjoint it
reports the clause as unreachable.

**The warning is telling the truth.** It fires only when the expression's *type*
cannot produce the pattern — not merely when its current *value* doesn't. Waiting
changes values over time; it does not change types. If a function's return type is
the single atom `:pending`, no amount of re-evaluation will ever make it match
`{:ok, _}`, and the wait can only ever time out.

The usual cause is a stub or helper narrow enough for the compiler to pin down
exactly:

```elixir
defp pending, do: :pending          # inferred type: :pending

with_wait on({:ok, v} <~ pending()) do   # can never match — correctly flagged
  v
end
```

Real waitables are rarely this narrow. A function returning `{:ok, term} | {:error, term}`,
one whose value comes from a database or an HTTP call, or anything the checker
cannot narrow, all admit the pattern and produce no warning.

### What to do about it

**If the expression really is constant**, the warning has found a bug — the wait
cannot succeed. Fix the expression or the pattern.

**If you are writing a test stub** that should fail to match at *runtime* while
still being type-compatible, widen its return type so the checker cannot pin it
down. Routing through the process dictionary is the simplest way, and leaves the
returned value unchanged:

```elixir
# Before: inferred type is exactly `:pending`.
defp pending, do: :pending

# After: same value, but the checker sees `dynamic()`.
defp pending, do: Process.get(:__unset__, :pending)
```

This library's own test suite does exactly that; see `test/wait_for_it/with_wait_test.exs`.

**If the expression is genuinely dynamic** but the checker has narrowed it anyway
— for example, it is built from literals in the same module — either add a
`@spec` that widens the return type, or move the value behind a boundary the
checker does not see through.

### Why WaitForIt does not suppress the warning

It would be possible to route the match through something opaque inside the macro
expansion, so the diagnostic never appears. WaitForIt deliberately does not do
this. The same mechanism that produces the spurious-looking warning above is what
catches a genuinely impossible pattern in your own code — waiting forever for a
shape the expression cannot return. Silencing it library-wide would trade a rare,
accurate warning for a permanently blind spot, which is the worse deal.
