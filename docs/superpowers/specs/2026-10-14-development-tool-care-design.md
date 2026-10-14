# Development tool care

User intent: manage storage and live resource use created by all connected development tools, including editors, agent CLIs and orchestrators. The default Development page must show tools and actionable cleanup rather than a project-size chart.

Keep all existing AITool categories. Integration remains local and capability labels must distinguish history, CLI metadata and explicit folder links. Add a common storage adapter for known macOS app cache/log locations and explicit Codex/Claude diagnostic log and OpenCode cache locations. Scan metadata only, never session bodies, credentials, databases, project rules, sources or managed worktrees. Unsupported storage paths remain visibly unconfirmed; project folder connections remain available for every tool.

Each row shows tool name, connection status, recognized cache/log bytes, eligible bytes, current CPU/RAM and process count. Selecting a row shows exact candidates, blocked reasons and review actions. File cleanup is manual, moves only old inactive-tool files to Trash, validates ownership, paths, ancestor identities, modification age and live processes immediately before execution. Default retention is 14 days; use existing retention setting. Recently changed files, links, databases and nested project/session paths are excluded. Cancellation invalidates the plan. Shared roots are deduplicated and protected if any owner is running.

Memory pressure must never start file cleanup. Sustained pressure produces a task-review notice with a cooldown. Existing persisted project-pressure automation is disabled during migration. CLI pause/resume/stop remains explicit through the existing identity-checked controller; pause retains RAM. GUI app termination remains in CPU/Memory. Do not invent an idle/orphan judgment or cloud-task control.

Use the repository's donyhome-design skill, Theme/DonyControls, 64pt tool rows, native confirmation and real native screenshots. No real personal file cleanup or process stopping during verification. Tests use disposable files and simulated process state.
