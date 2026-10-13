# Clipboard integration

Source: https://github.com/p0deje/Maccy at commit `0dd54788f45bfd1c11937af87f3f9a194e397beb`. Copyright (c) 2025 Alex Rodionov, MIT. License bundled at `Resources/Clipboard/Maccy-LICENSE.txt`.

## Actual reuse

`ClipboardHistory.swift` adapts the upstream `Maccy/Clipboard.swift` capture loop, supported/ignored pasteboard types, transient/webarchive/dynamic/Microsoft OLE exclusions, Word-link exclusions, empty-text handling, ignore regular expressions, application allow/deny filtering and clear-formatting behavior. `Maccy/Extensions/NSPasteboard.PasteboardType+Types.swift` supplies the exact protected marker names. It keeps each pasteboard item's representations rather than flattening everything, so multiple copied files and their original format representations survive. `Maccy/Sorter.swift` supplies the three sorting semantics and pinned-first behavior. Search mode control mirrors upstream `Search.swift`; the integration uses the same Fuse 1.4.0 threshold (0.7), 5,000-character performance truncation, result scores and score ordering as upstream. Upstream standalone UI, Defaults/Sauce/SwiftData coupling were replaced with existing native donyhome controls, Foundation JSON storage and AppKit/Carbon.

SPM dependency: https://github.com/krisk/fuse-swift exactly 1.4.0 (Maccy upstream lockfile version). Product `Fuse` is linked to `DonyCore`. Internal modules remain `DonyCore` and `DonyClean`.

## Integration hooks

Create one `@StateObject private var clipboard = ClipboardController()` in the app owner. Call `clipboard.start()` on application appearance (idempotent). Route sidebar page to `ClipboardView(controller: clipboard)`, settings to `ClipboardSettingsView(controller: clipboard)` and a menu action to `clipboard.showPopup()`. Call `stop()` for explicit teardown. The constructor snapshots the pasteboard change count and does not read existing clipboard contents. It starts only after the parent calls start.

Default shortcut is Command-Shift-C; a user-initiated native key recorder supports arbitrary key codes and Command/Option/Control/Shift modifiers. Existing saved shortcuts are preserved. Pin/delete shortcuts are also configurable. Carbon registration failures are displayed instead of claiming success. Manual history clear does not clear the system pasteboard; optional shutdown clearing of history and the system pasteboard are separate, disabled by default. Store: Application Support/donyhome/Clipboard/history.json, owner-only directory/file modes. Corrupt/unreadable history disables saving until an explicit recovery action moves the original file to a unique backup, preserving its contents. Pins survive restart and history pruning. Unpinned history limit 1–10,000; individual representation cap 25 MB and total copy cap 50 MB.

## Capability map

- Text, RTF/HTML, PNG/TIFF/JPEG/HEIC and files: original persisted bytes and per-item format types; image preview, local Vision OCR search, HTML/RTF plain text fallback and text/file search.
- History, duplicate copy count/date, pins, text edit, individual delete, clear unpinned/all, limit, three sorts.
- Exact substring, regular-expression, Fuse fuzzy and mixed search. Invalid regular expressions produce no matches and do not crash.
- Pause/resume, ignore next copy, app exclude/allowlist, enabled content categories, excluded pasteboard types and text regular expressions.
- Protected/concealed/transient/auto-generated data always skipped, major password manager app IDs excluded. Clipboard privacy markers are honored before representation reads.
- Fast popup remembers previous external frontmost app. Arrow navigation, Return copy, Option-Return paste, Option-Shift-Return plain paste, Command-1…9 quick copy, Option-Delete delete, Option-P pin, Option-Command-Delete clear unpinned and Shift variant clear all.
- Paste queue multi-selection, select all, reverse ordering, combined-text copy, plain-text preparation, next action and Cmd-V metadata advancement after user permission. For synthetic paste requests, queue completion keeps the pasted bytes unchanged; the next item is prepared only by an explicit next action, because key posting does not acknowledge target pasteboard consumption. Ordinary external physical Cmd-V retains upstream key-up preparation behavior. Once a synthetic request is used, that queue stays in explicit-next mode. Popup Option-S toggles selection, Command-A selects all, Option-R reverses, Shift-Return prepares the selected queue. An external clipboard capture interrupts the queue. Pending copies are attributed to the outgoing application before workspace activation changes context. Delayed paste verifies both the selected pasteboard change count and target process immediately before posting keys; stack advancement also validates the prepared clipboard. User-initiated paste checks Accessibility without requesting it, activates the remembered external app and verifies it still owns focus before dispatching a keystroke. Permission prompting is only on the settings button.

## Settings and presentation revision

- One grouped history list, shared 64pt rows, single-line titles and dividers; no cards per item. Quick text selection rows use the shared 36pt density, with explicit image-height overrides only for image rows.
- Direct settings button and six tabs: General (app login, open/pin/delete shortcuts, search, automatic/plain paste, Accessibility), Storage (content types, limit, sorting, byte count), Appearance (cursor/center placement, image size, delayed full preview, whitespace glyphs, app icons, title/footer), Pins (key/title/content/order), Exclusions (native app picker plus bundle IDs/types/regex), Advanced (pause, ignore next, optional shutdown clearing).
- Optional preference objects and pin titles decode older saved JSON without resetting existing settings or clipboard representations. Renaming a pin preserves its original data and content search.
- Automatic paste and explicit modifier selection share a tested policy. Command overrides automatic paste for copying; Option requests paste; Shift or the plain-text preference strips formatting. All popup selection paths use that policy.
- This does not reproduce Maccy's updater, separate menu-bar identity, sound notifications, every search-field visibility option or fuzzy match-range styling. donyhome owns app startup and its unified menu character. No unsupported controls are presented as working options.
- Core migration/modifier tests, release build and static row/menu rules are verified. Native rendering inspection of this revision remains pending while the Mac is locked; previous screenshots are not treated as verification of this build.

## Deliberate differences / remaining parity gaps

This is an adapted integration, not a byte-for-byte clone of the entire Maccy application. Upstream fuzzy highlight ranges are not reproduced. Pin letter assignment and shortcuts are integrated (queue control letters reserved). Multiple selection, pin ordering/bottom placement, image OCR, paste stack (explicit next preparation for safe asynchronous paste), adaptive keyboard layout paste and Chrome Remote Desktop/NetBeans clipboard resync are integrated. Maccy's standalone appearance, launch-at-login, localization/intents/updater, sound notifications and standalone shortcut definitions outside clipboard actions are not copied. The app's own startup/settings controls remain authoritative. Unknown private types are preserved only alongside an enabled supported type, as upstream does.

Tests use unique `NSPasteboard(name:)` boards and temporary fixture stores exclusively. They never read or write the user's general pasteboard or activate/paste into an external app.
