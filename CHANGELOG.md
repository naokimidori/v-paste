# Changelog

All notable changes to V-Paste will be documented in this file.

The project follows semantic versioning for public releases.

## [1.2.0] - 2026-06-03

### Changed

- Split the history panel and card implementation into smaller responsibility-focused files.
- Split large history panel tests into focused support, view model, menu/settings, and test helper files.
- Improved history panel presentation on multi-display setups so the panel opens on the active display instead of drifting from another screen.
- Reworked the panel presentation animation to keep the window fixed at the current screen bottom while sliding clipped content inside the panel.
- Optimized the slide animation with a layer transform path for smoother presentation.

### Fixed

- Fixed cross-display panel transition artifacts when opening from a secondary display.
- Fixed the visual mismatch where the fallback presentation looked like a fade instead of a bottom slide.

## [1.1.0] - 2026-05-29

### Added

- Added a single-select type filter for All, Images, Text, Links, and Files in the history panel.
- Added a redesigned Preferences About tab with centered app identity, version text, and an icon-only GitHub action.

### Changed

- Refreshed the app icon, menu bar icon, and README brand logo.
- Simplified About menu copy to a single About item with the version shown inline.
- Normalized version display so release builds show the marketing version and local debug builds append `-dev`.

### Fixed

- Kept the type filter menu anchored below the selected control while preserving the existing panel presentation.
- Suppressed the macOS standard About panel build suffix.

## [1.0.1] - 2026-05-10

### Added

- Added an expanded About menu with the app version and a GitHub repository link.
- Added English and Simplified Chinese localization across the panel, cards, groups, empty states, and menus.

### Fixed

- Fixed copying from cards while search is active.
- Fixed Preferences tab switching stability and reduced excess bottom whitespace.

## [1.0.0] - 2026-05-06

### Added

- Initial open-source baseline.
- Local-first macOS clipboard history app.
- Menu bar controller and floating history panel.
- Text, URL, file, and image clipboard capture.
- SQLite persistence, groups, favorites, search, and retention controls.
- Settings panel, launch-at-login support, and configurable show-panel shortcut.
- XCTest coverage for domain, persistence, clipboard normalization, write-back, and panel view model behavior.
