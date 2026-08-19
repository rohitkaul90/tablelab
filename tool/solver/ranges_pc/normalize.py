#!/usr/bin/env python3
"""Normalize the raw PokerCoaching range dataset into TableLab's format.

Reads  raw/pc-{cash,mtt}.json  (gunzip the committed .gz first if absent),
writes normalized/pc_normalized.json.gz  (full charts, canonical schema),
       normalized/index.json             (per-chart catalog + aggregate stats),
       normalized/REPORT.md              (validation report — read this).

Canonical schema per chart:
  id       stable key: {game}_{table}_{bbs}bb_{hero}_{node}[_vs_...][ _nN]
  game     cash | mtt
  table    8max | 6max | hu
  bbs      effective stack in bb
  ante     ante in bb-fraction units as PC reports it (0 for cash)
  hero     seat label (UTG, UTG1, LJ, HJ, CO, BTN, SB, BB)
  node     rfi | vs_open | vs_3bet | vs_4bet | vs_raise_call | vs_limp |
           vs_allin_* (situation HERO faces; PC's 'Folded To' == rfi,
           'Squeeze' == facing raise+cold-call)
  villains involved opponent seats, in PC's order (raiser first)
  sequence PC simpleSequence (preflop line, F/C/R/A per seat in order)
  actions  ordered canonical action ids: "f", "c", "r:<to-bb>", "r", "a:<bb>"
  hands    hand -> [freq per action] aligned to `actions`; null = unreachable
           (all-zero or absent in source; typically excluded by earlier action)
  sizes    {heroBetSize, raiseSize} raw from PC (bb, raise-TO)
  src      {_id, fileName, updateDate} provenance

Dedup: logical key = (game, table, bbs, hero, node, villains, sequence);
newest updateDate wins (then _id); losers listed in index as superseded.
Rows renormalized when |sum-1| <= 0.1 (reported); worse rows nulled+flagged.
"""
import gzip
import io
import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).parent
RAW = HERE / 'raw'
OUT = HERE / 'normalized'

RANKS = 'AKQJT98765432'
ALL_HANDS = []
for i, a in enumerate(RANKS):
    for j, b in enumerate(RANKS):
        if i == j:
            ALL_HANDS.append(a + a)
        elif i < j:
            ALL_HANDS.append(a + b + 's')
for i, a in enumerate(RANKS):
    for j, b in enumerate(RANKS):
        if i < j:
            ALL_HANDS.append(a + b + 'o')

NODE_MAP = {
    'Folded To': 'rfi',
    'Open Raise': 'vs_open',
    '3bet': 'vs_3bet',
    '4bet': 'vs_4bet',
    '5bet': 'vs_5bet',
    'Squeeze': 'vs_raise_call',
    'Limp': 'vs_limp',
    'All-In': 'vs_allin',
    'All-In 3bet': 'vs_allin_3bet',
    'All-In 4bet': 'vs_allin_4bet',
    'All-In 5bet': 'vs_allin_5bet',
    '4bet Jam': 'vs_4bet_jam',      # MTT: facing a 4-bet that is a jam
    'Limp-Raise': 'vs_limp_raise',  # MTT: hero limped, got raised behind
}
TABLE_MAP = {'8Max': '8max', '6Max': '6max', 'HU': 'hu'}
SEAT_MAP = {'UTG+1': 'UTG1', 'UTG+2': 'UTG2'}  # keep others verbatim

LBL_RE = re.compile(r'^([a-z]+)\s*(?:\(([\d.]+)\))?$')


def canon_action(label, bbs):
    """PC label ('f', 'c', 'r', 'r (12)') -> canonical action id."""
    m = LBL_RE.match(label.strip())
    if not m:
        return None
    kind, size = m.group(1), m.group(2)
    if kind in ('f', 'c'):
        return kind
    if kind == 'r':
        if size is None:
            return 'r'
        s = float(size)
        # a raise TO the full effective stack is an all-in
        tag = 'a' if abs(s - bbs) < 0.5 else 'r'
        s_txt = f'{s:g}'
        return f'{tag}:{s_txt}'
    return None


def combos(h):
    return 6 if len(h) == 2 else (4 if h.endswith('s') else 12)


RANK_ORDER = {r: i for i, r in enumerate('23456789TJQKA')}


