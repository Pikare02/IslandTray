#!/usr/bin/env python3
"""Builds the two shortcuts the app offers to install, and signs them.

Run from the repository root:

    python3 scripts/make-shortcuts.py

Signing matters: an unsigned shortcut can only be imported after the user
finds "Allow Untrusted Shortcuts" in Settings, which is hidden until they have
run a shortcut at least once. A shortcut signed with `-m anyone` imports with
no such detour. Signing needs macOS and the `shortcuts` CLI, which is why this
is a build-time script and not something the app does at runtime.
"""

import plistlib
import subprocess
import sys
import uuid
from pathlib import Path

# Every action's UUID is derived from this namespace and a name, never random:
# the "Always Allow" a person taps is remembered against the UUID of the action
# that asked (WFSmartPromptState carries the action UUID), so a UUID that
# changed on every build -- or was absent, and made up afresh on each load --
# would put the question back on every run.
NAMESPACE = uuid.UUID("9a5e9fd8-7c37-5e0e-9cf5-6cb0f1d1b0aa")


def stable_uuid(name):
    return str(uuid.uuid5(NAMESPACE, name)).upper()

BUNDLE = "com.pikare.islandtray"
OUT = Path("Resources/Shortcuts")

# Only what can actually become a file. A URL cannot: Shortcuts answers a
# shared web image with "WFURLContentItem produced no file representation for
# type public.data" and stops before the action runs. Leaving URL-ish classes
# out makes Shortcuts take the image representation the same share offers
# instead -- and where a share really is only a link, the shortcut stays out
# of the sheet rather than appearing and failing.
SHARE_INPUTS = [
    "WFGenericFileContentItem",
    # A folder from Files. Without it the shortcut is not offered for one.
    "WFFolderContentItem",
    "WFImageContentItem",
    "WFAVAssetContentItem",
    "WFPDFContentItem",
    "WFRichTextContentItem",
    "WFStringContentItem",
]


def action(identifier, parameters=None, action_uuid=None):
    parameters = dict(parameters or {})
    if action_uuid:
        parameters["UUID"] = action_uuid
    assert "UUID" in parameters, f"{identifier} needs a stable UUID"
    return {
        "WFWorkflowActionIdentifier": identifier,
        "WFWorkflowActionParameters": parameters,
    }


def from_output(action_uuid, name):
    return {
        "Value": {"Type": "ActionOutput", "OutputUUID": action_uuid, "OutputName": name},
        "WFSerializationType": "WFTextTokenAttachment",
    }


FROM_SHARE_SHEET = {
    "Value": {"Type": "ExtensionInput"},
    "WFSerializationType": "WFTextTokenAttachment",
}


# What "when a screenshot is saved to the clipboard" is, in a file.
# iOS 27 made automation triggers part of the shortcut itself, so one can be
# shipped here rather than built by hand in Settings. The keys and the
# "ScreenshotLocations" values come from WorkflowKit (iOS 27 simulator
# runtime); an older iOS ignores the whole array and the shortcut still runs
# by hand. It arrives switched off -- iOS disables the automations of an
# imported shortcut, whatever this says -- so the person turns it on once.
SCREENSHOT_TO_CLIPBOARD_TRIGGER = {
    "WFTriggerIdentifier": "WFScreenshotTrigger",
    "WFTriggerUUID": stable_uuid("ClipboardToTray.screenshotTrigger"),
    "WFTriggerSerializedParameters": {
        "ScreenshotLocations": ["clipboard"],
        "__enabled__": True,
        # No "shortcut ran" banner and no "run?" question: the island already
        # says what was added.
        "__notify__": False,
        "__show_confirmation__": False,
    },
}


def workflow(actions, types, inputs, glyph, colour, triggers=None):
    if triggers:
        return dict(_workflow(actions, types, inputs, glyph, colour), WFWorkflowTriggers=triggers)
    return _workflow(actions, types, inputs, glyph, colour)


