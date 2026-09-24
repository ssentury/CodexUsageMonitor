import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { PriceCatalog, validateModels } from '../src/catalog.mjs';
import { priceUsage } from '../src/pricing.mjs';
import { UsageDatabase } from '../src/database.mjs';

const defaults = { models: { known: { inputPerMillion: 2, cachedInputPerMillion: .2, outputPerMillion: 10,
  creditsInputPerMillion: 50, creditsCachedInputPerMillion: 5, creditsOutputPerMillion: 250 } } };
const usage = { inputTokens: 1000000, cachedInputTokens: 0, outputTokens: 0 };
function setup(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'monitor-catalog-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  const file = path.join(root, 'prices.json');
  return { root, file, catalog: new PriceCatalog(defaults, file) };
}

test('discovered models sort first; blank prices stay unknown and explicit zeros are free', (t) => {
  const { catalog } = setup(t);
  assert.equal(catalog.snapshot([{ model: 'new', calls: 2 }]).models[0].model, 'new');
  catalog.update({ new: { inputPerMillion: 0 } }, () => {});
  assert.deepEqual(priceUsage('new', usage, catalog.rateCard()), { usd: null, credits: null });
  catalog.update({ new: { inputPerMillion: 0, cachedInputPerMillion: 0, outputPerMillion: 0 } }, () => {});
  assert.deepEqual(priceUsage('new', usage, catalog.rateCard()), { usd: 0, credits: 0 });
});

test('custom rates persist, reset reveals defaults, and failure retains the previous catalog', (t) => {
  const { catalog, file } = setup(t);
  catalog.update({ known: { inputPerMillion: 3, cachedInputPerMillion: 1, outputPerMillion: 4 } }, () => {});
  assert.equal(new PriceCatalog(defaults, file).rateCard().models.known.inputPerMillion, 3);
  const saved = fs.readFileSync(file, 'utf8');
  assert.throws(() => catalog.update({ known: {} }, () => { throw new Error('database failed'); }));
  assert.equal(fs.readFileSync(file, 'utf8'), saved);
  assert.equal(catalog.rateCard().models.known.inputPerMillion, 3);
  catalog.update({ known: null }, () => {});
  assert.equal(catalog.rateCard().models.known.inputPerMillion, 2);
});

test('invalid imports cannot partially overwrite a saved catalog', (t) => {
  const { catalog } = setup(t);
  for (const value of [-1, '2', Infinity, NaN]) assert.throws(() => validateModels({ bad: { inputPerMillion: value } }));
  assert.throws(() => validateModels(JSON.parse('{"__proto__":{}}')));
  assert.throws(() => validateModels({ bad: { longContextThresholdTokens: 1.5 } }));
  assert.throws(() => catalog.update({ known: {}, bad: { outputPerMillion: -1 } }, () => {}));
  assert.equal(catalog.rateCard().models.known.inputPerMillion, 2);
});

test('live repricing updates existing calls, preserves auto-review exclusion and survives reopening', (t) => {
  const { catalog, root } = setup(t);
  const dbPath = path.join(root, 'usage.sqlite3');
  const db = new UsageDatabase(dbPath, catalog.rateCard());
  try {
    // Foreign keys are irrelevant to this isolated pricing fixture.
    db.database.exec('PRAGMA foreign_keys = OFF');
    const insert = db.database.prepare(`INSERT INTO calls(event_id, session_id, turn_id, root_turn_id, event_at, model,
      input_tokens,cached_input_tokens,cache_write_tokens,output_tokens,reasoning_tokens,total_tokens,excluded)
      VALUES (?, 'session', 'turn', 'turn', ?, ?, 1000000,0,0,0,0,1000000,?)`);
    insert.run('normal', new Date().toISOString(), 'new', 0);
    insert.run('review', new Date().toISOString(), 'review-only', 1);
    assert.deepEqual(db.detectedModels().map((row) => row.model), ['new']);
    catalog.update({ new: { inputPerMillion: 3, cachedInputPerMillion: 0, outputPerMillion: 0 } }, (rates) => db.updateRateCard(rates));
    assert.equal(db.summary('today').usd, 3);
    assert.equal(db.summary('today').credits, 75);
    assert.equal(db.database.prepare("SELECT usd FROM calls WHERE event_id='review'").get().usd, null);
    catalog.update({ new: {} }, (rates) => db.updateRateCard(rates));
    assert.equal(db.summary('today').unpricedCalls, 1);
  } finally { db.close(); }
  const reopened = new UsageDatabase(dbPath, catalog.rateCard());
  try { assert.equal(reopened.summary('today').unpricedCalls, 1); } finally { reopened.close(); }
});
