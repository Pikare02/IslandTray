# Shortcuts

**English** · [日本語](SHORTCUTS.ja.md)

IslandTray adds these actions to the Shortcuts app. They run inside the app's
own process, which is why they work even on a free account where the share
extension cannot. The actions are named in Japanese in Shortcuts whatever the
app's language; the English names below are translations.

| Action in Shortcuts | Meaning | What it does |
|---------------------|---------|--------------|
| **トレイに追加** | Add to Tray | Puts the files it is given into the tray. |
| **クリップボードに追加** | Add to Clipboard | Puts what it is given — text, images, files — on the clipboard board. |
| **トレイの表示を更新** | Refresh the tray display | Rebuilds the Dynamic Island display. |
| **トレイの表示をめくる** | Page the tray display | Turns the island to the next page (used by its buttons). |

## Ready-made shortcuts

**Settings → Setup** in the app installs both of these with one tap each
(choose *Shortcuts* in the sheet, then *Add*). They are signed, so no
"untrusted shortcuts" setting is needed.

### ShareToTray — the share sheet

*Receive files, images, media, PDFs and text from the Share Sheet → トレイに追加.*

It appears in the share sheet of every app. Links are deliberately not
accepted: a link cannot become a file, and accepting one made Shortcuts pick
the link instead of the image when sharing a picture from Safari.

### ClipboardToTray — keep what you copy

*Get Clipboard → クリップボードに追加.*

Assign it to the Action button or a back tap (*Settings → Accessibility →
Touch → Back Tap*), and copying something and keeping it is one press.
Formatted text is stored as it came in; copying it back out of the app offers
the formatting to apps that paste it and plain text to those that do not.

If the Clipboard variable was never connected to the action's *Content*
field, the action reads the clipboard itself — which iOS allows only while
IslandTray is in front.

## Keeping the island up around the clock

iOS ends a Live Activity after eight hours. Three daily automations bring it
back:

1. In Shortcuts, open the **Automation** tab and tap **+**.
2. Choose **Time of Day**, set **07:00**, **Daily**.
3. Choose **Run Immediately** — left asking for confirmation, it will not run
   on its own.
4. For the action, choose **トレイの表示を更新** (refresh the tray display).
5. Repeat for **15:00** and **23:00**.

Opening the app also rebuilds the island, so a missed run is fixed the next
time you open it.

## Rebuilding the bundled shortcuts

The `.shortcut` files in `Resources/Shortcuts` are generated and signed by a
script (macOS only, needs the `shortcuts` command):

```bash
python3 scripts/make-shortcuts.py
```
