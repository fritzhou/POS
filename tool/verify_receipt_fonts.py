#!/usr/bin/env python3
"""Verify retained receipt font assets against their recorded source provenance."""
from pathlib import Path
import hashlib
import json

root = Path(__file__).resolve().parents[1]
fonts = root / 'assets/fonts'
provenance = json.loads((fonts / 'PROVENANCE.json').read_text())
expected = {'NotoSans-Regular.ttf', 'NotoSans-Bold.ttf', 'NexaPOS-CJK-Regular.ttf'}
assert set(provenance['packaged_fonts']) == expected
for name, checksum in provenance['packaged_fonts'].items():
    assert len(checksum) == 64
    assert hashlib.sha256((fonts / name).read_bytes()).hexdigest() == checksum, name
for name in ['NOTO-LICENSE.txt', 'NOTO-CJK-LICENSE.txt']:
    license_text = (fonts / name).read_text()
    assert 'SIL OPEN FONT LICENSE' in license_text.upper()
print('Offline receipt font assets and licenses verified; no runtime font download.')
