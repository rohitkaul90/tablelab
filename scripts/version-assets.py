#!/usr/bin/env python3
"""Cache-bust the marketing site's shared CSS/JS by content hash.

WHY THIS EXISTS
---------------
Cloudflare serves /site.css and /site.js with `Cache-Control: max-age=14400`
(4 hours) while the HTML is only 600s and `cf-cache-status: DYNAMIC`. So after a
deploy the HTML updates immediately but the CSS/JS keep serving the OLD file for
up to four hours. That silently shipped a broken-looking consent banner on
2026-07-26 and previously made a nav change appear not to deploy.

Appending `?v=<content-hash>` makes the edge treat a changed file as a new
object, so changes go live instantly while the long cache lifetime still helps
repeat visitors. The hash is derived from the file contents, so there is no
version number to remember bumping — if the file did not change, nothing changes.

USAGE
-----
    python scripts/version-assets.py           # rewrite web/ and docs/
    python scripts/version-assets.py --check   # exit 1 if out of date (for CI)

RUN IT whenever web/site.css or web/site.js changes, before committing.
"""
from __future__ import annotations

import argparse
import hashlib
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ("site.css", "site.js")
# Only the real tags — never the prose mentions of "site.js" inside HTML comments.
PATTERNS = {
    "site.css": re.compile(r'(<link rel="stylesheet" href="/site\.css)(\?v=[0-9a-f]+)?(">)'),
    "site.js": re.compile(r'(<script src="/site\.js)(\?v=[0-9a-f]+)?(" defer></script>)'),
}


def short_hash(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:10]


def html_files() -> list[pathlib.Path]:
    out: list[pathlib.Path] = []
    for base in ("web", "docs"):
        d = ROOT / base
        if not d.is_dir():
            continue
        out += sorted(d.glob("*.html")) + sorted(d.glob("blog/*.html"))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true",
                    help="report drift without writing; exit 1 if any file is stale")
    args = ap.parse_args()

    # Hash the source copies in web/. docs/ is a build artifact of web/, so the
    # two must carry the same version for the pair to stay byte-identical.
    hashes = {}
    for asset in ASSETS:
        src = ROOT / "web" / asset
        if not src.exists():
            print(f"error: {src} not found", file=sys.stderr)
            return 2
        hashes[asset] = short_hash(src)

    changed, stale = [], []
    for f in html_files():
        # Read/write as bytes so CRLF line endings survive untouched.
        text = f.read_bytes().decode("utf-8")
        new = text
        for asset, pat in PATTERNS.items():
            new = pat.sub(lambda m, a=asset: f"{m.group(1)}?v={hashes[a]}{m.group(3)}", new)
        if new != text:
            stale.append(f.relative_to(ROOT))
            if not args.check:
                f.write_bytes(new.encode("utf-8"))
                changed.append(f.relative_to(ROOT))

    for asset, h in hashes.items():
        print(f"  {asset:<9} -> ?v={h}")

    if args.check:
        if stale:
            print(f"\nSTALE: {len(stale)} file(s) need re-versioning:")
            for f in stale:
                print(f"  {f}")
            print("\nRun: python scripts/version-assets.py")
            return 1
        print("\nAll HTML files carry the current asset versions.")
        return 0

    print(f"\nupdated {len(changed)} file(s)" if changed else "\nalready up to date — nothing changed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
