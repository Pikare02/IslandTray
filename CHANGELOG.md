# Changelog

**English** · [日本語](CHANGELOG.ja.md)

Versions follow [Semantic Versioning](https://semver.org): the last number for
fixes, the middle one for new features, the first for changes that break how
the app is used. The version is set once, in `project.yml`
(`MARKETING_VERSION`), and each release is tagged `vX.Y.Z` with its `.ipa`
files attached on GitHub.

## [1.1.1] — 2026-09-21

### App
- The update popup on launch gains *Don’t Show Again for This Version*; a
  later release is still offered.

## [1.1.0] — 2026-09-21

### App
- Checks GitHub for a newer release on launch and offers the install page;
  turn it off in Settings → Updates, or check by hand there.

### Changed
- *Remove from the tray once taken* is now off by default (copy, not cut).
  An existing choice is kept.

## [1.0.0] — 2026-09-21

The first release.

### Tray
- Drag files, photos, videos and text in from any app; items are copied into
  the app, so they outlive their source.
- Drag them out again, several at once by tapping more cards with a second
  finger.
- Grid or list, switched from the toolbar; sort by name, date or size, group by
  kind, filter by kind and age, and search across both boards.
- Select several to share or delete; swipe a row left to delete it, or swipe
  all the way to delete at once.
- Optionally remove an item once another app has taken it (cut instead of
  copy), and delete the original too when it really was moved.
- Asks before taking in a file the tray already has.

### Dynamic Island
- A Live Activity showing the count, thumbnails and filenames, with buttons to
  page through the items.
- Kept up past iOS's eight-hour limit by a Shortcuts automation; optionally
  shown even when the tray is empty.
- Follows a shortcut's additions immediately, even with another app in front.

### Getting things in
- Share extension (paid accounts) and a ready-made share-sheet shortcut (free
  accounts), both installable from inside the app.
- *Save to Files → On My iPhone → IslandTray* is taken in the next time the app
  opens.
- A clipboard board, fed by a ready-made shortcut for the Action button or a
  back tap. Formatted text keeps its formatting for apps that support it and
  pastes as plain text elsewhere.

### App
- English and Japanese, light/dark theme, and a highlight colour of your own.
- Unsigned `.ipa` builds for TrollStore (`Release`) and AltStore / SideStore
  (`Free-Release`).

[1.1.1]: https://github.com/Pikare02/IslandTray/releases/tag/v1.1.1
[1.1.0]: https://github.com/Pikare02/IslandTray/releases/tag/v1.1.0
[1.0.0]: https://github.com/Pikare02/IslandTray/releases/tag/v1.0.0
