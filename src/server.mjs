import fs from 'node:fs';
import fsp from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import { spawn } from 'node:child_process';

import {
  APP_NAME,
  APP_VERSION,
  PUBLIC_DIRECTORY,
  RATE_CARD_PATH,
  ROOT_DIRECTORY,
  resolveConfiguration,
} from './config.mjs';
import { UsageDatabase } from './database.mjs';
import { loadRateCard } from './pricing.mjs';
import { PriceCatalog } from './catalog.mjs';
import { SessionScanner } from './scanner.mjs';
import { normalizeWidgetHistoryMinutes, runningModels, widgetSnapshot } from './widget.mjs';

const configuration = resolveConfiguration();
await fsp.mkdir(configuration.stateRoot, { recursive: true });
const catalog = new PriceCatalog(loadRateCard(RATE_CARD_PATH), path.join(configuration.stateRoot, 'price-overrides.json'));
const rateCard = catalog.rateCard();
const database = new UsageDatabase(configuration.databasePath, rateCard);
const eventClients = new Set();
let revision = 0;

const notifyClients = () => {
  revision += 1;
  const message = `event: update\ndata: ${JSON.stringify({ revision, at: new Date().toISOString() })}\n\n`;
  for (const response of eventClients) response.write(message);
};

const scanner = new SessionScanner({
  sessionsRoot: configuration.sessionsRoot,
  lookbackDays: configuration.lookbackDays,
  database,
  onChange: notifyClients,
});

const server = http.createServer(async (request, response) => {
  try {
    const requestUrl = new URL(request.url || '/', `http://${configuration.host}:${configuration.port}`);
    if (requestUrl.pathname === '/api/catalog') {
      if (request.method === 'GET') return sendJson(response, 200, catalog.snapshot(database.detectedModels()));
      if (request.method === 'PUT') {
        const origin = `http://${configuration.host}:${configuration.port}`;
        if ((request.headers.origin && request.headers.origin !== origin) || request.headers.host !== `${configuration.host}:${configuration.port}`) {
          return sendJson(response, 403, { error: 'Only local, same-origin catalog updates are allowed.' });
        }
        if (!request.headers['content-type']?.startsWith('application/json')) return sendJson(response, 415, { error: 'Expected application/json.' });
        try {
          const chunks = []; let length = 0;
          for await (const chunk of request) {
            length += chunk.length;
            if (length > 256_000) return sendJson(response, 413, { error: 'Catalog is too large.' });
            chunks.push(chunk);
          }
          const body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
          catalog.update(body.models, (next) => database.updateRateCard(next));
        } catch (error) { return sendJson(response, 400, { error: error.message }); }
        notifyClients();
        return sendJson(response, 200, catalog.snapshot(database.detectedModels()));
      }
    }
    if (request.method === 'GET' && requestUrl.pathname === '/api/widget') {
      const historyMinutes = normalizeWidgetHistoryMinutes(requestUrl.searchParams.get('minutes'));
      return sendJson(response, 200, {
        ...widgetSnapshot(database.database, Date.now(), historyMinutes),
        historyMinutes,
        runningModels: runningModels(database.database),
        state: scanner.snapshot().state,
      });
    }
    if (request.method === 'POST' && requestUrl.pathname === '/api/widget/start') {
      const pid = startWidget();
      return sendJson(response, 202, { accepted: true, pid });
    }
    if (request.method === 'GET' && requestUrl.pathname === '/api/health') {
      return sendJson(response, 200, {
        app: APP_NAME,
        version: APP_VERSION,
        state: scanner.snapshot().state,
        port: configuration.port,
        sessionsRoot: configuration.sessionsRoot,
        counts: database.counts(),
        scanner: scanner.snapshot(),
      });
    }
    if (request.method === 'GET' && requestUrl.pathname === '/api/turns') {
      return sendJson(response, 200, {
        revision,
        turns: database.listRootTurns({
          limit: requestUrl.searchParams.get('limit'),
          days: requestUrl.searchParams.get('days'),
        }),
      });
    }
    if (request.method === 'GET' && requestUrl.pathname === '/api/summary') {
      return sendJson(response, 200, database.summary(requestUrl.searchParams.get('days')));
    }
    if (request.method === 'POST' && requestUrl.pathname === '/api/rescan') {
      scanner.fullScan().catch((error) => console.error(error));
      return sendJson(response, 202, { accepted: true });
    }
    if (request.method === 'GET' && requestUrl.pathname === '/api/events') {
      response.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache, no-transform',
        Connection: 'keep-alive',
        'X-Content-Type-Options': 'nosniff',
      });
      response.write(`event: ready\ndata: ${JSON.stringify({ revision })}\n\n`);
      eventClients.add(response);
      request.on('close', () => eventClients.delete(response));
      return;
    }
    if (request.method === 'GET') return serveStatic(requestUrl.pathname, response);
    sendJson(response, 404, { error: 'Not found' });
  } catch (error) {
    console.error(error);
    sendJson(response, 500, { error: error instanceof Error ? error.message : String(error) });
  }
});

