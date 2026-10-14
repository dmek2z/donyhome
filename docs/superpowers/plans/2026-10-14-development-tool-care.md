# Development tool care implementation plan

> Implement inline using superpowers:executing-plans; user requested the correction after the source review.

**Goal:** Tool-centered Development care with usable storage candidates and honest live resource actions.
**Architecture:** DonyCore owns recognized storage roots, candidate eligibility and pressure response; AppModel orchestrates scans and pre-move checks; SwiftUI displays the common tool model and delegates process actions to existing controllers.
**Spec:** ../specs/2026-10-14-development-tool-care-design.md
**Global constraints:** macOS 14+, all existing AITool categories, metadata-only scans, manual Trash only, no cloud conversation control, no RAM claims for disk cleanup or pause.
**Review focus:** symlinked parents; shared storage owners; recently modified/active tools after scan; selected-tool changes/cancellation; persistent legacy memory-triggered cleanup.

### Task 1: Core storage and pressure policy
Files: Sources/DonyCore/ToolStorage.swift; Tests/DonyCoreTests/ToolStorageTests.swift.
Interface: ToolStorage.scan(tools:home:runningTools:days:token:now:), ToolStorage.validate(_:home:runningTools:days:token:now:), result candidates/owners/reasons; DevelopmentPressurePolicy.shouldReview.
- [x] Add fixture tests for non-OpenAI tools, recent/active protection, credentials/history/source exclusion, shared/deduplicated roots, changed files and symlink parents, cancellation and pressure review.
- [x] Run RED; implement core; run GREEN/full suite and commit.

### Task 2: App model and tool-first Development UI
Files: Sources/DonyClean/ToolCareModel.swift; ToolCareView.swift; AIProjectsView.swift; AppModel.swift.
Consumes Task 1 interfaces. Keep existing project/work/cache tabs. Add default 도구 정리 tab and exact candidate review. Storage movement re-samples process owners and revalidates candidates; preserve selected photo/duplicate originals.
- [x] Wire tool scan, live usage and review navigation with busy/cancel/selection guards.
- [x] Disable legacy file cleanup on memory pressure; issue task-review notice only.
- [x] Apply common design components; build and check design rules.

### Task 3: Documentation, verification and delivery
- [x] Update design/integration docs and README, version 2.2.1/build 17.
- [x] Run full suite, release build, design check and one fresh whole-change review.
- [x] Verify native UI without deleting personal files or controlling real developer processes.
- [x] Commit, push own branch/create reviewable PR, package and update installed app.

### Accepted design correction (2026-10-14)
- Installed the standalone donyhome-design skill globally and bundled portable references/installer.
- Removed text dropdowns from Development and CPU/Memory; shared selection is now direct actions throughout file lists. Removed generic description paragraphs while retaining actual blocked reasons/confirmations.
- Added CI guards for new text dropdowns and portable-reference drift, plus four regression fixtures.
- Native verification: tool row/reset, disabled active-owner files, retention sheet open/close, task chips/empty state, memory navigation, select/clear with protected rows, 960pt-wide layouts. Actual file deletion and process termination were not performed.
- Core: 168 tests/31 suites passed; release bundle built/signed; skill schema and portable install/update/backup passed.
