# Changelog

All notable changes to this project are documented in this file.

## [0.2.0] - 2026-09-22

### Added

- Native quickfix and location-list history browser via `:QuickfixActionsHistory [quickfix|location]`.
- `history()` and `open_history()` Lua APIs for inspecting and opening history.
- Location-list history scoped to its owning window.

### Changed

- History browsers are reused per scope and excluded from their own rows.

## [0.1.0]

### Added

- Initial release.
