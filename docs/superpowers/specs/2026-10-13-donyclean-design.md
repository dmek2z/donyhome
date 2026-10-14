# DonyClean · 도니클린

Personal macOS utility, approved in chat on 2026-10-13. All measurements and operations stay on this Mac. SwiftUI/AppKit native application, macOS 14+, no third-party dependencies, telemetry, accounts, subscriptions or privileged helper.

## Scope

- Overview: live total CPU, memory usage/pressure, swap, disk availability and time series. A combined scan examines user caches/logs and current resource pressure and links to specific remedies.
- Cleanup: inspect immediate children of ~/Library/Caches and ~/Library/Logs, show size, full path and unavailable paths. No selected-by-default deletion. Scan off the main thread with progress and cancellation. Skip links and inaccessible items.
- Files: choose a folder, list large files (>=100 MB), find exact byte-identical duplicates using size then streamed SHA-256 then byte comparison. Preserve one original per duplicate group. Exclude packages, hidden files and cloud placeholders. Hard links are not additional copies.
- Performance: live process CPU delta and physical memory, sorted by user choice. Regular GUI applications belonging to the current user can be quit explicitly, with a separate force-quit confirmation. Verify PID, start time, UID and protected application identities immediately before every action. No automatic killing, purge, swap removal, memory balloon allocation or arbitrary terminal commands.
- Applications: list user-installed applications, their sizes and precise bundle-ID-related caches/logs/preferences/application support candidates. Support files are presented individually and unselected. Running applications must be quit before removal; system applications cannot be removed. Login/background management opens the macOS settings panel.
- Menu bar: live CPU/memory overview, open the app, and persistent load hints. System notifications are opt-in, sustained CPU >=85% for 30 seconds or warning/critical memory pressure for 30 seconds, with a ten-minute cooldown. No alerts on normal state.
- History: persist actual actions and per-item errors locally; open moved files in Finder. Moving files to Trash does not count as freed disk space. Emptying Trash remains a Finder action.

## File operation contract

Every actionable row retains its scanned path, allowed root and lstat fingerprint (device, inode, type, size, mtime). Revalidate before moving. Reject root itself, ancestor symlinks, path escapes, protected system roots, changed/replaced candidates, missing files, and application support roots themselves. Use macOS Trash API, report individual failures, and never recursively permanently delete user data. Known running-app cache folders are marked unavailable for cleanup. A duplicate may move only if a verified identical retained copy still exists at action time.

## Experience

Korean interface using the Dony design tokens: #f6f7f9 sidebar (240 px), #f2f4f6 canvas, white cards (20 px radius), #3182f6 primary buttons (42 px height), bundled Pretendard, and the Dony logo. Remove decorative overlines, marketing hero and repeated descriptions; retain measurements, labels, errors and important confirmations. This supersedes the initial mint/charcoal proposal per user direction on 2026-10-13. Window minimum 960x680. Six sections: Overview, Cleanup, Files, Performance, Applications, History. Preference toggles for monitoring notifications and login at launch. Main window and menu bar share one bounded sampler; hidden/minimized window retains only lightweight monitoring. Permission problems are reported rather than interpreted as empty directories.

## Deferred scope

Antivirus and third-party automatic updates require their own engines/sources and are not claimed by this version. OS/system caches and private browser histories are not scanned. No fabricated health score or claimed performance improvement; report actual observed values and moved bytes.

## Acceptance

Build standalone signed-local DonyClean.app with one shell command. Unit tests cover path safety, file changes, duplicate preservation including stale originals, hard links, partial scan errors, process identity and CPU arithmetic. Smoke-test real system metrics, cancellation and UI navigation. Exercise Trash only against disposable fixture files. Deliver app, sources and launch instructions.