server.listen(configuration.port, configuration.host, () => {
  fs.writeFileSync(configuration.pidPath, String(process.pid), 'utf8');
  console.log(`Codex Usage Monitor ${APP_VERSION} listening on http://${configuration.host}:${configuration.port}`);
  scanner.start().catch((error) => console.error('Scanner startup failed:', error));
});

const heartbeat = setInterval(() => {
  for (const response of eventClients) response.write(': heartbeat\n\n');
}, 20_000);
heartbeat.unref();

async function shutdown(signal) {
  console.log(`Received ${signal}; shutting down.`);
  clearInterval(heartbeat);
  await scanner.stop();
  for (const response of eventClients) response.end();
  await new Promise((resolve) => server.close(resolve));
  database.close();
  try {
    await fsp.unlink(configuration.pidPath);
  } catch {}
  process.exit(0);
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

function sendJson(response, status, value) {
  const body = JSON.stringify(value);
  response.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  response.end(body);
}

async function serveStatic(urlPath, response) {
  const relative = urlPath === '/' ? 'index.html' : decodeURIComponent(urlPath).replace(/^\/+/, '');
  const resolved = path.resolve(PUBLIC_DIRECTORY, relative);
  if (!resolved.startsWith(`${path.resolve(PUBLIC_DIRECTORY)}${path.sep}`) && resolved !== path.join(PUBLIC_DIRECTORY, 'index.html')) {
    return sendJson(response, 403, { error: 'Forbidden' });
  }
  try {
    const content = await fsp.readFile(resolved);
    response.writeHead(200, {
      'Content-Type': contentType(resolved),
      'Content-Length': content.length,
      'Cache-Control': resolved.endsWith('index.html') ? 'no-cache' : 'public, max-age=300',
      'X-Content-Type-Options': 'nosniff',
    });
    response.end(content);
  } catch (error) {
    if (error.code === 'ENOENT') return sendJson(response, 404, { error: 'Not found' });
    throw error;
  }
}

function contentType(filePath) {
  if (filePath.endsWith('.html')) return 'text/html; charset=utf-8';
  if (filePath.endsWith('.css')) return 'text/css; charset=utf-8';
  if (filePath.endsWith('.js')) return 'text/javascript; charset=utf-8';
  if (filePath.endsWith('.svg')) return 'image/svg+xml';
  return 'application/octet-stream';
}

function startWidget() {
  if (process.platform !== 'win32') throw new Error('The desktop widget is only available on Windows.');
  const scriptPath = path.join(ROOT_DIRECTORY, 'scripts', 'Widget.ps1');
  const child = spawn(
    path.join(process.env.SystemRoot || 'C:\\Windows', 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'),
    ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', scriptPath, '-Replace'],
    { stdio: 'ignore', windowsHide: true },
  );
  child.on('error', (error) => console.error('Widget startup failed:', error));
  child.on('exit', (code) => {
    if (code) console.error(`Widget process exited with code ${code}.`);
  });
  return child.pid;
}
