# Development management

The primary page is Tool Care: all connected development tools appear with measured cache/log bytes, eligible file bytes, live process memory/CPU and connection status. Project inspection is a secondary tab for generated artifacts and explicitly selected project files. Local CLI task control is in Tasks; GUI application termination remains in CPU/Memory. Newly found projects remain unselected.

Tool Care uses a common adapter across the existing ChatGPT, Codex, Claude, Hermes, Orca, Cursor, Herdr, cmux, tmux, Terminal, OpenCode, Gemini, Aider, Copilot, VS Code, Windsurf and other-tool classifications. It checks exact named macOS cache/log roots and cache-only subdirectories under app support, plus Codex diagnostic logs, Claude debug logs and OpenCode cache. VS Code/Copilot shared cache is counted once in aggregate and protected while either owner runs. Missing or unrecognized locations are labeled unconfirmed; choosing a tool does not imply its private session schema is supported.

Candidates are individual regular files at least the configured shared retention age (14 days initially). Running-tool caches remain protected; old logs from active tools require a complete local file-descriptor snapshot showing the path and file identity are not open, rechecked immediately before movement. Scans never read file contents. Credentials, account/session databases, transcripts, project markers, instructions and worktrees are excluded; links are never followed. Cleanup is user-selected Trash movement with a native path/size confirmation and immediate live-owner/file/ancestor revalidation. New neighboring cache files are never swept into an inspected plan. Retained duplicate/photo originals remain protected. Disk space changes are measured separately from moved bytes.

Memory pressure produces a review notice after 30 seconds, with a 10-minute cooldown. It never starts disk-file cleanup. The legacy memory-triggered project cleanup setting is disabled on upgrade. Actual RAM relief requires task/application exit; CLI suspension retains memory. Automatic judgments that a task is idle, orphaned or unnecessary are not inferred from process size alone.

Cleanup choices are generated caches (default), project AI context, or whole project. Context means explicit project-local instruction/configuration paths; global conversation transcripts, account databases and tool state indexes are excluded. Managed worktrees are inventoried but their owner bookkeeping is not modified by raw folder deletion. Entire Git worktrees and context directories containing nested project markers are protected. Retention and active-owner checks apply to all scopes, with revalidation before Trash movement. Selection/settings are rechecked before execution. The default optional “remote backup required” filter for whole-project cleanup checks live remote refs for HEAD and all local branches/tags, clean working tree, stash, reflog-only work, linked worktrees, submodules, LFS attributes and ignored local files. With that filter on, network failure or unknown backup status preserves the folder; remote status is rechecked just before moving it. Cached remote-tracking refs alone do not establish backup. Users can explicitly turn the filter off to move unbacked local work to Trash; changing that choice clears the old plan before another manual cleanup. Running-project and retention protections remain separate.

## What integration means

- Codex: local thread SQLite cwd/activity index, current process directories and managed-worktree inventory. No native thread archive or cloud conversation API.
- Claude Code: bounded local JSONL metadata headers for cwd/activity. Claude desktop/cloud conversations are not connected.
- Cursor: local workspace metadata and activity timestamps. Chat contents are not rewritten.
- Herdr/Orca/cmux/tmux: read-only local CLI metadata adapters plus process directories. Availability and structured response checks are displayed; an executable alone is not a successful connection.
- Hermes and other CLI/editor tools: current process directories and explicit folder links; no assumed private session database schema.
- ChatGPT: explicit local folder links only. ChatGPT cloud Projects/chats are not supported.

This is local project/file integration, not an AI context-window compactor. Removing files reclaims disk space; it does not by itself free RAM used by running tools. Credentials and chat contents are not sent anywhere.

Project inventories run as one read-only helper process per folder. The parent enforces a 20-second deadline and interrupts the helper on cancellation, including when a filesystem provider or permission check blocks a system call. Incomplete folders remain visible with their issue; they are not treated as a successful inventory or remote-backup verification.

Primary references: https://code.claude.com/docs/en/sessions, https://github.com/openai/codex, https://herdr.dev/, https://www.onorca.dev/.

## Presentation and portable design skill

Development and CPU/Memory use direct actions, tool rows/chips and segmented scope selection. Retention is in a separate settings sheet. Generic capability/implementation paragraphs are removed; measurement caveats use help and actual blocked-file reasons remain visible. The shared selection component uses direct select/clear actions in all file lists. The standalone donyhome-design skill installs with `zsh scripts/install-design-skill.sh`; its bundled reference must match the design document, checked in CI. Legacy text dropdowns in maintenance/clipboard settings have been replaced with direct/segmented controls and settings sheets; only rare secondary icon-menu actions remain.

## 2.3.0 scan budgets and file accounting

Cache roots use a 1,000,000-entry/120-second traversal budget per root. Limits and inaccessible roots are shown as partial measured results rather than complete sizes. General cache inventories group discovered/recommended/protected regular-file bytes; duplicates by file identity are counted once. Recommendations are individual captured leaves, revalidated for retention, live ownership, sources introduced after scan, links and fingerprints. Unknown cache namespaces are inventoried but not recommended. The configured app retention is passed explicitly to smart/manual/automatic/developer/tool scans; legacy direct-core defaults remain only for backward compatibility.

The pnpm cache namespace is distinct from its content-addressable package store. Only the cache namespace is inspected by developer cleanup; source/project markers, credentials and store paths are preserved. References: https://github.com/pnpm/pnpm.io/blob/main/docs/settings/other.md and https://github.com/pnpm/pnpm.io/blob/main/docs/settings/store.md.
