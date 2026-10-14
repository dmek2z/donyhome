# Clipboard flow ·2.3.3

Reference: https://github.com/p0deje/Maccy at fe0d74d2a622bdadb6513b8bf8fe4aeb0609f6f2. Reviewed FloatingPanel.swift, Observables/Popup.swift, Observables/History.swift, Observables/AppState.swift, Views/KeyHandlingView.swift and README usage. Existing clipboard capture/format handling attribution and MIT license remain bundled.

Quick access must perform actual clipboard writes: most recently copied unpinned item is number1;1–9 target the current filtered recent order, not permanent record IDs. Management sorting preferences remain separate. Rich text/image/file representations use the existing bounded capture/write path. Numbered copy is always copy; Option paste keeps its permission/target/change-count validation. A successful write closes the popup before any optional paste permission fallback. External clipboard changes close the popup even when history capture is paused/ignored.

The popup and independent settings use a nonactivating floating panel that accepts keyboard focus and works during another app-modal cleanup confirmation. Settings keys are excluded from the quick-list event monitor. Pin editing/key selection stay inside settings instead of creating another blocked sheet. Shortcut recording is scoped to its owning window and explicitly cancelled on close; closing settings disposes the hosting tree.

Actual clipboard state is separate from keyboard highlighting. A successful write or allowed capture sets the current marker. External/ignored/paused changes and editing the copied record invalidate it. Failure leaves the popup and error visible; only successful writes close it. Existing history/settings are preserved.

Regression evidence: initial4 tests failed with8 issues, then passed. Review corrections for editing/recorder lifetime failed as2 cases, then passed. Recency/window-close cases failed before fixes. Final evidence is recorded in the session/release notes. Unit cases use private pasteboards and zero-size nonactivating fixture panels; personal clipboard data is not deleted or uploaded. A local native checker compares hashes and history identities without printing clipboard text.

Scope is the functional quick-copy/settings flow. The original project's hold-to-cycle shortcut mode and slide-out preview behavior are not claimed as implemented. Existing search modes, pins/letters, storage/type/app exclusions and optional paste are retained; automatic paste requires the user's existing accessibility authorization.

## Final verification

Core191 tests/34 suites passed on the final production source. Popup9 cases passed after correcting the external-copy fixture to advance the native pasteboard change count with clearContents before setString. The9 cases include rich-format writes, copied-item promotion, dynamic1/2 reassignment independent of management sorting, actual zero-size popup visibility after internal/external copy, paused capture, edit invalidation and synchronous recorder cancellation. Design policy5 passed;2.3.2/build20 release build and strict signature passed.

Installed:/Users/dhkim/Applications/DonyHome.app. NativeCmd2 changed the actual general pasteboard to the selected item and closed the popup. On reopening, Cmd1 copied that same newly promoted item and closed it again; hashes/history IDs matched without printing content. Rewriting the existing general pasteboard representations from a separate process advanced changeCount and closed the open popup while preserving clipboard bytes. The popup Settings button opened the independent settings window; shortcut recording entered its waiting state and closing Settings cancelled it. Existing history/settings retained; no user files or history were removed.

This patch's final native verification did not repeat the entire cleanup-confirmation/modal scenario; the original failure was observed during such a confirmation and the modal admission/independent-settings paths have component assertions. Hold-to-cycle and slide-out preview remain outside this fix.

The local Swift6.4 test build required an explicit external-plugin-path for TestingMacros under CommandLineTools/usr/lib/swift/host/plugins/testing; product release building does not require that test-only argument.


## 2.3.3: stale popup reproduction and correction

A real failure remained in2.3.2: the general pasteboard and persisted/main-window history contained the latest copy, but reopening the existing floating popup still rendered an older number1. This was reproduced in the installed app, so successful storage/shortcut assertions alone did not establish that the visible popup was current.

The controller now polls synchronously before presentation and recreates the standalone hosting tree on each opening. Query, selection and scroll start fresh; the controller owns exactly one popup key monitor, and an old tree can only remove its own monitor identity. The visible list and the current shortcut targets are built from the same recent-copy order.

A second regression test exposed capture suspension in NSModalPanelRunLoopMode: the old scheduled timer left the new copy uncaptured and the popup visible. Capture now runs synchronously on the main run loop, registered for common, event-tracking and modal-panel modes. Tests use temporary pasteboards and zero-size fixture windows, without exercising real cleanup.

Verification: core191 tests/34 suites and popup11 tests passed together; the added AppKit key-event regression also passed, for203 distinct tests total. That additional test mounts the actual hosting view and sends numbered AppKit events to its own private fixture panel:2 copies the second item once and closes, rebuilding then1 copies the promoted item once and closes. It guards against missing or duplicate monitors across rebuilt trees. Design policy5 tests passed;2.3.3/build21 release build and strict signature passed.

Installed2.3.3 native checks: the reported latest sentence appeared as number1 after item-click copy/reopening, with the actual general pasteboard bytes matching. New external copies appeared in the rebuilt popup instead of the previous stale list. A separate process restored the clipboard representations saved immediately before copy testing; the visible popup closed and reopening placed that external copy at number1. History/settings were retained and no personal cleanup ran.

CUA numbered/direction-key attempts during this check returned focus to the main window without a clipboard write; those attempts are not counted as keyboard success. The in-process AppKit event test above verifies the actual hosted keyboard monitor and write/close/promote behavior. This follow-up did not run a complete real cleanup confirmation alongside the popup; modal/event-tracking capture is verified using the native run-loop modes with private fixtures.
