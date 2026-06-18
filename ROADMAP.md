# WaitForIt Modernization & Enhancement Roadmap

> Status: proposed plan (June 2026). This document is the working plan for modernizing
> WaitForIt and improving developer experience. It is intended to be edited as decisions
> are refined and phases are completed.

## Guiding principles

1. **App-developer joy first.** Every change is judged by how it feels to the person
   `import WaitForIt`-ing into their app or test suite. Familiar syntax, predictable
   behavior, great error messages, great docs.
2. **Additive 2.x, then a clean 3.0.** All non-breaking improvements ship in the 2.x line.
   Anything that changes existing behavior (timeout semantics, option renames, removing
   `WaitForIt.V1`) is deferred to 3.0 and gated behind deprecation warnings first.
3. **Don't reinvent control flow.** WaitForIt's whole appeal is that it looks like Elixir
   (`if`/`case`/`cond`/`with`). New constructs must keep that property.
4. **Production-grade, not just test-grade.** Telemetry, backoff, and monotonic timing make
   it safe to reach for in running systems, not only in tests.

## Versioning summary

| Version | Theme | Breaking? |
|---------|-------|-----------|
| 2.2 | Foundation + DX quick wins (monotonic fix, loop unification, `match_wait` docs, `:interval` alias, CI, README) | No |
| 2.3 | Telemetry + backoff | No |
| 2.4 | ExUnit helpers (`assert_eventually` & friends) | No |
| 2.5 | `with_wait` composability construct | No |
| 3.0 | Unify timeout semantics, remove `WaitForIt.V1`, optional functional API | Yes |

---

## Phase 0 — Foundation & modernization (2.2, non-breaking)

Low-risk correctness and tooling work that everything else builds on.

### 0.1 Fix monotonic-time bug in the signal loop
`WaitForIt.Waiting.wait_for_signal/3` derives remaining time from `System.system_time/1`
(wall clock). A clock adjustment (NTP, leap, container migration) mid-wait can skew or
break the timeout. Switch to `System.monotonic_time/1`.

### 0.2 Unify the polling and signaling wait loops
Today polling spawns a per-wait "time bomb" `Task` that sleeps and sends a timeout message,
while signaling uses `receive`-after math. The `# TODO` in `waiting.ex` already proposes
unifying them. Plan:

- Compute `deadline = monotonic_now() + timeout` **once** at loop entry.
- Each iteration: `evaluate` → `{:halt, v}` returns; `{:cont, v}` computes
  `remaining = deadline - monotonic_now()`; if `remaining <= 0`, time out.
- Polling: block in `receive ... after min(remaining, interval)` (no signal expected → always
  ticks). Signaling: block in `receive {:signal} ... after remaining`.
- Net effect: one code path, no extra process per wait, no `Task` to kill, correct timing.

This also positions us for backoff (0.3 is just "make the interval vary per attempt").

### 0.3 Tooling & hygiene
- Bump dev deps: `ex_doc` (~> 0.38), `stream_data` (fixes the `register_test/4`
  deprecation warning), `credo`, `dialyxir`.
- Add **GitHub Actions CI**: matrix over a couple of Elixir/OTP versions; run
  `mix test`, `mix format --check-formatted`, `mix credo --strict`, `mix dialyzer`.
- Populate `.formatter.exs` `locals_without_parens` so paren-free usage formats cleanly:
  `wait: 1, wait: 2, wait!: 1, wait!: 2, case_wait: 2, case_wait: 3, cond_wait: 1,
  cond_wait: 2, match_wait: 2, match_wait: 3, signal: 1` (and bang variants).
- Decide on a minimum Elixir version (currently `~> 1.15`; keep unless a feature forces a bump).

---

## Phase 1 — DX quick wins (2.2, non-breaking)

### 1.1 Promote and document `match_wait`
`match_wait/3` already exists, is tested, and is genuinely useful (wait until an expression
matches a pattern *and* bind out of it). It is currently `@doc false`. Plan:

- Remove `@doc false`, write full `@doc` with examples, add `@doc section: :match_wait`,
  add a `match_wait!/3` bang variant for symmetry, add it to the docs groups and README.
- Example to feature:
  ```elixir
  {:ok, user} = match_wait({:ok, %User{}}, Repo.get(User, id), timeout: 2_000)
  ```

