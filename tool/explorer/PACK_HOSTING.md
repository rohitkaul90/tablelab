# GTO Explorer — pack hosting (Cloudflare R2)

Hosts the ~51 GB of explorer packs so the **Study tab lights up in prod**. The
app fetches packs over HTTP from a public base URL; when packs are discoverable
the Study tab appears automatically (`kDebugMode || spots.isNotEmpty`) — no code
change beyond setting the URL.

- **App side (done):** `lib/explorer/http_packs.dart` (`HttpPackSource` +
  `fetchHostedSpots`), wired into `explorerProvider.init()` (hosted first, local
  `~/tlpacks` scan as dev fallback). URL in `lib/config/explorer_config.dart`.
- **Data:** `~/tlpacks` — 312 spots (4 scenarios × 78), + a generated
  `index.json`.

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

## 4. Generate the index + upload

Generate `index.json` (already run once; re-run if packs change):
```
# full (312 spots)
dart run tool/explorer/gen_pack_index.dart
# [STAGED] one scenario only:
dart run tool/explorer/gen_pack_index.dart ~/tlpacks srp_late_v_bb
```

Upload (many small files → high concurrency). **[STAGED]** first:
```
rclone copy ~/tlpacks/srp_late_v_bb r2:tablelab-packs/srp_late_v_bb \
  --transfers 32 --checkers 32 --progress
rclone copyto ~/tlpacks/index.json r2:tablelab-packs/index.json --progress
```
Then the rest (or everything at once):
```
rclone copy ~/tlpacks r2:tablelab-packs \
  --transfers 32 --checkers 32 --progress \
  --exclude "*.tmp"
```
`rclone copy` is idempotent/resumable — safe to re-run. ~51 GB ≈ 1–2 h at
50–100 Mbps up.

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
curl -sI https://packs.tablelab.app/index.json | grep -iE "HTTP/|content-type|content-encoding"
curl -s https://packs.tablelab.app/index.json | head
curl -sI "https://packs.tablelab.app/srp_late_v_bb/7s5s2s_deep/flop.bin.gz" | grep -iE "HTTP/|content-encoding"
```
Expect `200`, `index.json` listing spots, and **no** `content-encoding: gzip` on
the `.gz`.

## 8. Point the app at it + deploy
Set the URL in `lib/config/explorer_config.dart`:
```dart
const String kPacksBaseUrl =
    String.fromEnvironment('TLPACKS_URL', defaultValue: 'https://packs.tablelab.app');
```
Commit + push to `main` → `deploy-web.yml` rebuilds → the Study tab appears in
prod (init fetches the hosted index → `spots.isNotEmpty` → tab shows). No
per-scenario deploy: adding more spots later just means uploading them +
re-uploading `index.json`; the app picks them up on next launch.

Test before committing the real URL:
`flutter run -d chrome --dart-define=TLPACKS_URL=https://packs.tablelab.app`.

## Cost
Storage 51 GB → ~$0.62/mo (10 GB free + 41 GB × $0.015). Egress: **$0**. Class-A
(writes) one-time on upload; Class-B (reads) are cheap and only on real usage.
