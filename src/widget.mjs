// Each point represents the trailing 30 seconds of recorded API-equivalent cost.
// Use event time, not ingestion time, so rescans cannot create artificial spikes.
export const MIN_WIDGET_HISTORY_MINUTES = 1;
export const MAX_WIDGET_HISTORY_MINUTES = 60;

export function normalizeWidgetHistoryMinutes(value, fallback = 5) {
  if (value == null || value === '') return fallback;
  const minutes = Number(value);
  if (!Number.isInteger(minutes)) return fallback;
  return Math.min(MAX_WIDGET_HISTORY_MINUTES, Math.max(MIN_WIDGET_HISTORY_MINUTES, minutes));
}

export function widgetSnapshot(database, now = Date.now(), historyMinutes = 5) {
  const pointCount = normalizeWidgetHistoryMinutes(historyMinutes) * 60;
  const end = Math.floor(now / 1000);
  const first = end - (pointCount - 1);
  const start = first - 29;
  const rows = database.prepare(
    `SELECT event_at, usd FROM calls
     WHERE excluded = 0 AND event_at >= ? AND event_at <= ?`,
  ).all(new Date(start * 1000).toISOString(), new Date(now).toISOString());
  const buckets = new Map();
  const missing = new Map();
  for (const row of rows) {
    const second = Math.floor(Date.parse(row.event_at) / 1000);
    if (row.usd == null) missing.set(second, (missing.get(second) || 0) + 1);
    else buckets.set(second, (buckets.get(second) || 0) + row.usd);
  }
  let sum = 0;
  let unpriced = 0;
  const points = [];
  for (let second = start; second <= end; second++) {
    sum += (buckets.get(second) || 0) - (buckets.get(second - 30) || 0);
    unpriced += (missing.get(second) || 0) - (missing.get(second - 30) || 0);
    if (second >= first) points.push(Math.max(0, sum) / 30);
  }
  return {
    at: new Date(now).toISOString(), windowSeconds: 30,
    usdPerSecond: points.at(-1), points, unpricedCalls: unpriced,
  };
}
