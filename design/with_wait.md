# Design: `with_wait` (Phase 4)

> Status: proposed design for review. Grounded in Elixir behavior verified against
> Elixir 1.17 / OTP 27 (parsing of `<~`, `with` guard support, `with`/`else` semantics,
> middle-default macro arity, `unquote_splicing` into `with`).

## 1. Goal

Compose several waits into a single `with`-style pipeline, where some clauses must *wait* for a
condition and others are ordinary one-shot matches, and where a failure (a non-match or a
timeout) short-circuits to an `else` block — exactly like `with/1`, but with waiting.

This is the flagship composability feature. Today, composing N waits means nesting `case_wait`
or chaining `match_wait` calls by hand, with no shared failure path. `with_wait` makes it read
like the `with` you'd already write.

## 2. Surface syntax

```elixir
with_wait on(
  {:ok, token}   <-  authenticate(user),                    # one-shot match (no waiting)
  {:ok, account} <~  {load_account(token), timeout: 2_000}, # wait, with per-clause options
  {:ok, balance} <~  fetch_balance(account)                 # wait, with default/global options
), interval: 50 do
  {:ok, balance}
else
  {:error, reason} -> {:error, reason}
  still_pending    -> {:still_waiting, still_pending}
end
```

- `<-` — an ordinary `with` clause: evaluated **once**. If it matches, bind and continue;
  otherwise route to `else`. Standard `with` semantics, unchanged.
- `<~` — a **wait-for-match** clause: re-evaluate the right-hand side until it matches the
  pattern, then bind and continue. On timeout, behave like a `<-` clause that didn't match
  (route to `else`).
- `on(...)` — a syntactic wrapper holding the clauses (see §3).
- Global options (`interval: 50` above) apply to every `<~` clause unless overridden per-clause.
- `do`/`else` — identical to `with`: `else` is a series of match clauses; success returns the
  `do` block's value.

### Bang variant

`with_wait!` is identical except that a `<~` clause that times out raises
`WaitForIt.TimeoutError` instead of routing to `else`. (`<-` non-matches still route to `else`.)

## 3. The `on(...)` wrapper

`with` gets its comma-separated clauses through dedicated parser support; a user macro cannot.
A macro has fixed arity, so `with_wait c1, c2, c3 do … end` (variadic) is impossible. Wrapping
the clauses in a single pseudo-call — `on(c1, c2, c3)` — gives the macro one AST node to
destructure:

```elixir
quote(do: on({:ok, x} <- a(), {:ok, y} <~ b()))
# => {:on, _, [ {:<-, _, [...]}, {:<~, _, [...]} ]}
```

`on` is **not** a real function — it is never defined or called; the `with_wait` macro pattern-
matches `{:on, _, clauses}` and discards the wrapper. Nothing named `on` is imported.

Global options sit between the wrapper and the block, which Elixir groups as a middle argument
(verified): `with_wait on(...), interval: 50 do … end` parses as
`with_wait(on(...), [interval: 50], [do: …, else: …])`. The macro is therefore:

```elixir
defmacro with_wait(clauses, opts \\ [], blocks)
```

A 2-arg call (`with_wait on(...) do … end`) gets `opts` defaulted to `[]`; a 3-arg call supplies
the options. (Middle-default arity resolution is verified.)

**Open question (naming):** `on` reads reasonably (`with_wait on(...)`). Alternatives:
`clauses(...)`, `all(...)`, `steps(...)`. Recommendation: keep `on`. See §12.

## 4. Clause kinds and options

| Clause form | Meaning |
| ----------- | ------- |
| `pattern <- expr` | ordinary `with` clause, evaluated once |
| `pattern <~ expr` | wait until `expr` matches `pattern`, using global/default options |
| `pattern <~ {expr, opts}` | wait, with per-clause `opts` merged over the global options |
| bare `expr` | passed through to `with` unchanged (executed once; `with` allows this) |

Per-clause options are recognized when the `<~` right-hand side is a 2-tuple whose second
element is a **literal keyword list** (`{expr, [timeout: …, …]}`). Anything else is treated as the
expression itself, so `coords <~ {get_x(), get_y()}` correctly waits for the *tuple* value (the
second element is a call, not a literal keyword list). The only ambiguous case is waiting for a
literal `{value, [key: val]}` tuple; the workaround is to bind the expression to a variable
first. This will be documented.