def _workflow(actions, types, inputs, glyph, colour):
    return {
        "WFWorkflowClientVersion": "2000",
        "WFWorkflowMinimumClientVersion": 900,
        "WFWorkflowMinimumClientVersionString": "900",
        "WFWorkflowIcon": {
            "WFWorkflowIconStartColor": colour,
            "WFWorkflowIconGlyphNumber": glyph,
        },
        "WFWorkflowImportQuestions": [],
        "WFWorkflowTypes": types,
        "WFWorkflowInputContentItemClasses": inputs,
        "WFWorkflowActions": actions,
    }


def build():
    OUT.mkdir(parents=True, exist_ok=True)

    clipboard_uuid = stable_uuid("ClipboardToTray.getclipboard")
    clipboard = workflow(
        [
            action("is.workflow.actions.getclipboard", action_uuid=clipboard_uuid),
            action(
                f"{BUNDLE}.AddToClipboardIntent",
                {"content": from_output(clipboard_uuid, "クリップボード")},
                action_uuid=stable_uuid("ClipboardToTray.add"),
            ),
        ],
        # No ActionExtension: this one is for the Action button and back taps,
        # where there is no shared item to receive.
        types=["NCWidget"],
        inputs=[],
        glyph=59511,
        colour=463140863,
        triggers=[SCREENSHOT_TO_CLIPBOARD_TRIGGER],
    )

    share = workflow(
        [action(
            f"{BUNDLE}.AddToTrayIntent", {"files": FROM_SHARE_SHEET},
            action_uuid=stable_uuid("ShareToTray.add"),
        )],
        # ActionExtension is what puts a shortcut in the share sheet.
        types=["ActionExtension"],
        inputs=SHARE_INPUTS,
        glyph=59511,
        colour=946986751,
    )

    return {"ClipboardToTray": clipboard, "ShareToTray": share}


def main():
    built = build()
    for name, plist in built.items():
        # The CLI refuses an input that is not named .shortcut.
        unsigned = OUT / f"{name}-unsigned.shortcut"
        signed = OUT / f"{name}.shortcut"
        plistlib.dump(plist, unsigned.open("wb"), fmt=plistlib.FMT_BINARY)
        result = subprocess.run(
            ["shortcuts", "sign", "-m", "anyone", "-i", str(unsigned), "-o", str(signed)],
            capture_output=True, text=True,
        )
        unsigned.unlink()
        if result.returncode != 0:
            print(f"signing {name} failed: {result.stderr.strip()}", file=sys.stderr)
            return 1
        print(f"wrote {signed} ({signed.stat().st_size} bytes)")
    if any(p.get("WFWorkflowTriggers") for p in built.values()) and not keeps_triggers():
        print(
            "note: this Mac's `shortcuts sign` is older than macOS 27 and drops "
            "WFWorkflowTriggers, so the screenshot automation is not in the "
            "signed file. Build on macOS 27 or later to ship it.",
            file=sys.stderr,
        )
    return 0


def keeps_triggers():
    """Whether `shortcuts sign` preserves a trigger, or quietly drops it.

    Signing runs the file through the host's own Shortcuts, which discards
    keys it does not know -- and automation triggers in a shortcut file are
    iOS/macOS 26 and later. Measured rather than inferred from the OS version:
    two otherwise identical workflows, one with a trigger, are signed and
    compared. Equal sizes means the trigger did not survive.
    """
    import tempfile

    bare = _workflow([action("is.workflow.actions.nothing", action_uuid=stable_uuid("probe"))],
                     ["NCWidget"], [], 59511, 463140863)
    with tempfile.TemporaryDirectory() as tmp:
        sizes = []
        for label, plist in [("bare", bare), ("trig", dict(bare, WFWorkflowTriggers=[SCREENSHOT_TO_CLIPBOARD_TRIGGER]))]:
            src = Path(tmp) / f"{label}-unsigned.shortcut"
            out = Path(tmp) / f"{label}.shortcut"
            plistlib.dump(plist, src.open("wb"), fmt=plistlib.FMT_BINARY)
            if subprocess.run(["shortcuts", "sign", "-m", "anyone", "-i", str(src), "-o", str(out)],
                              capture_output=True).returncode != 0:
                return True  # Cannot tell; do not cry wolf.
            sizes.append(out.stat().st_size)
        return abs(sizes[0] - sizes[1]) > 32


if __name__ == "__main__":
    sys.exit(main())
