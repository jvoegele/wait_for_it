# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## Unreleased
### Added
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
- Added guides (Waiting in tests, Polling vs signaling, Telemetry, Recipes) and a rewritten README.
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

[Unreleased]: https://github.com/jvoegele/wait_for_it/compare/v1.1.0...HEAD
[1.1.1]: https://github.com/jvoegele/wait_for_it/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/jvoegele/wait_for_it/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/jvoegele/wait_for_it/compare/init...v1.0.0