Options are the usual WaitForIt options (`:timeout`, `:interval`, `:pre_wait`, `:signal`, and
`WaitForIt.Backoff` interval functions). Per-clause options win over global options
(`Keyword.merge(global, clause)`).

### `<~` precedence caveat (important)

`<~` is a tightly-binding arrow operator — higher precedence than `when` and the comparison
operators. So these **mis-parse**:

```elixir
{:ok, n} when n > 5 <~ poll()     # parses as {:ok, n} when n > (5 <~ poll())
found <~ Enum.find(xs, f) != nil  # parses as (found <~ Enum.find(...)) != nil
```

Parentheses are the escape hatch (both verified to parse correctly):

```elixir
({:ok, n} when n > 5) <~ poll()
found <~ (Enum.find(xs, f) != nil)
```

The common cases need no parentheses: `{:ok, u} <~ fetch(id)` and
`{:ok, u} <~ {fetch(id), timeout: 100}`. The doc will call this out, and recommend `case_wait`
for waits dominated by a single complex/guarded condition (where `with_wait`'s value is
composition, not single-condition expressiveness).

## 5. Semantics

- **Success:** every clause matches (waiting as needed); the `do` block runs and its value is the
  result.
- **`<-` non-match:** routes to `else` with the non-matching value (standard `with`).
- **`<~` timeout (non-bang):** the wait returns the last (non-matching) value, which the desugared
  `with` clause then fails to match — routing to `else` with that last value, exactly like a
  `<-` non-match. A timeout is therefore *indistinguishable from a non-match* in `else`, which is
  the property that makes the construct compose cleanly.
- **No `else`:** a non-match/timeout makes the whole `with_wait` return the non-matching/last
  value (standard `with`).
- **`else` present but no else-clause matches:** raises `WithClauseError` (inherited from `with`).
- **Guards:** supported via parentheses (§4); `with` evaluates the guard and routes guard-
  failures to `else` (verified).
- **Bang:** a `<~` timeout raises `WaitForIt.TimeoutError`; `<-` non-matches still route to `else`.

## 6. Desugaring

`with_wait` is a **compile-time transformation into a real `with`** — no `with_wait` runtime
construct, no dedicated `Waitable`. Each `<~` clause becomes a `<-` clause whose right side is a
soft wait; every other clause passes through untouched. The `with`'s own machinery then provides
binding, `else` routing, and `WithClauseError`.

The example from §2 expands (conceptually) to:

```elixir
with {:ok, token} <- authenticate(user),
     {:ok, account} <-
       WaitForIt.__wait_clause__(
         {:ok, account},
         load_account(token),
         Keyword.merge([interval: 50], timeout: 2_000)
       ),
     {:ok, balance} <-
       WaitForIt.__wait_clause__(
         {:ok, balance},
         fetch_balance(account),
         Keyword.merge([interval: 50], [])
       ) do
  {:ok, balance}
else
  {:error, reason} -> {:error, reason}
  still_pending -> {:still_waiting, still_pending}
end
```

The clause list is built with `unquote_splicing` into a quoted `with` (verified to work):

```elixir
quote do
  with unquote_splicing(compiled_clauses) do
    unquote(do_block)
  else
    unquote(else_clauses)   # omitted entirely when there is no else
  end
end
```

Clause compilation:

```
compile(pattern <- expr)         => pattern <- expr                          # unchanged
compile(pattern <~ expr)         => pattern <- __wait_clause__(pattern, expr, global)
compile(pattern <~ {expr, opts}) => pattern <- __wait_clause__(pattern, expr, merge(global, opts))
compile(other)                   => other                                    # unchanged (bare expr, etc.)
```

This fixes the WIP-branch bug where an option-less `<~` clause was turned into a plain `<-`
(and therefore did **not** wait): in this design every `<~` clause waits, defaulting to the
global/default options when none are given per-clause.

## 7. The soft clause-wait primitive

`__wait_clause__/3` is a `@doc false` macro that performs a `match_wait` whose timeout *returns
the last value* instead of raising:

```elixir
defmacro __wait_clause__(pattern, expr, opts) do
  quote do
    require WaitForIt.Waitable.MatchWait

    waitable =
      WaitForIt.Waitable.MatchWait.create(
        unquote(ignore_pattern_bindings(pattern)),  # see below
        unquote(expr)
      )

    WaitForIt.Waiting.wait(
      waitable,
      Keyword.put(unquote(opts), :on_timeout, :return_last_value),
      __ENV__
    )
  end
end
```

Two small supporting changes:

