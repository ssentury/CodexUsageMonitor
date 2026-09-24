import assert from 'node:assert/strict';
import test from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { MODEL_COLORS, modelFamily, normalizeWidgetHistoryMinutes, runningModels, widgetSnapshot } from '../src/widget.mjs';

test('widget aggregates models, excludes auto-review, expires costs and flags missing rates', () => {
  const db = new DatabaseSync(':memory:');
  try {
    db.exec('CREATE TABLE calls(event_at TEXT, usd REAL, excluded INTEGER, model TEXT)');
    const insert = db.prepare("INSERT INTO calls VALUES (?, ?, ?, 'gpt-6-astra')");
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

test('widget history supports configurable minute ranges with safe bounds', () => {
  const db = new DatabaseSync(':memory:');
  try {
    db.exec('CREATE TABLE calls(event_at TEXT, usd REAL, excluded INTEGER, model TEXT)');
    const now = Date.parse('2026-09-24T12:00:00.500Z');
    assert.equal(widgetSnapshot(db, now, 1).points.length, 60);
    assert.equal(widgetSnapshot(db, now, 15).points.length, 900);
    assert.equal(widgetSnapshot(db, now, 999).points.length, 3600);
    assert.equal(normalizeWidgetHistoryMinutes('7'), 7);
    assert.equal(normalizeWidgetHistoryMinutes(null), 5);
    assert.equal(normalizeWidgetHistoryMinutes('invalid'), 5);
  } finally { db.close(); }
});

test('model bands preserve total history, colors, unknown costs and expiration', () => {
  const db = new DatabaseSync(':memory:');
  try {
    db.exec('CREATE TABLE calls(event_at TEXT, usd REAL, excluded INTEGER, model TEXT)');
    const now = Date.parse('2026-09-24T12:00:00.500Z');
    const insert = db.prepare('INSERT INTO calls VALUES (?, ?, ?, ?)');
    for (const [model, usd] of [['gpt-6-astra', 0.3], ['gpt-6-sol', 0.6], ['gpt-5.6-terra', 0.9], ['gpt-6-luna', 1.2], ['unrecognized', 1.5]]) {
      insert.run(new Date(now - 1000).toISOString(), usd, 0, model);
    }
    insert.run(new Date(now - 1000).toISOString(), 99, 1, 'codex-auto-review');
    insert.run(new Date(now - 1000).toISOString(), null, 0, 'unknown');
    const snapshot = widgetSnapshot(db, now);
    snapshot.points.forEach((total, i) => {
      assert.ok(Math.abs(snapshot.series.reduce((sum, item) => sum + item.points[i], 0) - total) < 1e-10);
    });
    assert.deepEqual(snapshot.series.map((item) => Number(item.points.at(-1).toFixed(2))), [0.01, 0.02, 0.03, 0.04, 0.05]);
    assert.equal(snapshot.unpricedCalls, 1);
    assert.deepEqual(snapshot.series.map((item) => item.color), ['#579DFF', '#FFAA55', '#57C785', '#579DFF', '#89939F']);
    assert.ok(widgetSnapshot(db, now + 31000).series.every((item) => item.points.at(-1) < 1e-10));
    assert.equal(modelFamily('gpt-6-sol-2026-09-01'), 'sol');
    assert.equal(modelFamily('something-solar'), 'other');
  } finally { db.close(); }
});

test('running models count distinct current sessions including children and omit stopped and review turns', () => {
  const db = new DatabaseSync(':memory:');
  try {
    db.exec(`CREATE TABLE files(session_id TEXT, current_turn_id TEXT, current_model TEXT);
      CREATE TABLE turns(id TEXT, session_id TEXT, model TEXT, status TEXT);`);
    const file = db.prepare('INSERT INTO files VALUES (?, ?, ?)');
    const turn = db.prepare('INSERT INTO turns VALUES (?, ?, ?, ?)');
    for (const [session, model, status] of [
      ['parent', 'gpt-6-astra', 'running'], ['child1', 'gpt-6-luna', 'running'],
      ['child2', 'gpt-6-luna', 'running'], ['done', 'gpt-6-sol', 'completed'],
      ['aborted', 'gpt-5.6-terra', 'aborted'], ['review', 'codex-auto-review', 'running'],
    ]) {
      file.run(session, session + '-turn', model);
      turn.run(session + '-turn', session, model, status);
    }
    file.run('parent', 'parent-turn', 'gpt-6-astra'); // Duplicate source does not double count.
    turn.run('old-turn', 'parent', 'gpt-6-sol', 'running'); // Historical dangling turn.
    assert.deepEqual(runningModels(db), [
      { model: 'gpt-6-astra', count: 1, color: MODEL_COLORS.astra, label: 'GPT-6 Astra' },
      { model: 'gpt-6-luna', count: 2, color: MODEL_COLORS.luna, label: 'GPT-6 Luna' },
    ]);
    db.exec('UPDATE files SET current_turn_id = NULL');
    assert.deepEqual(runningModels(db), []);
  } finally { db.close(); }
});
