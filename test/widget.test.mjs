import assert from 'node:assert/strict';
import test from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { widgetSnapshot } from '../src/widget.mjs';

test('widget aggregates models, excludes auto-review, expires costs and flags missing rates', () => {
  const db = new DatabaseSync(':memory:');
  try {
    db.exec('CREATE TABLE calls(event_at TEXT, usd REAL, excluded INTEGER)');
    const insert = db.prepare('INSERT INTO calls VALUES (?, ?, ?)');
    const now = Date.parse('2026-09-24T12:00:00.500Z');
    const add = (seconds, usd, excluded = 0) => insert.run(new Date(now + seconds * 1000).toISOString(), usd, excluded);
    add(-1, 0.3); add(-2, 0.6); add(-2, 99, 1); add(-31, 30);
    add(-1, null); add(1, 100);
    const live = widgetSnapshot(db, now);
    assert.equal(live.points.length, 300);
    assert.ok(Math.abs(live.usdPerSecond - 0.03) < 1e-10);
    assert.equal(live.unpricedCalls, 1);
    assert.equal(widgetSnapshot(db, now + 400000).usdPerSecond, 0);
    assert.equal(widgetSnapshot(db, now + 400000).unpricedCalls, 0);
    assert.deepEqual(widgetSnapshot(db, now), live);
  } finally { db.close(); }
});
