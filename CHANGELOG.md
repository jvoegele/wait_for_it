# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## 2.5.0 - 2026-08-25
### Added
- Elixir 1.19 and 1.20 to the CI matrix, which now spans the declared floor (`~> 1.15`) through the
  current release. The two most recent Elixir versions — the ones most adopters run — were
  previously untested, and the set-theoretic type checker is exactly the kind of moving target a
  macro-heavy library needs coverage against. The `lint` flag moved to the newest entry so
  formatting and Credo run against current tooling, and the Dialyzer job now matches
  `.tool-versions` instead of trailing the matrix by two releases.
  [(Issue #23)](https://github.com/jvoegele/wait_for_it/issues/23)
- A [Troubleshooting](guides/troubleshooting.md) guide, opening with "Why does the compiler say my
  pattern will never match?"
  [(Issue #24)](https://github.com/jvoegele/wait_for_it/issues/24)
- **`usage-rules.md`, shipped in the package** — WaitForIt's guidance condensed for AI coding
  agents, in the layout [`usage_rules`](https://hex.pm/packages/usage_rules) syncs from. A
  consumer can pull it into their `AGENTS.md` with `mix usage_rules.sync`, or read it directly at
  `deps/wait_for_it/usage-rules.md`.

  It leads with the one rule — on timeout each form behaves as its native counterpart would on a
  final non-matching evaluation — and then the traps that are easy to get wrong and silent when
  you do: a catch-all clause in `case_wait`/`cond_wait` disables the waiting entirely (measured:
  it halts after one evaluation in 4 ms), waiting blocks the calling process and must not happen
  inside a GenServer callback, signals are node-local, and `timeout: :infinity` removes all
  timeout behaviour rather than merely extending it.

### Changed
- **Telemetry metadata `env` is now a trimmed map rather than the caller's whole `Macro.Env`**
  ([Issue #22](https://github.com/jvoegele/wait_for_it/issues/22)). It carries exactly
  `:context`, `:context_modules`, `:file`, `:function`, `:line`, and `:module` — the same six
  fields `WaitForIt.TimeoutError` has always exposed. The two paths disagreed about what `env`
  meant; now they share one definition and cannot drift apart again.

  A full `__ENV__` measured **1019 words (~8 KB)** in a module with ordinary imports, of which
  most is the calling module's import table (`:functions`, `:macros`, `:requires`) — it grows
  with the caller's imports and is of no use to a handler. That term was embedded in the
  caller's compiled module once per wait, copied into the signal registry's ETS on every
  signal-based wait, and copied again by every handler that forwarded metadata off-process.

  The trim happens at **macro expansion**, so the fat term is never emitted rather than being
  discarded later. Measured on a module with three wait sites:

  | | before | after |
  |---|---|---|
  | `env` term | 1019 words | 29 words |
  | whole event metadata | 1039 words | 49 words |
  | caller's compiled beam | 12,612 bytes | 3,360 bytes |

  A handler reading anything outside those six keys needs updating; one reading `env.file` or
  `env.line` does not. The value passed down internally stays a real `%Macro.Env{}` so that
  `Macro.Env.stacktrace/1` still reraises a timed-out `match_wait`/`case_wait`/`cond_wait` at
  the caller's location — byte-for-byte the stacktrace it produced before.

### Fixed
- The test suite no longer emits "the following clause will never match" warnings on Elixir 1.20.
  These came from the suite's own stub helpers, not from the waiting macros: 1.20 infers an exact
  return type for a local function, so `defp pending, do: :pending` has the type `:pending`, and a
  wait for `{:ok, _}` on it genuinely cannot match. The helpers wanted a *runtime* non-match to
  drive the timeout paths, not a type-level one, so they now route through the process dictionary —
  same value, no inferable type.

  Characterised across waitable shapes before changing anything: the warning fires **only** when the
  expression's inferred type is disjoint from the pattern. A union that includes the pattern, an
  opaque value, a `@spec`'d `term()`, the `nil | struct` shape of `Repo.get/2`, and a tagged
  `{:ok, _} | {:error, _}` union are all clean, as are `wait/2` and `case_wait/3`. So no realistic
  waitable trips it, and when it does fire it is correct — waiting changes values over time, not
  types, and an expression whose type cannot produce the pattern can only ever time out.

  WaitForIt therefore does **not** suppress the diagnostic in its expansion. The mechanism that
  produces the surprising warning is the same one that catches a genuinely impossible pattern in
  user code; silencing it library-wide would trade a rare accurate warning for a permanent blind
  spot. The guide explains the diagnosis and the fix instead.
  [(Issue #24)](https://github.com/jvoegele/wait_for_it/issues/24)

## 2.4.0 - 2026-07-31
### Added
- The `:timeout` option now accepts `:infinity`, for a wait that continues until its condition is
  met rather than giving up after a fixed budget. Such a wait can never time out, so the `!`
  variants never raise, `else` clauses never run, and `WaitForIt.until/2` never returns
  `{:timeout, last_value}`.
  [(Issue #6)](https://github.com/jvoegele/wait_for_it/issues/6)
- Telemetry metadata now includes a `wait_context` key, which distinguishes a wait that was written
  directly (`nil`) from one a construct desugared to. A `<~` clause of a `with_wait` reports
  `%{construct: :with_wait, clause: index}`, so its events are no longer indistinguishable from a
  standalone `match_wait` and can be attributed to a specific clause.
  [(Issue #19)](https://github.com/jvoegele/wait_for_it/issues/19)

### Fixed
- Corrected the `t:WaitForIt.wait_opt/0` typespec, which declared `:interval` (and its `:frequency`
  alias) as an integer only, even though a `WaitForIt.Backoff` function has been accepted since
  2.2.0.

## 2.3.0 - 2026-07-31
### Added
- Added a functional (non-macro) waiting API, `WaitForIt.until/2` and `WaitForIt.until!/2`, for
  conditions that are computed at runtime or passed in as a function. `until/2` returns a tagged
  `{:ok, value}` or `{:timeout, last_value}` result; `until!/2` returns the bare value on success
  and raises `WaitForIt.TimeoutError` on timeout.

### Changed
- Clarified the "Timeout behavior" documentation to lead with the single underlying rule — on
  timeout, each waiting form behaves exactly as its native Elixir counterpart would on a final
  non-matching evaluation — and demoted the behavior matrix to a reference table (now with a
  native-counterpart column). Documentation only; no API or behavioral changes.

## 2.2.1 - 2026-06-18
### Changed
- Restructured the documentation so the README is the single source for the `WaitForIt` module
  documentation, removing the duplicated Overview page. Documentation only; no API or behavioral
  changes.

## 2.2.0 - 2026-06-18
### Added
- Added the `with_wait/3` and `with_wait!/3` macros for composing several waits in a `with`-style
  pipeline. Clauses use `<-` (ordinary one-shot match) or `<~` (wait-for-match, with optional
  per-clause options); a `<~` timeout flows to the `else` block like an ordinary non-match (or
  raises `WaitForIt.TimeoutError` for `with_wait!`). See the "Composing waits" guide.
- Added the `WaitForIt.Test` module with `assert_eventually/2` (truthy and pattern-binding
  forms), `refute_eventually/2`, and `assert_always/2` test assertions that fail with a regular
  `ExUnit.AssertionError` (including the source expression and last value) on timeout.
- Documented and promoted the `match_wait/3` construct, and added a `match_wait!/3` bang variant.
- Added the `:interval` option as the preferred name for the polling interval. `:frequency`
  continues to work as an alias and is slated for removal in a future major version.
- Added `:telemetry` events (`[:wait_for_it, :wait, :start | :stop | :exception]`) for every wait,
  exposing wait duration, evaluation count, and outcome.
- Added backoff support: the `:interval` option now accepts a 1-arity function of the attempt
  number, plus a new `WaitForIt.Backoff` module with `constant/1` and `exponential/1` strategies.
- Added guides (Waiting in tests, Polling vs signaling, Composing waits, Recipes, Telemetry) and a
  rewritten README.
- Added GitHub Actions CI (test matrix, formatting, Credo, Dialyzer).

### Changed
- Rewrote the internal wait loop to use a single monotonic deadline, making timeouts immune to
  wall-clock adjustments and unifying the polling and signaling code paths (the polling mode no
  longer spawns a helper process per wait).
- Deprecated the `WaitForIt.V1` macros; they now emit deprecation warnings pointing at the
  current `WaitForIt` API and will be removed in a future major version.
- Modernized dependencies (`ex_doc`, `stream_data`, `credo`).

## 2.1.0 - 2023--11-14
### Changed
- Further improved documentation.
- `WaitForIt.case_wait/3` will now raise a `CaseClauseError` on timeout if there is no `else` block.
- `WaitForIt.cond_wait/2` will now raise a `CondClauseError` on timeout if there is no `else` block.

## 2.0.0 - 2023-11-02
### Changed
- Much improved documentation.
- Breaking change to return value of `WaitForIt.wait/2`, `WaitForIt.case_wait/3`, and `WaitForIt.cond_wait/2`.
- Rewrite of WaitForIt internals.
- Moved legacy code to `WaitForIt.V1`.

## 1.4.0 - 2023-10-24
### Added
- Add WaitForIt.wait! macro.

## [1.3.0] - 2020-04-02
### Changed
- Use DynamicSupervisor to manage condition variables.

## [1.2.1] - 2019-03-14
### Added
- Add `:pre_wait` option to all forms of waiting.

## [1.2.0] - 2019-03-08
### Added
- Add support for match clauses in `else` block of `case_wait`. [(Issue #9)](https://github.com/jvoegele/wait_for_it/issues/9)

## [1.1.1] - 2018-03-03
### Added
- Add idle timeout feature for ConditionVariable.

## [1.1.0] - 2017-09-02
### Added
- Add support for `else` clause in `case_wait` and `cond_wait`. [(Issue #4)](https://github.com/jvoegele/wait_for_it/issues/4)
- Add this CHANGELOG

### Changed
- Use supervisor to manage condition variables. [(Issue #5)](https://github.com/jvoegele/wait_for_it/issues/5)

### Fixed
- Grammar fixes for README and @moduledoc. Thanks to @GregMefford for the fixes.
- Fix [unexpected messages from wait_for_it when used with Genserver](https://github.com/jvoegele/wait_for_it/issues/3)

## [1.0.0] - 2017-08-28
- Initial release supporting `wait`, `case_wait`, and `cond_wait` with either polling or condition variable signaling.

[2.5.0]: https://github.com/jvoegele/wait_for_it/compare/2.4.0...2.5.0
[2.4.0]: https://github.com/jvoegele/wait_for_it/compare/2.3.0...2.4.0
[2.3.0]: https://github.com/jvoegele/wait_for_it/compare/2.2.1...2.3.0
[2.2.1]: https://github.com/jvoegele/wait_for_it/compare/2.2.0...2.2.1
[2.2.0]: https://github.com/jvoegele/wait_for_it/compare/2.1.2...2.2.0
[1.1.1]: https://github.com/jvoegele/wait_for_it/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jvoegele/wait_for_it/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jvoegele/wait_for_it/compare/init...v1.0.0