def expand_hand_token(tok):
    """Expand one excludeHands token to concrete 169-grid hand labels.

    Forms seen in the raw data: '55-22' (pair range), 'J4o-J2o' (kicker range),
    '65o-32o' (diagonal/connector range: both ranks step down), 'Q9s+' (kicker
    ascending), '22+' (pairs ascending), '72' (bare: both 72s and 72o),
    plus plain singles like '52o' / '82s'.
    """
    tok = tok.strip()
    if not tok:
        return []
    if tok.endswith('+'):
        base = tok[:-1]
        if len(base) == 2 and base[0] == base[1]:  # pairs up
            lo = RANK_ORDER[base[0]]
            return [r * 2 for r, i in RANK_ORDER.items() if i >= lo]
        hi, lo = base[0], base[1]
        sfxs = [base[2]] if len(base) > 2 else ['s', 'o']  # 'J2+' = both
        return [hi + k + sfx for sfx in sfxs for k, i in RANK_ORDER.items()
                if RANK_ORDER[lo] <= i < RANK_ORDER[hi]]
    if '-' in tok:
        a, b = [t.strip() for t in tok.split('-', 1)]
        if len(a) == 2 and a[0] == a[1]:  # pair range (a high, b low)
            hi, lo = RANK_ORDER[a[0]], RANK_ORDER[b[0]]
            return [r * 2 for r, i in RANK_ORDER.items() if lo <= i <= hi]
        # Suffix may appear on either end or neither ('72-52' = both variants).
        sfx_a = a[2] if len(a) > 2 else None
        sfx_b = b[2] if len(b) > 2 else None
        sfxs = [sfx_a or sfx_b] if (sfx_a or sfx_b) else ['s', 'o']
        out = []
        for sfx in sfxs:
            if a[0] == b[0]:  # same high card: kicker range
                hi, lo = RANK_ORDER[a[1]], RANK_ORDER[b[1]]
                out += [a[0] + k + sfx for k, i in RANK_ORDER.items()
                        if lo <= i <= hi]
                continue
            # diagonal: equal rank-gap at both ends, step both ranks down
            gap_a = RANK_ORDER[a[0]] - RANK_ORDER[a[1]]
            gap_b = RANK_ORDER[b[0]] - RANK_ORDER[b[1]]
            if gap_a != gap_b:
                raise ValueError(f'unparseable range token {tok!r}')
            ranks = '23456789TJQKA'
            for hi_i in range(RANK_ORDER[a[0]], RANK_ORDER[b[0]] - 1, -1):
                out.append(ranks[hi_i] + ranks[hi_i - gap_a] + sfx)
        return out
    if len(tok) == 2 and tok[0] != tok[1]:  # bare '72': both variants
        return [tok + 's', tok + 'o']
    return [tok]  # pair or explicit single


def expand_exclude(spec):
    out = set()
    for tok in spec.split(','):
        out.update(expand_hand_token(tok))
    return out


def load(name):
    p = RAW / f'{name}.json'
    if p.exists():
        return json.load(io.open(p, encoding='utf-8'))['ranges']
    with gzip.open(p.with_suffix('.json.gz'), 'rt', encoding='utf-8') as f:
        return json.load(f)['ranges']


