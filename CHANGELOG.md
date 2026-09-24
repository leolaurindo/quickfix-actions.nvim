# Changelog

All notable changes to this project are documented in this file.

## [0.4.0] - 2026-09-24

### Added

- Positional quickfix and location-list layouts (`top`, `left`, `right`, and `bottom`) and a full-tab layout that preserves the existing window layout.
- `:QuickfixActionsLayout` and `:QuickfixActionsLayoutToggle` for setting and cycling list layouts.
- Configurable initial layout and per-list runtime layout memory for `:QuickfixActionsToggle`.

### Changed

- Preserved the existing `vertical = true` Lua API and horizontal/vertical layout aliases.

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
