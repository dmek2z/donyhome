# Development management

The primary page manages projects and files; process termination belongs to CPU/Memory. Project inspection inventories file counts, logical bytes, recognized generated artifacts, and project-local AI instructions, rules, memories and agent definitions. It combines multiple tools referencing the same folder. Newly found projects remain unselected. Read-only connection refresh never changes the user's cleanup filter.

Cleanup choices are generated caches (default), project AI context, or whole project. Context means explicit project-local instruction/configuration paths; global conversation transcripts, account databases and tool state indexes are excluded. Managed worktrees are inventoried but their owner bookkeeping is not modified by raw folder deletion. Entire Git worktrees and context directories containing nested project markers are protected. Retention and active-owner checks apply to all scopes, with revalidation before Trash movement. Selection/settings are rechecked before execution. The default optional “remote backup required” filter for whole-project cleanup checks live remote refs for HEAD and all local branches/tags, clean working tree, stash, reflog-only work, linked worktrees, submodules, LFS attributes and ignored local files. With that filter on, network failure or unknown backup status preserves the folder; remote status is rechecked just before moving it. Cached remote-tracking refs alone do not establish backup. Users can explicitly turn the filter off to move unbacked local work to Trash; changing that choice clears the old plan and disables automation until reconfirmed. Running-project and retention protections remain separate.

## What integration means

- Codex: local thread SQLite cwd/activity index, current process directories and managed-worktree inventory. No native thread archive or cloud conversation API.
- Claude Code: bounded local JSONL metadata headers for cwd/activity. Claude desktop/cloud conversations are not connected.
- Cursor: local workspace metadata and activity timestamps. Chat contents are not rewritten.
- Herdr/Orca/cmux/tmux: read-only local CLI metadata adapters plus process directories. Availability and structured response checks are displayed; an executable alone is not a successful connection.
- Hermes and other CLI/editor tools: current process directories and explicit folder links; no assumed private session database schema.
- ChatGPT: explicit local folder links only. ChatGPT cloud Projects/chats are not supported.

This is local project/file integration, not an AI context-window compactor. Removing files reclaims disk space; it does not by itself free RAM used by running tools. Credentials and chat contents are not sent anywhere.

Primary references: https://code.claude.com/docs/en/sessions, https://github.com/openai/codex, https://herdr.dev/, https://www.onorca.dev/.
