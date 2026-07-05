// GTO Explorer — hosted packs config (public; committed).
//
// The public base URL of the hosted explorer packs (Cloudflare R2, served via
// packs.tablelab.app). When empty, the explorer falls back to the local
// ~/tlpacks scan in dev and shows NO Study tab in prod. Set this to the R2
// public URL once packs are uploaded (see tool/explorer/PACK_HOSTING.md), or
// override at build time with --dart-define=TLPACKS_URL=…
const String kPacksBaseUrl =
    String.fromEnvironment('TLPACKS_URL', defaultValue: 'https://packs.tablelab.app');
