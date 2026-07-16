#!/usr/bin/env node
// Creates the "TableLab — Launch KPIs" dashboard + its insights in PostHog via
// the REST API. Idempotency: bails if a dashboard of the same name already
// exists (so re-running won't duplicate). No secrets in this file — it reads
// the personal API key from the environment.
//
// Usage (PowerShell):
//   $env:POSTHOG_PERSONAL_API_KEY="phx_..."; $env:POSTHOG_PROJECT_ID="12345"; node scripts/posthog-setup-dashboards.mjs
// Usage (bash):
//   POSTHOG_PERSONAL_API_KEY=phx_... POSTHOG_PROJECT_ID=12345 node scripts/posthog-setup-dashboards.mjs
//
// Optional env:
//   POSTHOG_HOST     defaults to https://us.posthog.com  (API host, NOT us.i.posthog.com)
//   DRY_RUN=1        print the payloads, create nothing
//
// Requires Node 18+ (global fetch).

const HOST = (process.env.POSTHOG_HOST || 'https://us.posthog.com').replace(/\/$/, '');
const PROJECT = process.env.POSTHOG_PROJECT_ID;
const KEY = process.env.POSTHOG_PERSONAL_API_KEY;
const DRY = process.env.DRY_RUN === '1';
const DASHBOARD_NAME = 'TableLab — Launch KPIs';

if (!PROJECT || !KEY) {
  console.error('Missing POSTHOG_PROJECT_ID or POSTHOG_PERSONAL_API_KEY env vars.');
  process.exit(1);
}

import { makeApi, ev, prop, trends, funnel, retention } from './posthog-lib.mjs';

const api = makeApi({ host: HOST, project: PROJECT, key: KEY });

// ── Insight definitions (the 10-insight spec) ────────────────────────────────

const insights = [
  {
    name: 'Activation funnel (install → session → hand → AI)',
    description: 'Do new users reach value? Broken down by signup method.',
    query: funnel(
      [
        ev('Application Opened'),
        ev('session_logged'),
        ev('hand_recorded'),
        ev('ai_hand_analysis_requested'),
      ],
      { windowInterval: 7, windowUnit: 'day', breakdown: { key: 'signup_method', type: 'person' } },
    ),
  },
  {
    name: 'Live session completion (started → finalized)',
    description: 'Gap = abandoned live sessions. Cross-check live_session_abandoned.',
    query: funnel(
      [
        ev('live_session_started'),
        ev('session_logged', { properties: [prop('source', 'live')] }),
      ],
      { windowInterval: 1, windowUnit: 'day' },
    ),
  },
  {
    name: 'AI hand analysis funnel (requested → completed)',
    description: 'Request → result. Failures/limits shown in the AI outcomes insight.',
    query: funnel(
      [
        ev('ai_hand_analysis_requested'),
        ev('ai_analysis_completed', { properties: [prop('feature_type', 'hand')] }),
      ],
      { windowInterval: 1, windowUnit: 'hour' },
    ),
  },
  {
    name: 'AI outcomes (requested / completed / failed / rate-limited)',
    description: 'All AI call outcomes side by side.',
    query: trends([
      ev('ai_hand_analysis_requested'),
      ev('ai_session_analysis_requested'),
      ev('ai_analysis_completed'),
      ev('ai_analysis_failed'),
      ev('ai_rate_limit_hit'),
    ]),
  },
  {
    name: 'AI failure reasons',
    description: 'timeout vs at_capacity vs network vs server_error.',
    query: trends([ev('ai_analysis_failed')], { breakdown: { key: 'reason' } }),
  },
  {
    name: 'Import / migration funnel (started → completed)',
    description: 'Migration funnel, broken down by source app.',
    query: funnel(
      [ev('import_started'), ev('import_completed')],
      { windowInterval: 1, windowUnit: 'hour', breakdown: { key: 'source' } },
    ),
  },
  {
    name: 'Hand recording — Quick vs Full',
    description: 'entry_mode split.',
    query: trends([ev('hand_recorded')], { breakdown: { key: 'entry_mode' } }),
  },
  {
    name: 'AI coaching satisfaction (thumbs up/down)',
    description: 'ai_analysis_rated by rating (1 vs -1).',
    query: trends([ev('ai_analysis_rated')], { breakdown: { key: 'rating' } }),
  },
  {
    name: 'Retention (weekly, Application Opened)',
    description: 'First-time → returning weekly retention.',
    query: retention('Application Opened', { period: 'Week' }),
  },
  {
    name: 'Feature adoption (calculators / reads / replayer / export)',
    description: 'Secondary feature usage at a glance.',
    query: trends([
      ev('equity_calculator_used'),
      ev('icm_calculator_used'),
      ev('read_created'),
      ev('hand_replayer_opened'),
      ev('tournament_calendar_viewed'),
      ev('export_triggered'),
    ]),
  },
  {
    name: 'Feedback conversion (opened → submitted)',
    description: 'Is the feedback sheet too heavy?',
    query: funnel([ev('feedback_opened'), ev('feedback_submitted')], { windowInterval: 1, windowUnit: 'hour' }),
  },
];

// ── Run ──────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`PostHog: ${HOST}  project ${PROJECT}${DRY ? '  [DRY RUN]' : ''}`);

  // Preflight: validate auth + project.
  const proj = await api('GET', '/');
  console.log(`✓ Authenticated to project: ${proj.name || PROJECT}`);

  // Idempotency guard: bail if the dashboard already exists.
  const existing = await api('GET', `/dashboards/?search=${encodeURIComponent(DASHBOARD_NAME)}`);
  if ((existing.results || []).some((d) => d.name === DASHBOARD_NAME)) {
    console.error(`✗ A dashboard named "${DASHBOARD_NAME}" already exists. Delete it first or rename, then re-run.`);
    process.exit(2);
  }

  if (DRY) {
    insights.forEach((i) => console.log(`\n— ${i.name}\n${JSON.stringify(i.query, null, 2)}`));
    console.log('\n[DRY RUN] Nothing created.');
    return;
  }

  const dash = await api('POST', '/dashboards/', {
    name: DASHBOARD_NAME,
    description: 'Launch KPIs — funnels, retention, AI, feature adoption. Auto-generated.',
  });
  console.log(`✓ Created dashboard #${dash.id}`);

  let ok = 0;
  for (const i of insights) {
    try {
      const made = await api('POST', '/insights/', {
        name: i.name,
        description: i.description,
        query: i.query,
        dashboards: [dash.id],
      });
      console.log(`  ✓ ${i.name}  (#${made.id})`);
      ok++;
    } catch (e) {
      console.error(`  ✗ ${i.name}\n${e.message}`);
    }
  }

  console.log(`\nDone: ${ok}/${insights.length} insights created.`);
  console.log(`Open: ${HOST}/project/${PROJECT}/dashboard/${dash.id}`);
}

main().catch((e) => {
  console.error('\nFATAL:', e.message);
  process.exit(1);
});
