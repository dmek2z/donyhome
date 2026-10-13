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
    if path.name == 'DonyControls.swift':
        continue
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if re.search(r'\.menu(?:Style|Indicator)\s*\(', line) or re.search(r'(?<![\w])Menu\s*\{', line):
            errors.append(f'{path.relative_to(args.root)}:{number}: use DonyMenuButton/DonyIconMenu; menu chrome belongs in DonyControls.swift')
for relative in ['AGENTS.md', '.agents/skills/donyhome-design/SKILL.md', 'docs/design-system.md']:
    if not (args.root / relative).is_file():
        errors.append(f'{relative}: missing maintained design instructions')
if errors:
    print('\n'.join(errors))
    raise SystemExit(1)
print('Design rules passed: screen menu chrome is centralized; design skill and rules are present.')
