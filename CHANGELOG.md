# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## 2.0.0 - 2023-11-02
### Changed
- Much improved documentation
- Breaking change to return value of `WaitForIt.wait/2`, `WaitForIt.case_wait/3`, and `WaitForIt.cond_wait/2`
- Rewrite of WaitForIt internals
- Moved legacy code to `WaitForIt.V1`

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
