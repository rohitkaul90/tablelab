#!/usr/bin/env node
// Adds/updates the Study-tab (GTO Explorer) insights on the EXISTING
// "TableLab — Launch KPIs" dashboard. Helpers live in scripts/posthog-lib.mjs
// (shared with posthog-setup-dashboards.mjs). UPSERT semantics: re-running
// PATCHes an existing tile in place, so a bad tile is fixed by editing this
// file and re-running.
//
// Usage (PowerShell):
//   $env:POSTHOG_PERSONAL_API_KEY="phx_..."; $env:POSTHOG_PROJECT_ID="448322"; $env:POSTHOG_DASHBOARD_ID="1743504"; node scripts/posthog-add-study-funnel.mjs
// Usage (bash):
//   POSTHOG_PERSONAL_API_KEY=phx_... POSTHOG_PROJECT_ID=448322 POSTHOG_DASHBOARD_ID=1743504 node scripts/posthog-add-study-funnel.mjs
//
// POSTHOG_HOST defaults to https://us.posthog.com (API host, NOT us.i.posthog.com)

import { makeApi, ev, trends, funnel, upsertInsight } from './posthog-lib.mjs';

const HOST = process.env.POSTHOG_HOST;
const PROJECT = process.env.POSTHOG_PROJECT_ID;
const KEY = process.env.POSTHOG_PERSONAL_API_KEY;
const DASHBOARD = process.env.POSTHOG_DASHBOARD_ID;
const DRY = process.env.DRY_RUN === '1';

if (!PROJECT || !KEY || !DASHBOARD) {
  console.error('Missing POSTHOG_PROJECT_ID, POSTHOG_PERSONAL_API_KEY or POSTHOG_DASHBOARD_ID env vars.');
  process.exit(1);
}

const api = makeApi({ host: HOST, project: PROJECT, key: KEY });

// ── Study insights ────────────────────────────────────────────────────────────
// NOTE the funnel deliberately does NOT start from 'Application Opened': that
// is a MOBILE lifecycle event posthog_flutter's web target (posthog-js) never
// emits, so a 3-step funnel would show ~0% conversion for every web user —
// during exactly the web-first window after the events ship. Study adoption
// vs overall traffic is readable from the dashboard's existing DAU tile.

const insights = [
  {
    name: 'Study funnel (opened Study → explored a spot)',
    // The first provisioning run created this tile under the old name with the
    // broken 3-step query — rename-in-place so the dashboard keeps ONE tile.
    legacyName: 'Study funnel (opened app → opened Study → explored a spot)',
    description:
      'Does anyone use the GTO Explorer, and do openers actually explore? ' +
      'study_tab_opened fires on real tab switches only; explorer_spot_loaded ' +
      'on user-initiated spot loads only (app-start auto-select and the ' +
      'error-screen Retry are excluded). Events shipped 2026-07-16 — web ' +
      'counts within hours of deploy, mobile only after the next AAB.',
    query: funnel(
      [ev('study_tab_opened'), ev('explorer_spot_loaded')],
      { windowInterval: 7, windowUnit: 'day' },
    ),
  },
  {
    name: 'Study spots explored, by scenario',
    description:
      'Which solved scenarios users actually browse — the demand signal for ' +
      'expanding explorer pack coverage (density re-solve decision).',
    query: trends([ev('explorer_spot_loaded')], {
      interval: 'week',
      breakdown: { key: 'scenario', type: 'event' },
    }),
  },
];

// ── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  if (DRY) {
    insights.forEach((i) => console.log(`\n— ${i.name}\n${JSON.stringify(i.query, null, 2)}`));
    return;
  }

  const dash = await api('GET', `/dashboards/${DASHBOARD}/`);
  console.log(`✓ Target dashboard: #${DASHBOARD} "${dash.name}"`);

  for (const i of insights) {
    // Migrate a tile created under an old name: PATCH it to the new
    // name/query in place (keeps its dashboard position) before upserting.
    if (i.legacyName) {
      const legacy = await api('GET', `/insights/?search=${encodeURIComponent(i.legacyName)}`);
      const hit = (legacy.results || []).find((r) => r.name === i.legacyName);
      if (hit) {
        await api('PATCH', `/insights/${hit.id}/`, {
          name: i.name,
          description: i.description,
          query: i.query,
        });
        console.log(`✓ migrated legacy tile → ${i.name}`);
        continue;
      }
    }
    const outcome = await upsertInsight(api, i, [Number(DASHBOARD)]);
    console.log(`✓ ${outcome}: ${i.name}`);
  }
  console.log(`\nDone. Open: ${(HOST || 'https://us.posthog.com').replace(/\/$/, '')}/project/${PROJECT}/dashboard/${DASHBOARD}`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