def main():
    OUT.mkdir(exist_ok=True)
    raw = load('pc-cash') + load('pc-mtt')
    report = []
    skipped = [c for c in raw if 'handsWeights' not in c or not c.get('handsWeights')]
    charts_in = [c for c in raw if c not in skipped]
    report.append(f'- raw entries: {len(raw)}; skipped (no handsWeights): {len(skipped)}')
    for c in skipped:
        report.append(f'  - SKIPPED {c["format"]}/{c["type"]}/{c["bbs"]}bb {c["seat"]} '
                      f'{c["action"]} seq={c.get("simpleSequence")} ({c.get("fileName")})')

    # ── dedup ────────────────────────────────────────────────────────────────
    # Sizes are PART of the identity: the same node solved against a different
    # raise size is a materially different strategy (review finding — 67 groups
    # differed on up to 95/169 hands), so only true re-uploads dedupe.
    def lkey(c):
        return (c['format'], c['type'], c['bbs'], c['seat'], c['action'],
                tuple(c.get('villains') or []), c.get('simpleSequence') or '',
                tuple(c.get('heroBetSize') or []), tuple(c.get('raiseSize') or []))

    groups = {}
    for c in charts_in:
        groups.setdefault(lkey(c), []).append(c)
    canonical, superseded = [], []
    for k, grp in groups.items():
        grp.sort(key=lambda c: (c.get('updateDate') or '', str(c.get('_id'))), reverse=True)
        canonical.append(grp[0])
        superseded += [(grp[0], loser) for loser in grp[1:]]
    report.append(f'- logical charts: {len(canonical)}; superseded duplicates dropped: {len(superseded)}')

    # ── normalize each chart ─────────────────────────────────────────────────
    out_charts = []
    ids_seen = {}
    n_renorm, n_badrow, n_partial = 0, 0, 0
    unknown_actions = set()
    for c in canonical:
        node = NODE_MAP.get(c['action'])
        if node is None:
            unknown_actions.add(c['action'])
            node = 'vs_' + re.sub(r'[^a-z0-9]+', '_', c['action'].lower()).strip('_')
        game = c['format'].lower().replace('cash', 'cash').replace('mtt', 'mtt')
        table = TABLE_MAP[c['type']]
        hero = SEAT_MAP.get(c['seat'], c['seat'])
        villains = [SEAT_MAP.get(v, v) for v in (c.get('villains') or []) if v]
        bbs = c['bbs']

        # collect the chart's canonical action list (stable order: f, c, raises by size, bare r, all-ins)
        labels = []
        for acts in c['handsWeights'].values():
            for a in acts:
                lbl = a.split(':')[0].strip()
                if lbl not in labels:
                    labels.append(lbl)
        acts_canon = []
        for lbl in labels:
            ca = canon_action(lbl, bbs)
            if ca is None:
                unknown_actions.add(lbl)
                continue
            if ca not in acts_canon:
                acts_canon.append(ca)

        def order(a):
            kind = a.split(':')[0]
            size = float(a.split(':')[1]) if ':' in a else 0.0
            return ({'f': 0, 'c': 1, 'r': 2, 'a': 3}.get(kind, 4), size)
        acts_canon.sort(key=order)
        idx = {}
        for lbl in labels:
            ca = canon_action(lbl, bbs)
            if ca is not None:
                idx[lbl] = acts_canon.index(ca)

        if len(c['handsWeights']) != 169:
            n_partial += 1
        # excludeHands = hands hero cannot hold at this node (filtered out by
        # hero's own earlier action). Null them so consumers never read the
        # placeholder fold-1.0 rows the raw data carries — UNLESS the row has
        # genuine non-fold mass, in which case trust the weights and warn.
        excluded = set()
        if c.get('excludeHands'):
            try:
                excluded = expand_exclude(c['excludeHands'])
            except ValueError as e:
                report.append(f'  - EXCLUDE PARSE FAILED ({e}) on {c["seat"]} '
                              f'{c["action"]} {c["bbs"]}bb — exclusions ignored')
        hands = {}
        for h in ALL_HANDS:
            acts = c['handsWeights'].get(h)
            if acts is None:
                hands[h] = None
                continue
            if h in excluded:
                nonfold = sum(float(a.split(':')[1]) for a in acts
                              if not a.strip().startswith('f'))
                if nonfold < 0.005:
                    hands[h] = None
                    continue
                report.append(f'  - EXCLUDE CONTRADICTION kept: {game}/{table}/'
                              f'{bbs}bb {hero} {node} {h} nonfold={nonfold:.2f}')
            row = [0.0] * len(acts_canon)
            ok = True
            for a in acts:
                lbl, _, val = a.partition(':')
                lbl = lbl.strip()
                if lbl not in idx:
                    ok = False
                    continue
                row[idx[lbl]] += float(val)
            s = sum(row)
            if s == 0:
                hands[h] = None
                continue
            if abs(s - 1) > 0.1 or not ok:
                n_badrow += 1
                report.append(f'  - BAD ROW nulled: {game}/{table}/{bbs}bb {hero} {node} {h} sum={s:.3f}')
                hands[h] = None
                continue
            if abs(s - 1) > 0.005:
                row = [v / s for v in row]
                n_renorm += 1
            hands[h] = [round(v, 4) for v in row]

        base_id = f'{game}_{table}_{bbs:g}bb_{hero}_{node}'
        if villains:
            base_id += '_vs_' + '_'.join(villains)
        cid = base_id
        if cid in ids_seen:
            ids_seen[base_id] += 1
            cid = f'{base_id}_n{ids_seen[base_id]}'
        else:
            ids_seen[base_id] = 1

        out_charts.append({
            'id': cid,
            'game': game, 'table': table, 'bbs': bbs,
            'ante': float(c.get('ante') or 0),
            'hero': hero, 'node': node, 'villains': villains,
            'sequence': c.get('simpleSequence') or '',
            'actions': acts_canon,
            'sizes': {'heroBetSize': c.get('heroBetSize'), 'raiseSize': c.get('raiseSize')},
            'hands': hands,
            'src': {'_id': str(c.get('_id')), 'fileName': c.get('fileName'),
                    'updateDate': c.get('updateDate')},
        })

    report.append(f'- rows renormalized (|sum-1| in 0.005..0.1): {n_renorm}')
    report.append(f'- rows nulled as bad (|sum-1| > 0.1 or unparseable): {n_badrow}')
    report.append(f'- charts with <169 hands in source (absent = unreachable): {n_partial}')
    if unknown_actions:
        report.append(f'- UNKNOWN action labels (fallback-slugged): {sorted(unknown_actions)}')

    # ── benchmarks (fail the run if wildly off) ──────────────────────────────
    def find(**kw):
        for ch in out_charts:
            if all(ch.get(k) == v for k, v in kw.items()):
                return ch
        return None

    def share(ch, kinds):
        tot = 0.0
        for h, row in ch['hands'].items():
            if row is None:
                continue
            for a, v in zip(ch['actions'], row):
                if a.split(':')[0] in kinds:
                    tot += v * combos(h)
        return tot / 1326 * 100

    checks = []
    btn = find(game='cash', table='8max', bbs=100, hero='BTN', node='rfi')
    bb = next(
        (ch for ch in out_charts if ch['game'] == 'cash' and ch['table'] == '8max'
         and ch['bbs'] == 100 and ch['hero'] == 'BB' and ch['node'] == 'vs_open'
         and ch['villains'] == ['BTN']), None)
    # A missing anchor is itself a hard failure — it means the node vocabulary
    # drifted (e.g. PC renamed an action and the slug fallback fired), which is
    # exactly what these benchmarks exist to catch.
    if btn is None or bb is None:
        print('\n'.join(report))
        sys.exit('BENCHMARK ANCHOR MISSING: '
                 f'btn_rfi={"ok" if btn else "MISSING"} '
                 f'bb_vs_btn={"ok" if bb else "MISSING"}')
    checks.append(('cash 8max 100bb BTN rfi raise%', share(btn, {'r', 'a'}), 35, 50))
    checks.append(('cash 8max 100bb BB defend% vs BTN open', share(bb, {'c', 'r', 'a'}), 30, 50))
    failed = [(n, v) for n, v, lo, hi in checks if not lo <= v <= hi]
    for n, v, lo, hi in checks:
        report.append(f'- benchmark {n}: {v:.1f} (expect {lo}-{hi}) '
                      f'{"OK" if lo <= v <= hi else "FAIL"}')
    if failed:
        print('\n'.join(report))
        sys.exit(f'BENCHMARK FAILURES: {failed}')

    # ── outputs ──────────────────────────────────────────────────────────────
    payload = {'version': 1,
               'source': 'pokercoaching.com /api/get-training-weights, fetched 2026-08-19',
               'charts': out_charts}
    with gzip.open(OUT / 'pc_normalized.json.gz', 'wt', encoding='utf-8') as f:
        json.dump(payload, f, separators=(',', ':'))

    index = []
    for ch in out_charts:
        index.append({
            'id': ch['id'], 'game': ch['game'], 'table': ch['table'], 'bbs': ch['bbs'],
            'hero': ch['hero'], 'node': ch['node'], 'villains': ch['villains'],
            'sequence': ch['sequence'], 'actions': ch['actions'],
            'raise_pct': round(share(ch, {'r', 'a'}), 1),
            'call_pct': round(share(ch, {'c'}), 1),
        })
    counts = {}
    for ch in out_charts:
        k = f"{ch['game']}/{ch['table']}/{ch['node']}"
        counts[k] = counts.get(k, 0) + 1
    io.open(OUT / 'index.json', 'w', encoding='utf-8', newline='').write(
        json.dumps({'total': len(index), 'byKind': dict(sorted(counts.items())),
                    'charts': index}, indent=1))

    superseded_lines = [
        f'  - {lkeyfmt(w)} superseded {lkeyfmt(l)} (sizes {l.get("heroBetSize")})'
        for w, l in superseded[:40]]
    rep = ['# PC range normalization report', '',
           f'charts out: {len(out_charts)}', ''] + report + ['', '## superseded (first 40)'] + superseded_lines
    io.open(OUT / 'REPORT.md', 'w', encoding='utf-8', newline='').write('\n'.join(rep) + '\n')
    print('\n'.join(rep[:40]))
    print(f'\nwrote {OUT / "pc_normalized.json.gz"} ({len(out_charts)} charts), index.json, REPORT.md')


def lkeyfmt(c):
    return (f'{c["format"]}/{c["type"]}/{c["bbs"]}bb {c["seat"]} {c["action"]} '
            f'vs {c.get("villains")} [{c.get("updateDate") or "no-date"}]')


if __name__ == '__main__':
    main()
