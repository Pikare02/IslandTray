# Installing IslandTray

**English** · [日本語](INSTALL.ja.md)

IslandTray is not on the App Store. Install it from Xcode, or build an
unsigned `.ipa` and sideload it.

## From Xcode

1. `xcodegen generate`, then open `IslandTray.xcodeproj`.
2. Choose your team under *Signing & Capabilities* for each target.
3. Pick a scheme and run on your device:
   - `IslandTray` — with a **paid** Apple Developer account. Uses an App Group,
     so the share extension works.
   - `IslandTray (Free)` — with a **free** personal team. No App Group; the
     share sheet is reached through a shortcut instead (see
     [SHORTCUTS.md](SHORTCUTS.md)).

## Building the .ipa

```bash
./scripts/make-ipa.sh Release        # build/IslandTray-Release.ipa
./scripts/make-ipa.sh Free-Release   # build/IslandTray-Free-Release.ipa
```

The `.ipa` is unsigned; sideloading tools sign it themselves. After packaging,
the script checks that both extensions (widget and share), the Live Activity
and URL-scheme keys, and the right entitlements are present, and fails rather
than leaving a broken build behind.

| File | For |
|------|-----|
| `IslandTray-Release.ipa` | Tools that can grant arbitrary entitlements, such as TrollStore. Requests the App Group. |
| `IslandTray-Free-Release.ipa` | AltStore / SideStore and other free-account signing. No entitlements. |

## What differs on a free account

- The app cannot appear in the share sheet directly. Install the share-sheet
  shortcut from **Settings → Setup** in the app, or use *Save to Files* and
  choose *On My iPhone → IslandTray*; the file is taken in the next time the
  app opens.
- Everything else — the tray, the island, dragging in and out, the clipboard
  board — works the same.

## After updating

When a new build changes the bundled shortcuts, delete the old shortcut in the
Shortcuts app and install it again from the app's Settings. Installed shortcuts
are copies and do not update themselves.