### 1.2 `:interval` as the preferred name for `:frequency`
The moduledoc itself admits `:frequency` is a misnomer (it's an interval in ms, not a rate).

- Accept `:interval` everywhere; keep `:frequency` as a documented alias.
- If both are given, `:interval` wins (and emit a warning).
- Defer *removing* `:frequency` to 3.0.

### 1.3 Document the timeout-behavior matrix
The single most confusing thing for newcomers is that the forms differ on timeout. Make it
explicit in the moduledoc as a table:

| Construct | On timeout (no `else`) | On timeout (with `else`) | Bang variant |
|-----------|------------------------|--------------------------|--------------|
| `wait` | returns last falsy value | n/a | raises `TimeoutError` |
| `case_wait` | raises `CaseClauseError` | evaluates `else` | raises `TimeoutError` |
| `cond_wait` | raises `CondClauseError` | evaluates `else` | raises `TimeoutError` |
| `match_wait` | raises `MatchError` | n/a (no `else`) | raises `TimeoutError` |

(Whether to *unify* these is a 3.0 question — see Phase 5. For 2.x we document clearly.)

### 1.4 README + guides overhaul
The README is a stub. Replace with motivating examples and link to ExDoc guides. Add
`guides/` (wired into `mix.exs` `docs: [extras: ...]`):
- `guides/waiting_in_tests.md`
- `guides/polling_vs_signaling.md`
- `guides/composing_waits.md` (lands with `with_wait`)
- `guides/recipes.md` (wait for DB record, wait for process/registry, poll an HTTP endpoint,
  producer/consumer backpressure).

---

## Phase 2 — Telemetry & backoff (2.3, non-breaking)

### 2.1 Telemetry
Add `:telemetry` as a dependency and instrument each wait with `:telemetry.span/3`:

- `[:wait_for_it, :wait, :start]` — measurements `%{system_time, monotonic_time}`;
  metadata `%{wait_type, signal, timeout, interval, env}`.
- `[:wait_for_it, :wait, :stop]` — measurements `%{duration, evaluations}`;
  metadata `%{wait_type, result: :matched | :timeout, last_value}`.
- `[:wait_for_it, :wait, :exception]` — for crashes during evaluation.

Track an `evaluations` counter in the loop so users can see how many polls a wait took.
A `guides/telemetry.md` shows wiring it into `:telemetry_metrics`. Keep overhead near-zero
when no handlers are attached (which `:telemetry` already guarantees).

### 2.2 Backoff
Generalize the interval so production waits can ease off a struggling dependency.

- `:interval` accepts either an integer (constant, current behavior, default `100`) or a
  1-arity function `(attempt :: pos_integer -> non_neg_integer)`.
- Provide a `WaitForIt.Backoff` module with builders:
  - `WaitForIt.Backoff.constant(ms)`
  - `WaitForIt.Backoff.exponential(start: 50, max: 2_000, factor: 2, jitter: 0.1)`
- Backoff is independent of timeout: the deadline (Phase 0.2) still bounds total wait;
  each sleep is `min(remaining, backoff(attempt))`.

Example:
```elixir
wait(Repo.get(Post, id),
  timeout: :timer.seconds(30),
  interval: WaitForIt.Backoff.exponential(start: 50, max: 1_000))
```

---

## Phase 3 — ExUnit helpers (2.4, non-breaking)

The #1 use case is async assertions in tests, but there's no test-specific sugar today.
This phase is the one most likely to make people *love* the library.

New module `WaitForIt.ExUnit` (used via `import WaitForIt.ExUnit` or `use WaitForIt.ExUnit`):

```elixir
# Poll the assertion until it passes or the timeout elapses.
assert_eventually Repo.get(User, id).confirmed == true, timeout: 2_000

# Pattern-binding form (binds on success, usable after the call):
assert_eventually {:ok, user} = fetch_user(id)

# Inverse: assertion must hold for the whole window (stays true).
assert_always queue_size() < 100, timeout: 500
```

- On timeout, raise `ExUnit.AssertionError` (not `TimeoutError`) with a message that includes
  the **source expression** and the **last evaluated value** — so failures read like normal
  ExUnit failures, not library internals.
- Implemented on top of the existing `Waitable` machinery; `assert_eventually` is essentially
  `wait!`/`match_wait!` with an ExUnit-flavored timeout handler.
- `refute_eventually` for symmetry (asserts it never becomes truthy within the window).
- `guides/waiting_in_tests.md` becomes the showcase.

Open question to confirm during design: exact names (`assert_eventually` vs
`assert_eventually!`), and whether `assert_always`/`refute_eventually` ship in the same release.

---

## Phase 4 — `with_wait` composability (2.5, non-breaking)

Finish the flagship construct from the `feature/with_wait` branch: compose multiple waits in
a `with`-style pipeline, mixing ordinary matches with waiting matches.

### Syntax
```elixir
with_wait on(
  {:ok, token}  <-  authenticate(user),                                  # normal: evaluated once
  {:ok, account} <~ {load_account(token), timeout: 2_000},               # wait until it matches
  {:ok, balance} <~ fetch_balance(account)                               # wait with default opts
) do
  {:ok, balance}
else
  {:error, reason} -> {:error, reason}
end
```

- `<-` — a normal `with` clause, evaluated once (no waiting).
- `<~` — a **wait-for-match** clause: re-evaluate the right side until it matches the pattern,
  bounded by per-clause options `<~ {expr, opts}` or global defaults.
- `on(...)` is a syntactic wrapper so the macro receives all clauses as a single AST node
  (Elixir's `with`-style clause syntax is special-cased to the built-in `with`; a variadic
  macro isn't possible, so the wrapper is the pragmatic approach). Naming of `on` is open —
  alternatives noted below.

### Semantics & key design decisions
- Each `<~ pattern <- expr` desugars to a `match_wait`-style wait that, **on timeout, yields
  its last (non-matching) value** rather than raising. That value flows into the generated
  `<-` clause, fails to match, and transfers control to `else` — exactly like a normal `with`
  clause that didn't match. This makes timeout behavior compose naturally with `with/else`
  instead of escaping as an exception.
- **Fix the branch's gap:** the WIP currently maps a `<~` clause *without* explicit opts to a
  plain `<-` (so it doesn't wait). Correct behavior: a `<~` clause always waits, using global
  defaults when no per-clause opts are given.
- Global options (timeout/interval/signal/backoff) passed to `with_wait` apply to every `<~`
  clause unless overridden per-clause.
- Strip the debug `IO.inspect`/`IO.puts` left in the branch; add real tests (the branch's test
  is commented out).

### Deliverables
- Completed `WaitForIt.Waitable.WithWait` impl + `Evaluation.capture_with_clauses/eval_with_clauses`.
- `with_wait!` bang variant.
- `guides/composing_waits.md`.

---

## Phase 5 — 3.0 considerations (breaking, later)

Collected here so we don't lose them; sequenced after the 2.x line lands.

- **Unify timeout semantics.** Decide whether `case_wait`/`cond_wait`/`match_wait` should stop
  raising `CaseClauseError`/`CondClauseError`/`MatchError` on timeout by default in favor of a
  consistent model (e.g. always `else`-or-`TimeoutError`). This is the main breaking change
  worth a major version.
- **Remove `WaitForIt.V1`.** In 2.x, add `@deprecated` warnings to every `V1` macro pointing at
  the V2 equivalent (and stop starting its `ConditionVariable` supervisor/registry once nothing
  uses it). Remove the module and its `Application` children in 3.0.
- **Optional functional API.** A non-macro entry point for dynamic cases:
  `WaitForIt.until(fn -> ... end, opts)` returning `{:ok, value} | {:timeout, last_value}`.
  Useful when the condition is computed at runtime and a macro is awkward. Evaluate demand
  before committing.
- **Reconsider `:frequency` removal** (kept as deprecated alias since 2.2).

---

## Immediate next actions (Phase 0 + early Phase 1)

1. Monotonic-time fix + loop unification in `WaitForIt.Waiting`, with tests asserting no
   regression in polling/signaling/timeout behavior.
2. Dep bumps + GitHub Actions CI + `.formatter.exs` `locals_without_parens`.
3. Document & expose `match_wait` (+ `match_wait!`), `:interval` alias, timeout matrix.
4. README rewrite + `guides/` scaffolding wired into ExDoc.
5. Add `@deprecated` warnings to `WaitForIt.V1` macros.
