// Each point represents the trailing 30 seconds of recorded API-equivalent cost.
// Use event time, not ingestion time, so rescans cannot create artificial spikes.
export const MIN_WIDGET_HISTORY_MINUTES = 1;
export const MAX_WIDGET_HISTORY_MINUTES = 60;
export const MODEL_COLORS = {
  astra: '#579DFF', sol: '#FFAA55', terra: '#57C785', luna: '#B68CFF', other: '#89939F',
};

export function modelFamily(model) {
  return String(model || '').toLowerCase().match(/(?:^|[-_ ])(astra|sol|terra|luna)(?:$|[-_ ])/)?.[1] || 'other';
}

export function runningModels(database) {
  // The parser's current turn is cleared on completion/abort. Count sessions,
  // not historical running turns or token events; include child sessions.
  return database.prepare(`
    SELECT COALESCE(t.model, f.current_model, 'unknown') AS model,
           COUNT(DISTINCT f.session_id) AS count
    FROM files f JOIN turns t ON t.id = f.current_turn_id AND t.session_id = f.session_id
    WHERE t.status = 'running'
      AND COALESCE(t.model, f.current_model, 'unknown') <> 'codex-auto-review'
    GROUP BY COALESCE(t.model, f.current_model, 'unknown') ORDER BY model
  `).all().map(({ model, count }) => ({
    model, count, color: MODEL_COLORS[modelFamily(model)],
    label: model.replace(/^gpt[-_]/i, 'GPT-').replace(/[-_](astra|sol|terra|luna)\b/gi,
      (_, family) => ` ${family[0].toUpperCase()}${family.slice(1).toLowerCase()}`),
  }));
}

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
    `SELECT event_at, usd, model FROM calls
     WHERE excluded = 0 AND event_at >= ? AND event_at <= ?`,
  ).all(new Date(start * 1000).toISOString(), new Date(now).toISOString());
  const buckets = new Map();
  const missing = new Map();
  const series = Object.entries(MODEL_COLORS).map(([family, color]) => ({ family, color, points: [] }));
  const modelBuckets = new Map(series.map(({ family }) => [family, new Map()]));
  for (const row of rows) {
    const second = Math.floor(Date.parse(row.event_at) / 1000);
    if (row.usd == null) missing.set(second, (missing.get(second) || 0) + 1);
    else buckets.set(second, (buckets.get(second) || 0) + row.usd);
    if (row.usd != null) {
      const bucket = modelBuckets.get(modelFamily(row.model));
      bucket.set(second, (bucket.get(second) || 0) + row.usd);
    }
  }
  let sum = 0;
  let unpriced = 0;
  const points = [];
  const sums = new Map(series.map(({ family }) => [family, 0]));
  for (let second = start; second <= end; second++) {
    sum += (buckets.get(second) || 0) - (buckets.get(second - 30) || 0);
    unpriced += (missing.get(second) || 0) - (missing.get(second - 30) || 0);
    if (second >= first) points.push(Math.max(0, sum) / 30);
    for (const item of series) {
      const bucket = modelBuckets.get(item.family);
      const value = sums.get(item.family) + (bucket.get(second) || 0) - (bucket.get(second - 30) || 0);
      sums.set(item.family, value);
      if (second >= first) item.points.push(Math.max(0, value) / 30);
    }
  }
  return {
    at: new Date(now).toISOString(), windowSeconds: 30,
    usdPerSecond: points.at(-1), points, series, unpricedCalls: unpriced,
  };
}
