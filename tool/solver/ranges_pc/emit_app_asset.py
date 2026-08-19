#!/usr/bin/env python3
"""Emit the app's bundled preflop-range asset from the normalized PC dataset.

Reads  normalized/pc_normalized.json.gz  (run normalize.py first),
writes  ../../../assets/pc_ranges.json  (minified).

Slice shipped in-app (8-max is canonical per RANGE_MIGRATION_PLAN.md):
  - cash 8max, both depths (100bb + 200bb), every node
  - mtt  8max at the five PDF depths (80/50/30/20/12bb), every node
Everything else (6max, HU, the full 2-100bb MTT ladder) stays tooling-side in
the normalized file; solver tooling reads that directly, never this asset.

Per-chart `src` provenance is dropped from the asset (kept in normalized).
"""
import gzip
import io
import json
import pathlib

HERE = pathlib.Path(__file__).parent
ASSET = HERE.parent.parent.parent / 'assets' / 'pc_ranges.json'
MTT_BBS = {80, 50, 30, 20, 12}

with gzip.open(HERE / 'normalized' / 'pc_normalized.json.gz', 'rt', encoding='utf-8') as f:
    data = json.load(f)

sel = []
for c in data['charts']:
    keep = (c['game'] == 'cash' and c['table'] == '8max') or \
           (c['game'] == 'mtt' and c['table'] == '8max' and c['bbs'] in MTT_BBS)
    if not keep:
        continue
    c = dict(c)
    c.pop('src', None)
    sel.append(c)

sel.sort(key=lambda c: c['id'])
out = {'version': data['version'], 'source': data['source'], 'charts': sel}
io.open(ASSET, 'w', encoding='utf-8', newline='').write(
    json.dumps(out, separators=(',', ':')))
print(f'wrote {ASSET} — {len(sel)} charts, {ASSET.stat().st_size} bytes')
