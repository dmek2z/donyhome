#!/bin/zsh
# Install the bundled, self-contained Codex design skill on this Mac.
set -euo pipefail
dony_repo="${0:A:h:h}"
dony_destination="${CODEX_HOME:-$HOME/.codex}/skills"
if (( $# )); then
    if [[ $# != 2 || "$1" != "--dest" ]]; then
        print -u2 -- "Usage: zsh scripts/install-design-skill.sh [--dest skills-directory]"
        exit 2
    fi
    dony_destination="$2"
fi
dony_source="$dony_repo/.agents/skills/donyhome-design"
[[ -f "$dony_source/SKILL.md" && -f "$dony_source/references/design-system.md" ]] || { print -u2 -- "Bundled design skill is missing"; exit 1; }
mkdir -p "$dony_destination"
dony_target="$dony_destination/donyhome-design"
[[ ! -L "$dony_target" ]] || { print -u2 -- "Refusing to replace a symbolic-link skill"; exit 1; }
dony_stage="$(mktemp -d "$dony_destination/.donyhome-design.XXXXXX")"
trap 'rm -rf "$dony_stage"' EXIT
ditto "$dony_source" "$dony_stage/skill"
if [[ -e "$dony_target" ]]; then
    dony_backup_directory="${dony_destination:A:h}/skill-backups"
    mkdir -p "$dony_backup_directory"
    dony_backup="$(mktemp -d "$dony_backup_directory/donyhome-design.XXXXXX")"
    mv "$dony_target" "$dony_backup/skill"
    if ! mv "$dony_stage/skill" "$dony_target"; then
        mv "$dony_backup/skill" "$dony_target"
        exit 1
    fi
else
    mv "$dony_stage/skill" "$dony_target"
fi
print -r -- "Installed: $dony_target"
print -r -- "Available to Codex from the next conversation turn."
