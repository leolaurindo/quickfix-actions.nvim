# Changelog

All notable changes to this project are documented in this file.

## [0.3.0] - 2026-09-24

### Added

- Vertical layout, width, and optional wrapping controls for `open()`, also available through `toggle()` and `open_history()`.
- Changed-tick-aware `append()`, `add_file()`, and `choose_history()` APIs, plus commands for adding files and ranges to the current or a selected quickfix list.
- `set_text()` and `:QuickfixActionsSetText` for changing an entry's message in the native list.

### Changed

- File and range additions leave item text empty by default instead of duplicating the path.
- Add commands accept an optional trailing quickfix list ID, defaulting to the current quickfix list; explicit file ranges use `start:end`.
- Removed the redundant `:QuickfixActionsOpen` and `:QuickfixActionsClose` commands; the Lua APIs remain available.

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
