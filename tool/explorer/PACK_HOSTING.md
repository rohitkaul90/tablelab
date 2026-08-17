# GTO Explorer — pack hosting (Cloudflare R2)

Hosts the explorer packs so the **Study tab lights up in prod**. The
app fetches packs over HTTP from a public base URL; when packs are discoverable
the Study tab appears automatically (`kDebugMode || catalog.isNotEmpty`) — no
code change beyond setting the URL.

> **✅ FULL-DENSITY LIVE — pack-density campaign complete 2026-08-11.** All
> **26,325 pack-spots** are solved and hosted at `packs.tablelab.app`: **5
> scenarios × 5,265 spots each** (1,755 suit-isomorphic canonical flops × 3 SPR
> buckets — srp_late/middle/early/sb_v_bb shallow/medium/deep,
> `3bp_bb_v_btn` committed/shallow/medium), 'river' bet profile, ≤0.5%
> exploitability, `kReachEpsilon` 5e-3 reach pruning, minified manifests.
> Packs are generated from TLSD binary dumps (PR #59) and were **streamed to
> R2 directly from the fleet boxes** (PR #62 — see "Fleet upload" below). The
> v2 index layout is live: `catalog.json` serves all 5 × 5,265; the legacy
> `index.json` carries all 26,325 for old clients. The previous
> 78-representative-spot legacy packs were superseded and their
> non-canonical-named dirs purged (see "Campaign closeout" below). Storage
> is ~5–7 TB (the "~51 GB / 312 spots" figures elsewhere in older docs are
> the pre-campaign era).

- **App side (done):** `lib/explorer/http_packs.dart` (`HttpPackSource` +
  `HostedSpotDiscovery`), wired into `explorerProvider.init()` (hosted first,
  local `~/tlpacks` scan as dev fallback). URL in
  `lib/config/explorer_config.dart`.
- **Data:** `~/tlpacks` — the solved spots + the generated discovery indexes.

## Index layout (v2 — two-level, lazy)

```
<root>/catalog.json            { version: 2, scenarios: [{key, spots, index}] }
<root>/index/<scenario>.json   { version: 2, scenario, spots: [{flop, spr, path}] }
<root>/index.json              { version: 1, spots: [...] }   ← legacy, ALL spots
```

The client fetches the tiny `catalog.json` at startup (the Study tab gates on
it) and each scenario's spot list **on demand** — a 26k-spot fleet never rides
one multi-MB index fetch. Clients shipped before the v2 layout fetch only the
legacy `index.json`; keep emitting/uploading it until those builds age out
(`gen_pack_index.dart --no-legacy` opts out). A host with no `catalog.json`
still works on new clients (they fall back to `index.json` and group it in
memory).

**Upload ORDER contract — packs → scenario indexes → catalog LAST.** Each file
must only ever reference already-uploaded content: a spot listed in a scenario
index must have its pack chunks live, and a scenario listed in the catalog must
have its index live. Uploading the catalog first would advertise scenarios
whose index fetch 404s (the client shows a retry state — not fatal, but a bad
first impression). **Corollary for staging:** `catalog.json` and the legacy
`index.json` are ALWAYS full-scan, so they may only be uploaded once EVERY
scenario they advertise has its packs (and scenario index) live — a staged
single-scenario upload ships packs + that one `index/<scenario>.json` and
nothing else. On a first-time host, stage all scenarios' packs before the
first `catalog.json`/`index.json` upload.

**Edge cache:** `catalog.json` (and the index files) sit behind Cloudflare's
edge cache. After re-uploading them, purge the URLs (dashboard → Caching →
Purge, or just wait out the TTL) — a stale catalog serves the OLD scenario
list, and a stale scenario index can list spots whose packs moved. The pack
chunks themselves are content-stable (a spot's files never change in place),
so only the three index-file kinds need purging.

**Why R2:** cheap storage ($0.015/GB-mo after 10 GB free) and **zero read
egress** — the explorer downloads chunks constantly. tablelab.app is already on
Cloudflare, so a `packs.tablelab.app` custom domain → R2 bucket is clean.

For a FUTURE first-time host: **validate with ONE scenario first** (steps
flagged “[STAGED]”), prove the hosted path in a real prod build, then upload
the rest. (Done for the current host — the full-density fleet is live.)

---

## 1. Create the R2 bucket
Cloudflare dashboard → **R2** → *Create bucket* → name `tablelab-packs`
(location: Automatic). (First use of R2 prompts a one-time billing enable — R2
has no egress fees.)

## 2. Create an API token (for rclone)
R2 → *Manage R2 API Tokens* → *Create API token* → **Object Read & Write**,
scoped to `tablelab-packs`. Save the **Access Key ID**, **Secret Access Key**,
and your **Account ID** (the token page shows the S3 endpoint
`https://<ACCOUNT_ID>.r2.cloudflarestorage.com`).

## 3. Configure rclone
Install rclone (`winget install Rclone.Rclone` / `choco install rclone`), then
`rclone config` → `n` (new remote):
- name: `r2`
- storage: `s3`
- provider: `Cloudflare`
- access_key_id / secret_access_key: from step 2
- endpoint: `https://<ACCOUNT_ID>.r2.cloudflarestorage.com`
- leave region blank; accept defaults.

Verify: `rclone lsd r2:` should list `tablelab-packs`.

## 4. Generate the indexes + upload

Generate the indexes (re-run whenever packs change). The catalog + legacy
index are always FULL-scan; `onlyScenario` only scopes which per-scenario
index files are rewritten:
```
# full fleet
dart run tool/explorer/gen_pack_index.dart
# [STAGED] rewrite one scenario's index (catalog/legacy still cover all):
dart run tool/explorer/gen_pack_index.dart ~/tlpacks srp_late_v_bb
```

Upload in the CONTRACT ORDER (packs → scenario indexes → catalog last; many
small files → high concurrency). **[STAGED]** — packs + that scenario's index
ONLY. Do **not** upload `catalog.json` or the legacy `index.json` yet: both are
always full-scan, so they advertise EVERY scanned scenario, including ones
whose packs aren't live yet (on a first-time host, stage all scenarios' packs
before the first catalog/legacy upload):
```
rclone copy ~/tlpacks/srp_late_v_bb r2:tablelab-packs/srp_late_v_bb \
  --transfers 32 --checkers 32 --progress
rclone copyto ~/tlpacks/index/srp_late_v_bb.json \
  r2:tablelab-packs/index/srp_late_v_bb.json --progress
```
Full upload — packs FIRST (exclude every index-file kind: a mid-upload client
must never fetch an index listing chunks that aren't live yet), then the
scenario indexes, then the legacy index, then `catalog.json` LAST:
```
rclone copy ~/tlpacks r2:tablelab-packs \
  --transfers 32 --checkers 32 --progress \
  --exclude "*.tmp" --exclude "catalog.json" --exclude "index.json" \
  --exclude "index/**"
rclone copy ~/tlpacks/index r2:tablelab-packs/index --progress
rclone copyto ~/tlpacks/index.json r2:tablelab-packs/index.json --progress
rclone copyto ~/tlpacks/catalog.json r2:tablelab-packs/catalog.json --progress
```
`rclone copy` is idempotent/resumable — safe to re-run. (If the generator ran
with `--no-legacy` there is no `index.json` — it deletes a stale local copy
precisely so this step can't re-upload an outdated one; skip that line.)

> ⚠️ **Do NOT set `Content-Encoding: gzip`** on the `.bin.gz` files. The client
> receives raw gzipped bytes and gunzips them itself (`GZipDecoder`). rclone
> does not set that header by default — good. If you ever add
> `--header-upload "Content-Encoding: gzip"`, the browser will transparently
> decompress and the client will then double-decompress and fail. Verify in
> step 7 that `curl -I` shows **no** `content-encoding` header.

## 5. Public access — custom domain
R2 → `tablelab-packs` → **Settings → Public access → Custom Domains** →
*Connect Domain* → `packs.tablelab.app`. Cloudflare auto-creates the DNS + TLS
(tablelab.app is already on Cloudflare). Packs are then public at
`https://packs.tablelab.app/...`.

(Alternative for a quick test: enable the **r2.dev** public URL — rate-limited,
fine for validation, not for production traffic.)

## 6. CORS (the web app is cross-origin)
R2 → `tablelab-packs` → **Settings → CORS policy** → add:
```json
[
  {
    "AllowedOrigins": ["https://tablelab.app", "https://www.tablelab.app"],
    "AllowedMethods": ["GET"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 3600
  }
]
```
(For local `flutter run -d chrome` testing add your dev origin too, e.g.
`http://localhost:*` — or just test the mobile/desktop build which isn't
CORS-gated.)

## 7. Verify the host
```
curl -s https://packs.tablelab.app/catalog.json | head
curl -s https://packs.tablelab.app/index/srp_late_v_bb.json | head
curl -sI https://packs.tablelab.app/index.json | grep -iE "HTTP/|content-type|content-encoding"
curl -sI "https://packs.tablelab.app/srp_late_v_bb/7s5s2s_deep/flop.bin.gz" | grep -iE "HTTP/|content-encoding"
```
Expect `200`s, `catalog.json` listing scenarios / the scenario index listing
spots, and **no** `content-encoding: gzip` on the `.gz`.

## 8. Point the app at it + deploy
Set the URL in `lib/config/explorer_config.dart`:
```dart
const String kPacksBaseUrl =
    String.fromEnvironment('TLPACKS_URL', defaultValue: 'https://packs.tablelab.app');
```
Commit + push to `main` → `deploy-web.yml` rebuilds → the Study tab appears in
prod (init fetches the hosted `catalog.json` → `catalog.isNotEmpty` → tab
shows). **Per-scenario deploy contract:** adding a scenario later = upload its
packs, then `index/<scenario>.json`, then the regenerated `index.json` +
`catalog.json` (last — see the order contract above); adding spots to an
existing scenario = upload the packs, then re-upload that scenario's index (+
legacy `index.json`/`catalog.json` for the counts). The app picks changes up
on next launch — no client deploy.

Test before committing the real URL:
`flutter run -d chrome --dart-define=TLPACKS_URL=https://packs.tablelab.app`.

## Fleet upload (box → R2, full-density campaigns)

The full-density pack fleet (5 scenarios × 5,265 spots, ~350 MB avg/spot) is
far too big to pull to the operator laptop — solve boxes upload **directly to
R2** instead. Launch with:

```
.\tool\solver\vcpu-solve.ps1 -EmitPack -PackR2Remote r2:tablelab-packs `
  -GridArgs "--no-write --ignore-cache --parallel N" ... -PullAndTerminate
```

`-PackR2Remote` (requires `-EmitPack`) makes the launcher: install rclone on
the box, push the operator's `%APPDATA%\rclone\rclone.conf`, and run
`tool/solver/box_pack_uploader.sh` in its own tmux session (`uploader`, log
`~/uploader.log`) alongside the solve. Every 10 min the uploader:

1. finds complete spot packs — `<packsRoot>/<scenario>/<spotDir>/manifest.json`
   present (freq_grid writes the manifest atomically LAST, so presence proves a
   whole pack) that still hold `*.bin.gz` chunks;
2. `rclone copy`s each to `<remote>/<scenario>/<spotDir>/` — the **exact hosted
   layout above**, so no post-processing is needed;
3. verifies the **remote** manifest landed, then deletes the LOCAL chunk files
   + emptied subdirs but **KEEPS the local `manifest.json`**.

**Marker semantics.** The surviving local manifest is freq_grid's
`--ignore-cache` pack-existence resume marker — the box's disk stays bounded
(chunks leave as they upload) while a re-run on the SAME box still skips
uploaded spots. A transient rclone failure never kills the loop; the spot
retries next cycle (`rclone copy` is idempotent).

**Resume seed (spot reclaims).** Before the solve starts, the launcher pulls
just the remote manifests (`rclone copy <remote>/<scenario>/ ~/packs/<scenario>/
--include "*/manifest.json"`) for each scenario in `-Scenario` — a
reclaim-relaunch onto a **fresh** box materializes the completion markers and
skips everything already uploaded, losing only in-flight spots.

**Completion.** Under `-PullAndTerminate` the pack tar+scp pull is SKIPPED
entirely: after `BATCH DONE` the launcher touches `~/solve-done` (the
uploader's exit condition), waits for the uploader's final sweep
(`UPLOAD SWEEP DONE (<n> spots uploaded total)`, timeout 1 h), then terminates.
A sweep timeout leaves the box RUNNING (data preservation) — finish manually.
Without `-PullAndTerminate`, touch `~/solve-done` yourself when the solve ends.

**Boxes touch ONLY pack dirs — never `index/`, `index.json`, or
`catalog.json`.** The upload-order contract at the top of this doc is preserved
by construction: packs stream up first, and the operator regenerates + uploads
the scenario index (then legacy index + catalog LAST) only **after** a
scenario's packs are fully live. For index generation against R2 (no local
chunks), sync the remote manifests down and run `gen_pack_index.dart` over
that tree, or pull the scenario's manifests the same `--include` way.

Debug: `bash tool/solver/box_pack_uploader.sh <packsRoot> <remote> --dry-run`
prints what it would upload/delete without acting.

## Campaign closeout (reconcile → purge legacy → index regen)

The runbook that finalized the 2026-08 full-density campaign — reuse it for any
future fleet campaign. Order matters: reconcile first, delete legacy orphans
**before** regenerating indexes, and only then upload indexes in the contract
order.

1. **Reconcile canonical dirs.** Verify every expected `<scenario>/<flop>_<spr>`
   spot is complete on R2 via a **dirs-only listing** (`rclone lsf --dirs-only`
   per scenario) plus a **direct manifest GET per dir**
   (`<dir>/manifest.json` — presence proves a whole pack, since the manifest is
   written atomically LAST). A recursive `--include "*/manifest.json"` object
   listing is **INFEASIBLE at this scale** (60M+ objects — the sweep enumerates
   every chunk); listing directories and probing manifests directly is the only
   tractable audit.
2. **Delete legacy orphans BEFORE index regen.** Purge every dir not in the
   canonical `<flop>_<spr>` name set — the 78-representative-spot legacy packs,
   plus strays (each legacy scenario carried a recurring `Th8h7c_shallow`).
   Doing this before regen guarantees the fresh indexes can never list a
   soon-to-be-deleted spot.
3. **Regenerate indexes over a manifests-only tree.** Pull just the remote
   manifests down (the `--include "*/manifest.json"` copy per scenario is fine
   here — it's a scoped copy, not a full-bucket sweep) into a durable local
   copy at **`~/tlpacks/_closeout-tree`**, and run `gen_pack_index.dart` over
   that tree. Keep the tree — it's the cheap local mirror for future
   re-indexing without another R2 sweep.
4. **Upload in the unchanged contract order:** packs → `index/**` → legacy
   `index.json` → `catalog.json` **LAST** (see the order contract at the top).
   Purge the edge cache for the three index-file kinds after.

**Drains (bulk uploads of a partially-uploaded scenario):** use a **scoped**
`rclone copy <scenario> --ignore-existing --transfers 48` per scenario — never
a whole-root sweep. Note that **file COUNT, not bytes, drives sweep time**:
`--ignore-existing` still stats every remote object, so a drain over millions
of already-uploaded chunks is slow even when almost nothing transfers.

## Cost

**Recurring:** full-density storage is ~5–7 TB → ~$75–105/mo at $0.015/GB.
Read egress from R2: **$0**. Class-A (writes) were one-time on upload; Class-B
(reads) are cheap and only on real usage.

**One-time (2026-08 campaign):** solve ≈ **$1,093** spot instance-hours +
**$390** AWS egress + ~**$16** EBS ≈ **$1,495 total**. The egress line was the
unbudgeted lesson: R2 charges nothing to receive, but **AWS charges EC2→R2
egress at ~$0.09/GB**, which added ~+35% on top of instance-hours for a
multi-TB fleet upload — budget it explicitly in any future campaign.
