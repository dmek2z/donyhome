# DonyClean Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan in the current session. Steps use checkbox syntax for tracking.

**Goal:** Deliver a native local-only Mac cleanup and performance utility named DonyClean.

**Architecture:** A Foundation core owns scans, candidate validation, duplicates and history. A small C bridge reads Mach/libproc counters. A shared main-actor model coordinates background jobs and a SwiftUI window/menu bar; AppKit owns confirmations, quit and Trash.

**Tech Stack:** Swift 5.9 language mode, SwiftPM, SwiftUI, AppKit, Darwin, CryptoKit, Swift Testing. macOS 14+.

**Spec:** docs/superpowers/specs/2026-10-13-donyclean-design.md

## Global Constraints

- All data stays on this Mac; no third-party runtime dependencies or privileged helper.
- Operations require explicit row selection or user-reviewed recommended batch, and final native confirmation.
- File moves use macOS Trash; only real action results enter history.
- Invalid/changed candidates, system files and PID identity changes are rejected.
- Antivirus and third-party automatic updates are deferred.

## Review Focus

- Symlink ancestors and root-prefix collisions must never authorize file moves.
- An original removed/changed after duplicate scan must block deletion of its copies.
- Permission-denied or cancelled scans must not appear as complete successful scans.
- Reused process IDs and system applications must never be terminated.
- Partial operation failures must preserve the successful results and surface errors.

### Task 1: Candidate safety and filesystem scanning

**Files:** Package.swift, Sources/DonyCore/{Models,FileSafety,Scanner,Duplicates}.swift, Tests/DonyCoreTests/FileTests.swift.

**Interfaces:** Produces `FileCandidate.capture(url:root:kind:)`, `FileSafety.validate(_:)`, `Scanner.largeFiles(root:token:progress:)`, `Scanner.cleanup(roots:token:progress:)`, `DuplicateFinder.find(root:token:progress:)`.

- [x] Write fixture tests for escaping paths, symlink ancestors, changed files, cancellation, exact duplicates, hard links and missing originals; run `swift test` and observe missing core functionality.
- [x] Implement scanning with lstat snapshots, bounded traversal, readable error reports and cancellable streamed hashing/byte verification.
- [x] Run `swift test`; expected all filesystem tests pass.

### Task 2: Live system and process measurements

**Files:** Sources/DonySystemBridge/{bridge.c,include/DonySystemBridge.h}, Sources/DonyCore/{Telemetry,ProcessPolicy}.swift, Tests/DonyCoreTests/TelemetryTests.swift.

**Interfaces:** Produces `SystemSampler.sample() -> SystemSnapshot`, `ProcessPolicy.canQuit(_:currentUID:ownPID:) -> Bool` and process start identity verification.

- [x] Write hand-calculated CPU-counter tests and tests rejecting protected, foreign and reused processes. Run the test suite and observe missing measurement behavior.
- [x] Implement Mach memory/CPU, sysctl swap/pressure, libproc counters and PID start/UID checks. Clamp only valid measurement intervals; first sample CPU is unavailable.
- [x] Run `swift test`; expected all tests pass. Use executable `--diagnostics` for actual sampled metrics.

### Task 3: Application lifecycle and actionable UI

**Files:** Sources/DonyClean/{DonyCleanApp,AppModel,Theme,OverviewView,CleanupView,FilesView,PerformanceView,ApplicationsView,HistoryView}.swift, Sources/DonyCore/{ApplicationScanner,History}.swift.

**Interfaces:** Consumes core candidates/snapshots; produces one shared model, native confirmations and per-item result persistence.

- [x] Add tests for related-file matching and history roundtrip with mixed successes/errors. Run the tests and observe missing behavior.
- [x] Implement app inventory and exact bundle-ID-related support candidate discovery, local history, separate normal/force quit, and revalidated Trash moves.
- [x] Implement six navigable views and menu bar using live data, cancellation, progress, empty states and permission feedback. Native UI is verified by build and actual app navigation rather than implementation-mirroring view tests.
- [x] Run `swift test` and `swift build`; expected clean pass/build.

### Task 4: Bundle and verify

**Files:** scripts/build-app.sh, scripts/make-icon.swift, Resources/Info.plist, README.md.

- [x] Create reproducible release bundle with local ad-hoc signature and generated native icon.
- [x] Run `swift test`, `scripts/build-app.sh`, `DonyClean --diagnostics`; expected passing tests, valid signature and sane real metrics.
- [ ] Final icon/smart-care/bulk-quit rendered review pending because the Mac is locked. Earlier overview/performance/folder picker and synthetic helper normal quit were verified. Core cancellation and synthetic Trash are tested; no claim of every UI click.
- [x] Review whole implementation and fix material findings with focused regressions; leave a launchable app and concise usage notes.

User extension: Added Phosphor source vector icons, integrated smart scan, conservative recommendation policy, overlap-safe recommended action plans and bulk normal quit. See docs/cleanmymac-review.md for exact implemented/deferred comparison. Latest rendered states remain pending, not inferred from a successful build.
