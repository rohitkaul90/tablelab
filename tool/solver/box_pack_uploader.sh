#!/usr/bin/env bash
# box_pack_uploader.sh - continuous box->R2 explorer-pack uploader (fleet mode).
#
#   bash box_pack_uploader.sh <packsRoot> <r2remote> [--dry-run]
#   e.g. bash box_pack_uploader.sh /home/ubuntu/packs r2:tablelab-packs
#
# Runs ON the solve box (its own tmux session, started by vcpu-solve.ps1 when
# -PackR2Remote is set). Every cycle (10 min) it finds COMPLETE spot packs -
# <packsRoot>/<scenario>/<flopNoSpaces>_<spr>/manifest.json exists (freq_grid's
# generatePack writes the manifest atomically LAST, so its presence proves the
# pack is whole) - that still hold *.bin.gz chunk files, uploads each to
# <r2remote>/<scenario>/<spotDir>/ (the EXACT hosted layout PACK_HOSTING.md
# documents), verifies the remote manifest landed, then deletes the LOCAL
# chunk files + now-empty subdirs but KEEPS the local manifest.json:
#   - local disk stays bounded (a full-density slice would otherwise fill it),
#   - the surviving manifest is freq_grid's --ignore-cache resume marker, so a
#     relaunch onto THIS box still skips the spot.
# It never touches index/, index.json, or catalog.json - the operator
# regenerates + uploads those after each scenario completes (upload-order
# contract in tool/explorer/PACK_HOSTING.md).
#
# Exit: when ~/solve-done exists (touched by the launcher after BATCH DONE, or
# manually), one final sweep runs, then it prints
#   UPLOAD SWEEP DONE (<n> spots uploaded total)
# and exits 0. A transient rclone failure never kills the loop - the spot is
# simply retried next cycle (rclone copy is idempotent).
#
# --dry-run: print what WOULD be uploaded/deleted, act on nothing (no rclone,
# no deletes). Test/override knobs (defaults are the prod values):
#   UPLOADER_DONE_FILE   done marker path      (default $HOME/solve-done)
#   UPLOADER_INTERVAL_S  seconds between sweeps (default 600)

set -u

if [ $# -lt 2 ]; then
  echo "usage: box_pack_uploader.sh <packsRoot> <r2remote> [--dry-run]" >&2
  exit 2
fi
PACKS_ROOT=$1
REMOTE=$2
DRY_RUN=0
if [ "${3:-}" = "--dry-run" ]; then DRY_RUN=1; fi

DONE_FILE=${UPLOADER_DONE_FILE:-$HOME/solve-done}
INTERVAL_S=${UPLOADER_INTERVAL_S:-600}
TOTAL=0

log() { printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }

upload_sweep() {
  # Tolerate a not-yet-created packsRoot (uploader starts alongside the solve).
  if [ ! -d "$PACKS_ROOT" ]; then return 0; fi
  local manifest dir spot scenario chunks
  # Depth 3 = <root>/<scenario>/<spotDir>/manifest.json. Process substitution
  # (not a pipe) so TOTAL survives the loop body; empty finds fall through.
  while IFS= read -r manifest; do
    dir=$(dirname "$manifest")
    spot=$(basename "$dir")
    scenario=$(basename "$(dirname "$dir")")
    # Already uploaded + pruned (manifest kept as the resume marker)? Skip.
    if ! find "$dir" -name '*.bin.gz' -type f -print -quit 2>/dev/null | grep -q .; then
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      chunks=$(find "$dir" -name '*.bin.gz' -type f 2>/dev/null | wc -l)
      log "DRY-RUN would upload $scenario/$spot -> $REMOTE/$scenario/$spot/ then delete $chunks local chunk file(s), keeping manifest.json"
      TOTAL=$((TOTAL + 1))
      continue
    fi
    if ! rclone copy "$dir" "$REMOTE/$scenario/$spot/" --transfers 16 --checkers 8 --exclude '*.tmp'; then
      log "WARN rclone copy failed for $scenario/$spot - will retry next cycle"
      continue
    fi
    # Belt-and-braces: only prune local chunks once the remote manifest is
    # verifiably there (a spot whose remote manifest is missing re-uploads
    # next cycle; rclone copy skips the already-transferred chunks).
    if ! rclone lsf "$REMOTE/$scenario/$spot/manifest.json" 2>/dev/null | grep -q '^manifest\.json$'; then
      log "WARN remote manifest not visible for $scenario/$spot after copy - will retry next cycle"
      continue
    fi
    find "$dir" -name '*.bin.gz' -type f -delete 2>/dev/null
    find "$dir" -mindepth 1 -type d -empty -delete 2>/dev/null
    TOTAL=$((TOTAL + 1))
    log "uploaded $scenario/$spot -> $REMOTE/$scenario/$spot/ (chunks pruned, manifest kept)"
  done < <(find "$PACKS_ROOT" -mindepth 3 -maxdepth 3 -type f -name manifest.json 2>/dev/null | sort)
  return 0
}

log "uploader started: packsRoot=$PACKS_ROOT remote=$REMOTE dryRun=$DRY_RUN interval=${INTERVAL_S}s doneFile=$DONE_FILE"
while true; do
  upload_sweep
  if [ -e "$DONE_FILE" ]; then
    # Solve finished mid-sweep may have completed more spots - final sweep.
    # (Skipped in dry-run: nothing was pruned, so it would double-count.)
    if [ "$DRY_RUN" = 0 ]; then upload_sweep; fi
    log "UPLOAD SWEEP DONE ($TOTAL spots uploaded total)"
    exit 0
  fi
  sleep "$INTERVAL_S"
done
