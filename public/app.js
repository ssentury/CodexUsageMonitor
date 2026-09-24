const turnList = document.querySelector('#turn-list');
const summary = document.querySelector('#summary');
const days = document.querySelector('#days');
const listPeriod = document.querySelector('#list-period');
const updatedAt = document.querySelector('#updated-at');
const connection = document.querySelector('#connection');
const liveDot = document.querySelector('#live-dot');
const rescan = document.querySelector('#rescan');
let refreshTimer;

days.addEventListener('change', refresh);
rescan.addEventListener('click', async () => {
  rescan.disabled = true;
  await fetch('/api/rescan', { method: 'POST' });
  setTimeout(() => {
    rescan.disabled = false;
    refresh();
  }, 500);
});

const events = new EventSource('/api/events');
events.addEventListener('ready', markConnected);
events.addEventListener('update', () => {
  markConnected();
  scheduleRefresh(100);
});
events.onerror = () => {
  connection.textContent = '재연결 중';
  liveDot.classList.remove('connected');
};

setInterval(refresh, 10_000);
refresh();

async function refresh() {
  try {
    listPeriod.textContent = days.selectedOptions[0]?.textContent || '오늘';
    const query = `days=${encodeURIComponent(days.value)}`;
    const [turnResponse, summaryResponse] = await Promise.all([
      fetch(`/api/turns?${query}&limit=150`, { cache: 'no-store' }),
      fetch(`/api/summary?${query}`, { cache: 'no-store' }),
    ]);
    if (!turnResponse.ok || !summaryResponse.ok) throw new Error('백엔드 응답 실패');
    const turnPayload = await turnResponse.json();
    renderSummary(await summaryResponse.json());
    renderTurns(turnPayload.turns);
    updatedAt.textContent = `갱신 ${new Date().toLocaleTimeString()}`;
    markConnected();
  } catch (error) {
    turnList.replaceChildren(element('div', 'empty error', error.message));
  }
}

function scheduleRefresh(delay) {
  clearTimeout(refreshTimer);
  refreshTimer = setTimeout(refresh, delay);
}

function markConnected() {
  connection.textContent = '실시간 연결';
  liveDot.classList.add('connected');
}

function renderSummary(data) {
  const values = [
    ['호출', formatNumber(data.calls)],
    ['입력 토큰', formatTokens(data.inputTokens)],
    ['캐시 입력', formatTokens(data.cachedInputTokens)],
    ['API 환산', `$${formatMoney(data.usd)}`],
    ['Codex 크레딧', formatMoney(data.credits)],
  ];
  summary.replaceChildren(
    ...values.map(([label, value]) => {
      const item = element('div', 'metric');
      item.append(element('span', 'metric-label', label), element('strong', 'metric-value', value));
      return item;
    }),
  );
}

function renderTurns(turns) {
  if (!turns.length) {
    turnList.replaceChildren(element('div', 'empty', '아직 수집된 프롬프트가 없습니다.'));
    return;
  }
  turnList.replaceChildren(...turns.map(renderTurn));
}

function renderTurn(turn) {
  const card = element('article', `turn-card ${turn.status === 'running' ? 'running' : ''}`);
  const head = element('div', 'turn-head');
  const left = element('div');
  const title = element('div', 'turn-title');
  if (turn.status === 'running') title.append(element('span', 'status', '● 실행 중'));
  title.append(document.createTextNode(turn.title || '(제목 없는 프롬프트)'));
  left.append(title, element('div', 'turn-meta', `${formatTime(turn.started_at)} · ${shortPath(turn.cwd)}`));
  const total = element('div', 'turn-total');
  total.append(
    element('div', '', `${formatTokens(turn.totals.totalTokens)} tokens · ${turn.totals.calls} calls`),
    element('div', '', `$${formatMoney(turn.totals.usd)} · ${formatMoney(turn.totals.credits)} credits`),
  );
  head.append(left, total);
  card.append(head);

  const rows = element('div', 'rows');
  for (const model of turn.models) {
    const row = element('div', 'usage-row');
    const label = element('div', 'model', model.model);
    if (model.effort) label.append(element('span', 'effort', ` · ${model.effort}`));
    row.append(
      label,
      element('div', 'tokens', `${formatTokens(model.inputTokens)} / ${formatTokens(model.cachedInputTokens)} / ${formatTokens(model.outputTokens)} / ${formatTokens(model.totalTokens)}`),
      element('div', 'money', model.usd == null ? '미환산' : `$${formatMoney(model.usd)}`),
      element('div', 'money', model.credits == null ? '미환산' : formatMoney(model.credits)),
    );
    rows.append(row);
  }
  card.append(rows);

  for (const child of turn.children) {
    const childRow = element('div', 'child');
    const name = child.agentNickname || child.agentRole || 'subagent';
    childRow.append(
      element('div', 'child-line', ''),
    );
    childRow.firstChild.append(
      element('span', 'child-name', `↳ ${name} · ${child.model || 'unknown'}${child.effort ? ` · ${child.effort}` : ''}`),
      element('span', 'tokens', `${formatTokens(child.totalTokens)} · $${formatMoney(child.usd)}`),
    );
    card.append(childRow);
  }
  return card;
}

function element(tag, className = '', text = '') {
  const value = document.createElement(tag);
  if (className) value.className = className;
  if (text !== '') value.textContent = text;
  return value;
}

function formatTokens(value = 0) {
  const number = Number(value) || 0;
  if (number >= 1_000_000_000) return `${(number / 1_000_000_000).toFixed(2)}B`;
  if (number >= 1_000_000) return `${(number / 1_000_000).toFixed(2)}M`;
  if (number >= 1_000) return `${(number / 1_000).toFixed(1)}K`;
  return formatNumber(number);
}

function formatNumber(value = 0) {
  return new Intl.NumberFormat('ko-KR').format(Number(value) || 0);
}

function formatMoney(value = 0) {
  return (Number(value) || 0).toFixed(3);
}

function formatTime(value) {
  return value ? new Date(value).toLocaleString() : '-';
}

function shortPath(value) {
  if (!value) return '-';
  const parts = value.split(/[\\/]/).filter(Boolean);
  return parts.slice(-2).join(' / ');
}
