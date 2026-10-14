#!/usr/bin/env python3
"""Reject screen-local menu chrome; native submenus remain permitted."""
import argparse
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parent.parent)
args = parser.parse_args()
screens = args.root / 'Sources' / 'DonyClean'
errors = []
if not screens.is_dir():
    parser.error('Sources/DonyClean is missing')
for path in sorted(screens.glob('*.swift')):
    source = path.read_text()
    # Bound the remaining legacy debt; new screens cannot add text dropdowns.
    legacy_menu_counts = {}
    text_menus = list(re.finditer(r'\bDonyMenuButton\s*\(', source))
    if path.name != 'DonyControls.swift' and len(text_menus) > legacy_menu_counts.get(path.name, 0):
        errors.append(f'{path.relative_to(args.root)}: text dropdowns are forbidden in new/development/resource UI; use direct actions, chips or settings')
    native_menus = len(re.findall(r'\bMenu\s*\(', source))
    # One secondary pin-key submenu remains inside ClipboardItemRow's icon menu.
    allowed_submenus = 1 if path.name == 'ClipboardView.swift' else 0
    if path.name != 'DonyControls.swift' and (native_menus > allowed_submenus or re.search(r'\bPicker\s*\(', source)):
        errors.append(f'{path.relative_to(args.root)}: native dropdowns are forbidden in primary controls')
    for match in re.finditer(r'(?m)^(?:(?:private|fileprivate|public|internal)\s+)?struct\s+(\w+Row)\b', source):
        following = re.search(r'(?m)^(?:(?:private|fileprivate|public|internal)\s+)?struct\s+', source[match.end():])
        end = match.end() + following.start() if following else len(source)
        if re.search(r'\.panel\s*\(', source[match.start():end]):
            errors.append(f'{path.relative_to(args.root)}: {match.group(1)} must be a compact row; put the panel around the list, not each item')
    if path.name == 'DonyControls.swift':
        for label in re.finditer(r'Menu\(content:\s*content\)\s*\{([^}]*)\}', source):
            if re.search(r'\b(?:DonyIcon|Image)\s*\(', label.group(1)):
                errors.append('DonyControls.swift: keep native Menu labels text-only; draw sized icons outside native label conversion')
        continue
    for number, line in enumerate(source.splitlines(), 1):
        if re.search(r'\.menu(?:Style|Indicator)\s*\(', line) or re.search(r'(?<![\w])Menu\s*\{', line):
            errors.append(f'{path.relative_to(args.root)}:{number}: use direct controls/DonyIconMenu; menu chrome belongs in DonyControls.swift')
for relative in ['AGENTS.md', '.agents/skills/donyhome-design/SKILL.md', 'docs/design-system.md', '.agents/skills/donyhome-design/references/design-system.md', 'scripts/install-design-skill.sh']:
    if not (args.root / relative).is_file():
        errors.append(f'{relative}: missing maintained design instructions')
spec = args.root / 'docs/design-system.md'
reference = args.root / '.agents/skills/donyhome-design/references/design-system.md'
if spec.is_file() and reference.is_file() and spec.read_bytes() != reference.read_bytes():
    errors.append('donyhome-design: portable reference differs from docs/design-system.md; update both')
skill = args.root / '.agents/skills/donyhome-design'
for document in skill.rglob('*.md'):
    for match in re.finditer(r'\[[^\]]*\]\(([^)]+)\)', document.read_text()):
        target = match.group(1).split('#', 1)[0]
        if not target or re.match(r'[a-zA-Z][a-zA-Z0-9+.-]*:', target):
            continue
        resolved = (document.parent / target).resolve()
        if not resolved.is_relative_to(skill.resolve()) or not resolved.is_file():
            errors.append(f'donyhome-design: broken portable reference {target} in {document.name}')
if errors:
    print('\n'.join(errors))
    raise SystemExit(1)
print('Design rules passed: direct development/resource controls, centralized chrome, portable skill reference.')
