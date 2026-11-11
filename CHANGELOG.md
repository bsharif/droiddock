# Changelog

All notable changes to DroidDock are in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-11-11

First public release.

### Added
- Native SwiftUI window with a Finder-style sidebar, sortable file table, back and forward,
  search, status bar, and light and dark mode.
- Rust engine (`droiddock-engine`) that runs adb and returns JSON.
- Copy phone files and folders to the Mac. Double-click a file to copy and open it.
- Send Mac files and folders to the phone with drag and drop or **Send to Phone…**.
- Photo thumbnails from the JPEG built-in preview (reads about 64 KB per photo), with a
  memory and disk cache. PNG, HEIC, WebP and GIF files up to 8 MB are read whole.
- Phone picker at startup: USB phones, phones found on Wi-Fi (mDNS), recent addresses,
  connect by address, and pairing with a code (Android Wireless debugging).
- Classic Wi-Fi adb (port 5555) for a USB phone, with a warning that it is not encrypted,
  an **Unencrypted** label, and a **Turn Off** button.
- Settings: save folder, phone picker at startup, photo thumbnails.
- Menu commands and keyboard shortcuts.

[Unreleased]: https://github.com/bsharif/droiddock/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/bsharif/droiddock/releases/tag/v0.1.0
