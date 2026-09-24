const $ = (id) => document.getElementById(id);
const form = $('price-form');
const fields = [...form.querySelectorAll('input[name]')].map((input) => input.name);
let catalog, selected, baseline = '', busy = false, pendingImport;
let listSignature = '';
const dirty = () => selected && JSON.stringify(readRate()) !== baseline;
function message(text, error = false) { $('notice').textContent = text; $('notice').className = error ? 'error' : ''; }
function readRate() { return Object.fromEntries(fields.filter((key) => form.elements[key].value !== '').map((key) => [key, Number(form.elements[key].value)])); }
function fill(rate) { for (const key of fields) form.elements[key].value = rate[key] ?? ''; updateDirty(); }
function updateDirty() { $('dirty-state').textContent = dirty() ? 'Unsaved changes' : 'No unsaved changes'; }
function mayLeave() { return !dirty() || confirm('Discard unsaved prices?'); }
function renderList() {
  $('model-count').textContent = `(${catalog.models.length})`;
  const visible = catalog.models.filter((item) => item.model.toLowerCase().includes($('search').value.toLowerCase()) && (!$('missing-only').checked || !item.priced));
  const signature = JSON.stringify([selected, busy, visible.map(({ model, priced, source }) => [model, priced, source])]);
  if (signature === listSignature) return;
  listSignature = signature;
  $('models').replaceChildren(...visible.map((item) => {
    const button = document.createElement('button');
    button.className = `model-choice ${item.model === selected ? 'selected' : ''} ${item.priced ? '' : 'missing'}`;
    button.setAttribute('aria-pressed', String(item.model === selected));
    const title = document.createElement('strong'); title.textContent = item.model;
    const detail = document.createElement('small'); detail.textContent = !item.priced ? '● Needs prices' : item.source === 'custom' ? 'Custom prices' : 'Bundled prices';
    button.append(title, detail); button.disabled = busy;
    button.onclick = () => { if (item.model !== selected && mayLeave()) select(item.model); };
    return button;
  }));
  if (!visible.length) $('models').textContent = 'No matching models.';
}
function select(model) {
  const item = catalog.models.find((row) => row.model === model) || catalog.models[0];
  selected = item?.model;
  form.hidden = !item; $('empty-editor').hidden = !!item;
  if (!item) { baseline = ''; return; }
  $('model-name').textContent = item.model;
  $('model-meta').textContent = item.calls ? `${item.calls.toLocaleString()} recorded calls · model name filled automatically` : 'Included in your catalog · no recorded calls yet';
  $('price-status').textContent = item.priced ? 'Ready' : 'Needs prices';
  $('price-status').className = `badge ${item.priced ? '' : 'missing'}`;
  fill(item.rate); baseline = JSON.stringify(readRate()); updateDirty();
  $('reset').textContent = item.hasDefault ? 'Use bundled prices' : 'Clear prices';
  $('reset').disabled = item.source !== 'custom';
  $('copy-model').replaceChildren(new Option('Choose a model…', ''), ...catalog.models.filter((row) => row.model !== selected && row.priced).map((row) => new Option(row.model, row.model)));
  renderList();
}
async function load() {
  const response = await fetch('/api/catalog', { cache: 'no-store' });
  if (!response.ok) throw new Error('Could not load model prices.');
  catalog = await response.json(); renderList();
  if (!selected) select(catalog.models[0]?.model);
}
async function save(models, success) {
  if (busy) return;
  busy = true;
  const controls = [...document.querySelectorAll('button, input, select')];
  const disabled = controls.map((control) => control.disabled);
  controls.forEach((control) => { control.disabled = true; });
  let saved = false;
  try {
    const response = await fetch('/api/catalog', { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ models }) });
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || 'Could not save prices.');
    catalog = payload; saved = true; message(success);
  } catch (error) { message(error.message, true); }
  finally {
    busy = false; controls.forEach((control, index) => { control.disabled = disabled[index]; });
    if (saved) select(selected || catalog.models[0]?.model); else renderList();
  }
  return saved;
}
form.addEventListener('input', updateDirty);
form.onsubmit = async (event) => { event.preventDefault(); if (form.reportValidity()) await save({ [selected]: readRate() }, 'Prices saved. Existing usage has been recalculated.'); };
$('search').oninput = renderList; $('missing-only').onchange = renderList;
$('copy').onclick = () => { const source = catalog.models.find((row) => row.model === $('copy-model').value); if (source) { fill(source.rate); message(`Copied from ${source.model}. Save to apply.`); } };
$('reset').onclick = async () => { if (confirm('Reset this model’s prices? Existing usage will be recalculated.')) await save({ [selected]: null }, 'Model prices reset.'); };
$('export').onclick = () => {
  const models = Object.fromEntries(catalog.models.map((row) => [row.model, Object.fromEntries(fields.filter((key) => row.rate[key] != null).map((key) => [key, row.rate[key]]))]));
  const url = URL.createObjectURL(new Blob([JSON.stringify({ version: 1, models }, null, 2)], { type: 'application/json' }));
  const link = document.createElement('a'); link.href = url; link.download = 'model-prices.json'; link.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
};
$('import').onclick = () => { if (mayLeave()) $('import-file').click(); };
$('import-file').onchange = async (event) => {
  const file = event.target.files[0]; event.target.value = ''; if (!file) return;
  try {
    if (file.size > 256000) throw new Error('Catalog is too large.');
    const value = JSON.parse(await file.text());
    if (value.version !== 1 || !value.models || typeof value.models !== 'object' || Array.isArray(value.models)) throw new Error('Choose an exported model-prices.json catalog (version 1).');
    pendingImport = value.models;
    $('import-description').textContent = `${Object.keys(pendingImport).length} model entries will replace matching custom prices. Other models stay as they are. Existing usage will be recalculated.`;
    $('import-preview').hidden = false;
  } catch (error) { message(error.message, true); }
};
$('cancel-import').onclick = () => { pendingImport = null; $('import-preview').hidden = true; };
$('apply-import').onclick = async () => { if (pendingImport && mayLeave() && await save(pendingImport, 'Catalog imported. Existing usage has been recalculated.')) { pendingImport = null; $('import-preview').hidden = true; } };
window.addEventListener('beforeunload', (event) => { if (dirty()) { event.preventDefault(); event.returnValue = ''; } });
const events = new EventSource('/api/events');
let refreshTimer;
events.addEventListener('update', () => { clearTimeout(refreshTimer); refreshTimer = setTimeout(() => { if (!busy) load().catch(() => {}); }, 500); });
load().catch((error) => message(error.message, true));
