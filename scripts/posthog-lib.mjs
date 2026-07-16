// Shared PostHog REST helpers + InsightVizNode query builders — the ONE copy
// used by scripts/posthog-setup-dashboards.mjs and
// scripts/posthog-add-study-funnel.mjs. No secrets: callers pass env values in.
// Requires Node 18+ (global fetch).

/// Build an authenticated project-scoped API caller.
export function makeApi({ host, project, key }) {
  const base = `${(host || 'https://us.posthog.com').replace(/\/$/, '')}/api/projects/${project}`;
  const headers = { Authorization: `Bearer ${key}`, 'Content-Type': 'application/json' };
  return async function api(method, path, body) {
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
  };
}

// ── Query builders (PostHog node/InsightVizNode format) ──────────────────────

export const ev = (event, { math, properties, name } = {}) => ({
  kind: 'EventsNode',
  event,
  name: name || event,
  ...(math ? { math } : {}),
  ...(properties ? { properties } : {}),
});

export const prop = (key, value, type = 'event') => ({ key, value, operator: 'exact', type });

export const trends = (series, { interval = 'week', breakdown, dateFrom = '-30d' } = {}) => ({
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

export const funnel = (series, { windowInterval = 14, windowUnit = 'day', breakdown, dateFrom = '-30d' } = {}) => ({
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

export const retention = (event, { period = 'Week' } = {}) => ({
  kind: 'InsightVizNode',
  source: {
    kind: 'RetentionQuery',
    retentionFilter: {
      targetEntity: { id: event, name: event, type: 'events' },
      returningEntity: { id: event, name: event, type: 'events' },
      period,
      retentionType: 'retention_first_time',
    },
  },
});

/// Create the insight, or PATCH it in place when one with the same name
/// already exists (so re-running a script FIXES a bad tile instead of
/// skipping it). Returns 'created' | 'updated'.
export async function upsertInsight(api, insight, dashboardIds) {
  const existing = await api('GET', `/insights/?search=${encodeURIComponent(insight.name)}`);
  const hit = (existing.results || []).find((r) => r.name === insight.name);
  const payload = {
    name: insight.name,
    description: insight.description,
    query: insight.query,
    saved: true,
  };
  if (hit) {
    await api('PATCH', `/insights/${hit.id}/`, {
      ...payload,
      dashboards: [...new Set([...(hit.dashboards || []), ...dashboardIds])],
    });
    return 'updated';
  }
  await api('POST', '/insights/', { ...payload, dashboards: dashboardIds });
  return 'created';
}
