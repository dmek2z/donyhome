# Local Tools Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline. Steps use checkbox syntax.

**Goal:** Add the locally implementable missing CleanMyMac workflows to DonyClean.
**Architecture:** Focused Foundation scanners reuse immutable FileCandidate and TrashService. AppModel extensions coordinate tools. Native SwiftUI views show live results; OS authentication runs fixed maintenance commands.
**Tech Stack:** SwiftPM, Swift Testing, SwiftUI/AppKit, Darwin, IOKit.
**Spec:** docs/superpowers/specs/2026-10-13-local-tools-design.md

## Global Constraints
- Local only; no privileged background daemon or external runtime.
- Existing file/duplicate/process identity protection remains binding.
- Only dev caches join automatic recommendations; leftovers, old/install files and disk map require explicit selection.
- Never run personal destructive/maintenance tasks as verification.

## Review Focus
- Installed apps outside normal inventory roots must not be labeled certainly removed.
- Running tools and changed descendants must block developer cleanup.
- Nested candidates must retain duplicate original dependencies.
- Logical disk totals must not double count hard links or follow symlinks/cloud placeholders.
- Maintenance dates/arguments cannot become arbitrary shell commands; cancellation cannot appear successful.

### Task 1: Scanners and policies
**Files:** DonyCore/{DeveloperCleanup,Leftovers,Clutter,SpaceMap}.swift, Tests/DonyCoreTests/LocalToolsTests.swift.
**Interfaces:** DeveloperCleanup.scan(home:runningTools:token:), LeftoverScanner.scan(home:installedIDs:runningIDs:registered:token:), ClutterScanner.scan(root:token:), SpaceMap.scan(root:token:) return bounded, cancellable results.
- [x] Add failing fixture tests for exact paths, age, active tools, symlinks, installed/registered ID exclusion, old/installer classification, hardlink totals and cancellation.
- [x] Implement scanners/policies using shared validation and local metadata.
- [x] Run scripts/test.sh; expected green whole suite.

### Task 2: Maintenance and monitoring
**Files:** DonyCore/{Maintenance,Telemetry}.swift, bridge.c/h, Tests/DonyCoreTests/LocalToolsTests.swift.
**Interfaces:** Maintenance.command(for:), parseSnapshots(_:) and typed operations; Snapshot optional battery/network fields.
- [x] Test snapshot parsing/identifier injection, fixed command construction, reset/network deltas and unavailable battery data.
- [x] Implement commands and actual IOKit/getifaddrs readings; no privileged action in tests.
- [x] Run suite and read-only diagnostics; expected passing, sane measurements.

### Task 3: UI, integrated actions and delivery
**Files:** DonyClean/{AppModel,LocalToolsModel,SpaceView,ToolsView,FilesView,ApplicationsView,SmartCareView,OverviewView}.swift; SmartScanner; README/review/progress.
- [x] Wire new scans into smart results, developer recommendations, revalidation, history and distinct manual selectors.
- [x] Add map drilldown, old/install tabs, leftovers review, monitor values and manual maintenance actions with OS authentication and native confirmation.
- [x] Build/sign, read-only scan and fixture action tests pass. Native render/click review remains pending because Mac is locked; no claim of observed GUI or privileged-task execution.
- [x] Independent focused review, fix Important findings with regressions, update local installed app and commit.

User-scope addition: SimilarPhotoFinder/Vision CPU image comparison, user-chosen retained photo, preview/manual Trash and cross-recommendation protection. 200-image bound, source identity validation, exact duplicate overlap and corrupted-image errors tested.

Final addition: current-user Trash inspection and immutable-confirmation-list permanent emptying, exact root/fingerprint/new-entry/running-app guards, verified only on generated temporary fixtures. Final 53 tests / 14 suites pass.
