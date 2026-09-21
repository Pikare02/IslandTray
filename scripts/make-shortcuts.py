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

BUNDLE = "com.pikare.islandtray"
OUT = Path("Resources/Shortcuts")

# Every content type the share sheet can offer, so the shortcut appears for
# anything shareable rather than for files alone.
SHARE_INPUTS = [
    "WFAppStoreAppContentItem", "WFArticleContentItem", "WFContactContentItem",
    "WFDateContentItem", "WFEmailAddressContentItem", "WFGenericFileContentItem",
    "WFImageContentItem", "WFiTunesProductContentItem", "WFLocationContentItem",
    "WFDCMapsLinkContentItem", "WFAVAssetContentItem", "WFPDFContentItem",
    "WFPhoneNumberContentItem", "WFRichTextContentItem", "WFSafariWebPageContentItem",
    "WFStringContentItem", "WFURLContentItem",
]


def action(identifier, parameters=None, action_uuid=None):
    parameters = dict(parameters or {})
    if action_uuid:
        parameters["UUID"] = action_uuid
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


def workflow(actions, types, inputs, glyph, colour):
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

    clipboard_uuid = str(uuid.uuid4()).upper()
    clipboard = workflow(
        [
            action("is.workflow.actions.getclipboard", action_uuid=clipboard_uuid),
            action(
                f"{BUNDLE}.AddToClipboardIntent",
                {"content": from_output(clipboard_uuid, "クリップボード")},
            ),
        ],
        # No ActionExtension: this one is for the Action button and back taps,
        # where there is no shared item to receive.
        types=["NCWidget"],
        inputs=[],
        glyph=59511,
        colour=463140863,
    )

    share = workflow(
        [action(f"{BUNDLE}.AddToTrayIntent", {"files": FROM_SHARE_SHEET})],
        # ActionExtension is what puts a shortcut in the share sheet.
        types=["ActionExtension"],
        inputs=SHARE_INPUTS,
        glyph=59511,
        colour=946986751,
    )

    return {"ClipboardToTray": clipboard, "ShareToTray": share}


def main():
    for name, plist in build().items():
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
    return 0


if __name__ == "__main__":
    sys.exit(main())
