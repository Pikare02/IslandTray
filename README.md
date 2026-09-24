<p align="center">
  <img src="docs/icon.png" width="220" alt="IslandTray app icon">
</p>

<h1 align="center">IslandTray</h1>

<p align="center">
  <a href="https://pikare02.github.io/IslandTray/"><img src="https://img.shields.io/badge/Install_on_iPhone-1d6f86?style=for-the-badge&logo=apple&logoColor=white" alt="Install on iPhone"></a>
  <a href="https://github.com/Pikare02/IslandTray/releases/latest"><img src="https://img.shields.io/github/v/release/Pikare02/IslandTray?style=for-the-badge&color=13161c" alt="Latest release"></a>
</p>

**English** · [日本語](README.ja.md)

A shelf for files, photos and copied text on iPhone and iPad, with the Dynamic
Island as its handle. Drop things in while you work, see them in the island
from any app, and drag them out where they are needed.

## Features

- **Tray** — drag in files, photos, videos and text from any app. Items are
  copied into the app, so the tray keeps them even after the source moves on.
- **Dynamic Island / Live Activity** — the island shows how many items are
  waiting, with small thumbnails and filenames, and pages through them with
  buttons. Tapping it opens the tray.
- **Drag out** — drag a card into another app. Pick one up and tap others with
  a second finger to carry several at once, the way Photos and Files work.
- **Clipboard board** — keep what you copy instead of losing it to the next
  copy. Formatted text keeps its formatting for apps that support it and pastes
  as plain text everywhere else.
- **Share sheet** — send anything to the tray from another app's share sheet
  (a share extension on paid accounts, a ready-made shortcut on free ones).
- **Save to Files inbox** — anything saved to *On My iPhone → IslandTray* in
  Files is taken into the tray the next time the app opens.
- **Organise** — search across both boards, filter by kind, sort by name, date
  or size, group by kind, and switch between a grid and a list.
- **Remove** — swipe a row left to delete it (a full swipe deletes at once),
  select several to share or delete, or have items leave the tray once taken
  (cut instead of copy).
- **English and Japanese**, light/dark theme and a highlight colour of your own.
- **App Drawer (Labs, off by default)** — a full-screen page of shortcuts under
  the tray, with an empty-state clock and weather. Off, nothing changes. On,
  add entries for an installed app, a Shortcuts shortcut, a URL scheme, or a
  web link; picking an installed app is TrollStore-only, the other three kinds
  work on both builds. Each entry can take a custom icon, and the drawer can
  have its own background image. The empty state shows the date and, if you
  allow location, current weather from [Open-Meteo](https://open-meteo.com/)
  for wherever you are — or pick a region by hand instead of sharing location.

## Release notes

Each version's full notes, with its `.ipa` files, are on its GitHub release page. Everything is also in the [changelog](CHANGELOG.md).

| Version | Highlights |
|---|---|
| [1.7.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.7.0) | App Drawer (Labs): a full-screen drawer of shortcuts under the tray, with a clock-and-weather empty state |
| [1.6.2](https://github.com/Pikare02/IslandTray/releases/tag/v1.6.2) | iCloud Sync reflects another device's changes sooner |
| [1.6.1](https://github.com/Pikare02/IslandTray/releases/tag/v1.6.1) | Clearer setup guide; Status sits right after Appearance |
| [1.6.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.6.0) | iCloud Sync becomes a regular feature; settings reordered |
| [1.5.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.5.0) | New setting to keep reminding about important updates; dragging out of the clipboard board never removes the item |
| [1.4.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.4.0) | Dynamic Island feedback replaces the "Added" dialog; search reads inside items (text and image OCR); shortcuts remember "Always Allow" |
| [1.3.1](https://github.com/Pikare02/IslandTray/releases/tag/v1.3.1) | Folders come in more reliably and through the share-sheet shortcut; failed drops say why |
| [1.3.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.3.0) | Folders go into the tray and come out as folders |
| [1.2.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.2.0) | Copy from the clipboard board (tap the name, swipe right, or long-press); the island follows the share-sheet shortcut at once |
| [1.1.5](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.5) | The two shortcuts are back (1.1.4 shipped without them) |
| [1.1.4](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.4) | Removing from the tray and deleting the original are separate settings; drags out are always a copy |
| [1.1.3](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.3) | The install page moves to GitHub Pages |
| [1.1.2](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.2) | Files of an unknown type (`.ipa`) can be dragged into Files |
| [1.1.1](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.1) | The update popup can skip a version |
| [1.1.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.1.0) | Checks for a newer release on launch; copy, not cut, by default |
| [1.0.0](https://github.com/Pikare02/IslandTray/releases/tag/v1.0.0) | First release |

## Requirements

- iOS / iPadOS 17.0 or later
- To build: macOS with Xcode (Swift 6) and [XcodeGen](https://github.com/yonaskolb/XcodeGen)

## Getting started

```bash
brew install xcodegen
xcodegen generate
open IslandTray.xcodeproj
```

The Xcode project is generated from [`project.yml`](project.yml) and is not
checked in. Run the `IslandTray` scheme for a normal build, or
`IslandTray (Free)` to try the free-account setup (no App Group).

To build sideloadable `.ipa` files instead, see [docs/INSTALL.md](docs/INSTALL.md).

## Tests

```bash
xcodebuild test -project IslandTray.xcodeproj -scheme IslandTray \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Project layout

| Path | What it is |
|------|------------|
| `Sources/App` | The app: boards, drag in/out, App Intents for Shortcuts |
| `Sources/Widget` | The Live Activity shown in the Dynamic Island |
| `Sources/Share` | The share extension (needs an App Group) |
| `Sources/Shared` | Storage, ordering and filtering shared by all targets |
| `Resources/Shortcuts` | The signed shortcuts the app offers to install |
| `scripts/` | `make-ipa.sh`, `make-shortcuts.py`, `make-icon.swift` |
| `Tests/` | Unit tests |
| `docs/superpowers/` | Design spec and implementation plans (Japanese, development records) |

## Documentation

- [Changelog](CHANGELOG.md)
- [Install page (download the latest .ipa on your iPhone)](https://pikare02.github.io/IslandTray/)
- [Installing and building the .ipa](docs/INSTALL.md)
- [Shortcuts: share sheet, clipboard and keeping the island up](docs/SHORTCUTS.md)
