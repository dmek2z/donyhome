#!/usr/bin/env python3
"""Guard the shared failure that blocks hosted SwiftUI button transactions."""
from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
failures = []
for path in sorted((root / 'Sources/DonyClean').glob('*.swift')):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if re.search(r'\b(?:runModal|runModalSession|stopModal)\s*\(', line):
            failures.append(f'{path.relative_to(root)}:{number}: synchronous modal loop holds the SwiftUI action')
if failures:
    print('\n'.join(failures))
    raise SystemExit(1)
print('UI action guard passed: no nested synchronous modal loops')
