#!/usr/bin/env node
// Adds the Study-tab (GTO Explorer) insights to the EXISTING "TableLab — Launch
// KPIs" dashboard via the PostHog REST API. Companion to
// posthog-setup-dashboards.mjs (same helpers/format). Idempotent: skips any
// insight whose name already exists in the project.
//
// Usage (PowerShell):
//   $env:POSTHOG_PERSONAL_API_KEY="phx_..."; $env:POSTHOG_PROJECT_ID="448322"; $env:POSTHOG_DASHBOARD_ID="1743504"; node scripts/posthog-add-study-funnel.mjs
// Usage (bash):
//   POSTHOG_PERSONAL_API_KEY=phx_... POSTHOG_PROJECT_ID=448322 POSTHOG_DASHBOARD_ID=1743504 node scripts/posthog-add-study-funnel.mjs
//
// POSTHOG_HOST defaults to https://us.posthog.com (API host, NOT us.i.posthog.com)

const HOST = (process.env.POSTHOG_HOST || 'https://us.posthog.com').replace(/\/$/, '');
const PROJECT = process.env.POSTHOG_PROJECT_ID;
const KEY = process.env.POSTHOG_PERSONAL_API_KEY;
const DASHBOARD = process.env.POSTHOG_DASHBOARD_ID;
const DRY = process.env.DRY_RUN === '1';

if (!PROJECT || !KEY || !DASHBOARD) {
  console.error('Missing POSTHOG_PROJECT_ID, POSTHOG_PERSONAL_API_KEY or POSTHOG_DASHBOARD_ID env vars.');
  process.exit(1);
}

const base = `${HOST}/api/projects/${PROJECT}`;
const headers = { Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' };

async function api(method, path, body) {
  const res = await fetch(`${base}${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try { json = text ? JSON.parse(text) : {}; } catch { json = { raw: text }; }
  if (!res.ok) {
    throw new Error(`${method} ${path} → ${res.status}\n${JSON.stringify(json, null, 2)}`);
  }
  return json;
}

// ── Query builders (mirrors posthog-setup-dashboards.mjs) ────────────────────

const ev = (event, { math, properties, name } = {}) => ({
  kind: 'EventsNode',
  event,
  name: name || event,
  ...(math ? { math } : {}),
  ...(properties ? { properties } : {}),
});

const trends = (series, { interval = 'week', breakdown, dateFrom = '-30d' } = {}) => ({
  kind: 'InsightVizNode',
  source: {
    kind: 'TrendsQuery',
    series,
    interval,
    dateRange: { date_from: dateFrom },
    trendsFilter: {},
    ...(breakdown
      ? { breakdownFilter: { breakdown: breakdown.key, breakdown_type: breakdown.type || 'event' } }
      : {}),
  },
});

const funnel = (series, { windowInterval = 14, windowUnit = 'day', breakdown, dateFrom = '-30d' } = {}) => ({
  kind: 'InsightVizNode',
  source: {
    kind: 'FunnelsQuery',
    series,
    dateRange: { date_from: dateFrom },
    funnelsFilter: { funnelWindowInterval: windowInterval, funnelWindowIntervalUnit: windowUnit },
    ...(breakdown
      ? { breakdownFilter: { breakdown: breakdown.key, breakdown_type: breakdown.type || 'event' } }
      : {}),
  },
});

// ── Study insights ────────────────────────────────────────────────────────────

const insights = [
  {
    name: 'Study funnel (opened app → opened Study → explored a spot)',
    description:
      'Does anyone use the GTO Explorer? study_tab_opened fires on real tab ' +
      'switches only; explorer_spot_loaded on user-initiated spot loads only ' +
      '(the app-start auto-select is excluded). Events shipped 2026-07-16 — ' +
      'web counts within hours of deploy, mobile only after the next AAB.',
    query: funnel(
      [
        ev('Application Opened'),
        ev('study_tab_opened'),
        ev('explorer_spot_loaded'),
      ],
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

  // Confirm the dashboard exists before creating anything.
  const dash = await api('GET', `/dashboards/${DASHBOARD}/`);
  console.log(`✓ Target dashboard: #${DASHBOARD} "${dash.name}"`);

  let ok = 0;
  for (const i of insights) {
    // Idempotency: skip if an insight with this name already exists.
    const existing = await api('GET', `/insights/?search=${encodeURIComponent(i.name)}`);
    if ((existing.results || []).some((r) => r.name === i.name)) {
      console.log(`↷ Skipped (already exists): ${i.name}`);
      continue;
    }
    try {
      await api('POST', '/insights/', {
        name: i.name,
        description: i.description,
        query: i.query,
        dashboards: [Number(DASHBOARD)],
        saved: true,
      });
      console.log(`✓ Created: ${i.name}`);
      ok++;
    } catch (e) {
      console.error(`✗ Failed: ${i.name}\n${e.message}`);
    }
  }
  console.log(`\nDone: ${ok}/${insights.length} insights created on dashboard #${DASHBOARD}.`);
  console.log(`Open: ${HOST}/project/${PROJECT}/dashboard/${DASHBOARD}`);
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
