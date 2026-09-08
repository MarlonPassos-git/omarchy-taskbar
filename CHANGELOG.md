# Changelog

Notable changes to this project are documented here, with the newest version first.

This changelog uses the [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.
Version numbers follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

## 0.3.1

### Fixed

- Clicking a pinned icon repeatedly now really does cycle through
  that app's windows. Focusing a window makes Hyprland warp the pointer to the
  middle of it (`cursor:no_warps` defaults to `false`), which moved the pointer
  off the icon, so the second click landed on the window instead of the bar and
  cycling never got past the first window. The pointer is now put back where it
  was, so repeated clicks keep landing on the icon.

## 0.3.0

### Added

- Pin and unpin from the bar itself.