1. **`WaitForIt.Waiting`** gains an `:on_timeout` mode `:return_last_value` that returns the last
   evaluated value rather than calling `handle_timeout` (which, for `MatchWait`, raises
   `MatchError`). The existing `:raise` mode is reused by `with_wait!`. This is a one-branch
   addition to the existing `on_timeout/4`.

2. **`ignore_pattern_bindings/1`** (the variable→`_`, pins-preserved transform already written for
   `WaitForIt.Test`) is reused so that the `MatchWait` match test does not emit spurious "unused
   variable" warnings for pattern variables that are bound by the *outer* `<-`. It will be
   extracted to a shared internal helper (e.g. `WaitForIt.Evaluation`) and used by both
   `WaitForIt.Test` and the `with_wait` desugaring.

For `with_wait!`, the desugaring emits a bang clause-wait that passes `on_timeout: :raise`, so a
timeout raises `WaitForIt.TimeoutError`.

## 8. Telemetry

Each `<~` clause runs through `WaitForIt.Waiting.wait`, so it emits the standard
`[:wait_for_it, :wait, :start | :stop | :exception]` events with `wait_type: :match_wait`. This
gives per-clause observability for free.

Possible future enhancement (not in v1): tag clause waits with a `:with_wait` context in metadata
so they can be distinguished from standalone `match_wait`s. Noted, deferred.

## 9. Errors and validation

- Missing wrapper (`with_wait foo do … end` where `foo` is not `on(...)`): raise a `CompileError`
  with a clear message ("the clauses of with_wait must be wrapped in on(...)").
- Unknown/garbage clause shapes pass through to `with`, which reports its own compile error — we
  lean on `with`'s validation rather than re-implementing it.
- `with_wait` with no `<~` clauses is allowed (it is just a `with`); no special-casing.

## 10. Implementation plan

1. `WaitForIt.Waiting`: add the `:return_last_value` `on_timeout` mode (one branch + a test).
2. Extract `ignore_pattern_bindings/1` to a shared internal module; point `WaitForIt.Test` at it.
3. Add `WaitForIt.__wait_clause__/3` (and a bang form) `@doc false` macros.
4. Add `with_wait/2,3` and `with_wait!/2,3` public macros + a compile-time clause compiler
   (private helper module, e.g. `WaitForIt.WithWait`, or private functions in `WaitForIt`).
5. Remove the dead experimental scaffolding: the unused `WaitForIt.Waitable.WithWait` waitable and
   the unused `capture_with_clauses` in `WaitForIt.Evaluation` (this design supersedes them).
6. Docs: a moduledoc section + `@doc` for `with_wait`/`with_wait!`, a `groups_for_docs` section,
   `guides/composing_waits.md`, README mention, CHANGELOG, `.formatter.exs` entries
   (`with_wait`, `with_wait!`), and the `:with_wait` `wait_type` in the timeout-behavior matrix.

## 11. Testing plan

- Success path: all `<-`/`<~` clauses match (with a counter-driven `<~` that becomes ready).
- `<~` waits: a clause that is initially non-matching becomes matching within the timeout.
- Per-clause options override global options (e.g. a short per-clause timeout that fires while
  the global is long).
- `<~` timeout routes to `else` with the last value; and without `else` returns the last value.
- `<-` non-match routes to `else`.
- Guard via parentheses works (match and guard-failure-to-`else`).
- `with_wait!`: `<~` timeout raises `WaitForIt.TimeoutError`.
- No spurious "unused variable" warnings for bound pattern variables (compile-clean assertion,
  as we do elsewhere).
- Per-clause `:signal`.
- Telemetry emitted per `<~` clause.

## 12. Decisions (confirmed)

1. **`<~` timeout semantics — flow to `else`.** A `<~` timeout returns the last non-matching value,
   which the desugared `with` routes to `else` (or returns when there is no `else`). Timeouts are
   indistinguishable from non-matches. (Diverges from the WIP branch, which raised.)
2. **Wrapper keyword — keep `on(...)`.**
3. **Guards — parentheses, documented.** `({:ok, n} when n > 5) <~ poll()`; `case_wait` is the
   pointer for waits dominated by a single complex/guarded condition.
4. **`else` style — `with`-style match clauses only** (for `with` fidelity), not a bare `else`
   expression.
5. **Bang + `else`** — `with_wait!` still allows `else` (handling `<-` non-matches) while `<~`
   timeouts raise `WaitForIt.TimeoutError`.
