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
    for match in re.finditer(r'(?m)^(?:(?:private|fileprivate|public|internal)\s+)?struct\s+(\w+Row)\b', source):
        following = re.search(r'(?m)^(?:(?:private|fileprivate|public|internal)\s+)?struct\s+', source[match.end():])
        end = match.end() + following.start() if following else len(source)
        if re.search(r'\.panel\s*\(', source[match.start():end]):
            errors.append(f'{path.relative_to(args.root)}: {match.group(1)} must be a compact row; put the panel around the list, not each item')
    if path.name == 'DonyControls.swift':
        continue
    for number, line in enumerate(source.splitlines(), 1):
        if re.search(r'\.menu(?:Style|Indicator)\s*\(', line) or re.search(r'(?<![\w])Menu\s*\{', line):
            errors.append(f'{path.relative_to(args.root)}:{number}: use DonyMenuButton/DonyIconMenu; menu chrome belongs in DonyControls.swift')
for relative in ['AGENTS.md', '.agents/skills/donyhome-design/SKILL.md', 'docs/design-system.md']:
    if not (args.root / relative).is_file():
        errors.append(f'{relative}: missing maintained design instructions')
if errors:
    print('\n'.join(errors))
    raise SystemExit(1)
print('Design rules passed: screen menu chrome is centralized; design skill and rules are present.')
