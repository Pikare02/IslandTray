# Changelog

**English** · [日本語](CHANGELOG.ja.md)

Versions follow [Semantic Versioning](https://semver.org): the last number for
fixes, the middle one for new features, the first for changes that break how
the app is used. The version is set once, in `project.yml`
(`MARKETING_VERSION`), and each release is tagged `vX.Y.Z` with its `.ipa`
files attached on GitHub.

## [1.7.0] — 2026-09-24

### Labs
- **App Drawer** is a new Labs toggle (off by default; on, nothing else
  changes about the tray or clipboard). Turn it on and a full-screen drawer of
  shortcuts sits under the tray. Add an entry for an installed app, a
  Shortcuts shortcut, a URL scheme, or a web link — picking an installed app
  is TrollStore-only, the other three kinds work on the free build too. Each
  entry can carry its own custom icon, and the drawer can have a background
  image.
- When the drawer is empty it shows the date and current weather, from
  [Open-Meteo](https://open-meteo.com/) for your location if you allow it, or
  a region you pick by hand instead.
- The drawer is its own tab now, first in the bar (App Drawer · Tray ·
  Clipboard · Search), shown while the Labs toggle is on. Labs moved to its own
  page in Settings, just above the import log.
- Tapping a drawer icon runs it; long-press to edit. Picking a custom icon
  opens a square crop you can pan and zoom.
- Fixed: turning the drawer on put an unknown folder into the tray, and after
  deleting it nothing added to the drawer reached the Dynamic Island. The
  drawer's data no longer lives in the Files-app folder.
- Island: no stray arrow on an empty tray. With items, the left arrow on the
  first page opens the drawer and the right arrow comes back. The compact
  date and weekday are centred.
- Fixed: tapping a shortcut in the expanded island only opened IslandTray.
  A Live Activity link always opens its own app, so the app now passes the
  shortcut's URL on.
- New toggle: *Always show drawer on Lock Screen* — the Lock Screen activity
  shows the drawer's first six icons whatever the tray holds.

### Toolbar
- In a narrow window (iPad Slide Over) the toolbar buttons that do not fit
  appear in the overflow menu with their names.

### Updates
- Turning on *Keep reminding about important updates* now also sends a
  one-time system notification the first time an important update is found,
  in addition to the launch alert. Off is unchanged: told once, no
  notification.

## [1.6.2] — 2026-09-24

### iCloud Sync
- Another device's changes show up faster. While the app is open it now looks
  at the folder every 15 seconds instead of 30, and the moment it has asked
  iCloud for a new entry it checks again in a few seconds rather than waiting a
  whole cycle to read it — so a new item no longer sits behind two full
  intervals before it appears.

## [1.6.1] — 2026-09-24

### Settings
- The setup guide reads more clearly. The note on why the automation is needed
  now leads the steps it explains, instead of standing alone under its own
  header, and that section is titled for what it does — *Keeping the Dynamic
  Island always on* — rather than a bare *Setup steps*.
- Status now sits right after Appearance.

## [1.6.0] — 2026-09-24

### iCloud Sync
- **iCloud Sync** is now a regular feature, at the top of Settings (it was
  under Labs in 1.6.0 Nightly 1). Still off by default: off, the tray and
  clipboard stay on this device; on, choose the same folder in iCloud Drive on
  each device and both lists are shared through it. Works on a free account.
- An item from another device shows a cloud and downloads when tapped; a bar
  under the board shows sync progress, with the details one tap away.
- Deleting an item deletes it on every device. Turning sync off, disconnecting
  or changing the folder deletes nothing.

### Settings
- New order: iCloud Sync, Updates, Behaviour, Appearance, Setup, Status,
  Import log.
- Each one-click shortcut install now sits in the section of the guide it
  sets up (share sheet, clipboard).
- Updates has an *Open the Releases Page* link that is always there, up to date
  or not, for release notes and older builds.

## [1.6.0-nightly.1] — 2026-09-23 · Nightly

A preview build, published as a pre-release. The app's update check only
follows stable releases, so it will not offer this build or move anyone onto
it.

### Labs
- New *Labs* section in Settings, with **iCloud Sync** (off by default). Off,
  the tray and clipboard stay on this device, exactly as before. On, choose the
  same folder in iCloud Drive on each device and both lists are shared through
  it. Works on a free account; no iCloud entitlement is needed.
- An item from another device shows a cloud next to its name and downloads
  when tapped. A bar under the board shows a sync or download in progress; tap
  it for the details (folder, last sync, uploads waiting, activity log).
- Deleting an item deletes it on every device. Turning sync off, disconnecting
  or changing the folder deletes nothing.

## [1.5.0] — 2026-09-23

### Updates
- New setting *Keep reminding about important updates* (on by default). Turn
  it off and an important update is offered once, with "Don't Show Again",
  like any other.

### Clipboard
- Dragging an item out of the clipboard board no longer removes it, whatever
  the export settings say: it is a clipboard, so it stays to be pasted again.
  Only the tray moves items.

## [1.4.0] — 2026-09-23

### Shortcuts
- Adding through ShareToTray or ClipboardToTray no longer ends in an "Added"
  dialog: the Dynamic Island expands for a moment with a green check (and the
  alert's sound/haptic) instead. A dialog appears only when something could
  not be added or there is no island to show it on.
- Every action in the two shortcuts now carries a fixed identity, so the
  "Always Allow" you tap on the sharing question is remembered. It was asked
  again for each new item because the permission is kept against the identity
  of the action that asked, and the actions had none.
- On iOS 27, the clipboard shortcut carries a screenshot automation: turn it
  on once and every screenshot you copy lands on the clipboard board by
  itself. Settings explains the two switches. (Signing on macOS 26 strips the
  automation out of the shipped file; the build says so when it does.)

### Search
- Search by contents too: what a text item says, and the words recognised in
  images (OCR). Choose *All*, *Names* or *Contents* at the top left of the
  search screen.

### Updates
- An important update — an urgent fix, or a version that changes how the app
  works — says so and keeps saying so until the app is updated. Ordinary
  updates are still offered once and can be dismissed for good.

## [1.3.1] — 2026-09-22

### Fixed
- Folders: the copy out of Files is a coordinated read, so the Files app
  materialises the folder's contents for it, and a folder whose provider only
  hands over its URL is taken in too. A drop that still fails says why in
  Settings → diagnostics.

### Share sheet
- The share-sheet shortcut accepts folders.

## [1.3.0] — 2026-09-22

### Tray
- Folders can be put in the tray and taken out again as folders: drag one in
  from Files, or save it to *On My iPhone → IslandTray*. A folder is one item
  with a folder icon, its own group and filter, and the total size of what is
  inside; dragging it out hands over the whole folder.

## [1.2.0] — 2026-09-21

### Clipboard
- Tap an item's name to copy it back to the system clipboard; swipe a row
  right for Copy, or all the way to copy at once; in the grid, Copy is in the
  long-press menu. Works for images and files as well as text.
- The clipboard shortcut says “Added to the clipboard”, not “to the tray”.

### Fixed
- Adding through the share-sheet shortcut updates the Dynamic Island at once,
  instead of the next time the app is opened.

## [1.1.5] — 2026-09-21

### Fixed
- 1.1.4 was built without the two shortcuts, so the install buttons in
  Settings did nothing. They are back.

## [1.1.4] — 2026-09-21

### Changed
- *Remove from the tray once taken* and *Also delete the original file* are
  now two separate settings, both off by default. Deleting the original no
  longer requires removing the item from the tray.

### Fixed
- Dragging an item out is always offered as a copy, so the Files app shows
  the "+" instead of treating the drop as a move.

## [1.1.3] — 2026-09-21

### Changed
- The install page moved to GitHub Pages
  (<https://pikare02.github.io/IslandTray/>); the update popup opens it there.

## [1.1.2] — 2026-09-21

### Fixed
- Files of a type iOS does not know (an `.ipa`, for example) can be dragged
  into the Files app again; they were offered under a temporary type that
  Files refused, so the "+" never appeared.

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

[1.3.1]: https://github.com/Pikare02/IslandTray/releases/tag/v1.3.1
[1.3.0]: https://github.com/Pikare02/IslandTray/releases/tag/v1.3.0
[1.2.0]: https://github.com/Pikare02/IslandTray/releases/tag/v1.2.0
[1.1.5]: https://github.com/Pikare02/IslandTray/releases/tag/v1.1.5
[1.1.4]: https://github.com/Pikare02/IslandTray/releases/tag/v1.1.4
[1.1.3]: https://github.com/Pikare02/IslandTray/releases/tag/v1.1.3
[1.1.2]: https://github.com/Pikare02/IslandTray/releases/tag/v1.1.2
[1.1.1]: https://github.com/Pikare02/IslandTray/releases/tag/v1.1.1
[1.1.0]: https://github.com/Pikare02/IslandTray/releases/tag/v1.1.0
[1.0.0]: https://github.com/Pikare02/IslandTray/releases/tag/v1.0.0
