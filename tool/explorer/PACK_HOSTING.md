# GTO Explorer — pack hosting (Cloudflare R2)

Hosts the ~51 GB of explorer packs so the **Study tab lights up in prod**. The
app fetches packs over HTTP from a public base URL; when packs are discoverable
the Study tab appears automatically (`kDebugMode || catalog.isNotEmpty`) — no
code change beyond setting the URL.

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
first impression). Same logic per scenario when staging.

**Edge cache:** `catalog.json` (and the index files) sit behind Cloudflare's
edge cache. After re-uploading them, purge the URLs (dashboard → Caching →
Purge, or just wait out the TTL) — a stale catalog serves the OLD scenario
list, and a stale scenario index can list spots whose packs moved. The pack
chunks themselves are content-stable (a spot's files never change in place),
so only the three index-file kinds need purging.

**Why R2:** ~$0.62/mo storage (10 GB free, then $0.015/GB) and **zero egress** —
the explorer downloads chunks constantly. tablelab.app is already on Cloudflare,
so a `packs.tablelab.app` custom domain → R2 bucket is clean.

Recommended: **validate with ONE scenario first** (steps flagged “[STAGED]”),
prove the hosted path in a real prod build, then upload the rest.

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
small files → high concurrency). **[STAGED]** first:
```
rclone copy ~/tlpacks/srp_late_v_bb r2:tablelab-packs/srp_late_v_bb \
  --transfers 32 --checkers 32 --progress
rclone copyto ~/tlpacks/index/srp_late_v_bb.json \
  r2:tablelab-packs/index/srp_late_v_bb.json --progress
rclone copyto ~/tlpacks/index.json r2:tablelab-packs/index.json --progress
rclone copyto ~/tlpacks/catalog.json r2:tablelab-packs/catalog.json --progress
```
Then the rest (or everything at once — rclone uploads the pack dirs alongside
the index files, which is fine as long as a FINAL `catalog.json` copy runs
last):
```
rclone copy ~/tlpacks r2:tablelab-packs \
  --transfers 32 --checkers 32 --progress \
  --exclude "*.tmp" --exclude "catalog.json"
rclone copyto ~/tlpacks/catalog.json r2:tablelab-packs/catalog.json --progress
```
`rclone copy` is idempotent/resumable — safe to re-run.

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

## Cost
Storage 51 GB → ~$0.62/mo (10 GB free + 41 GB × $0.015). Egress: **$0**. Class-A
(writes) one-time on upload; Class-B (reads) are cheap and only on real usage.
