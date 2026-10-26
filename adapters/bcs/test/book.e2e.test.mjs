// Ende-zu-Ende: echter Chrome (headless) gegen den Fake-BCS. Wird übersprungen, wenn Chrome oder puppeteer-core fehlt.
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import { DEFAULT_CHROME, normalizeConfig, parsePayload } from '../src/plan.mjs';
import { startFakeBcs } from './fake-bcs.mjs';

let book;
try {
  ({ book } = await import('../src/book.mjs'));
} catch {
  book = null;
}
const skip = !book || !existsSync(DEFAULT_CHROME) ? 'Chrome oder puppeteer-core (npm install) fehlt' : false;

let bcs;
let config;
before(async () => {
  if (skip) return;
  bcs = await startFakeBcs({ initial: { '2026-10-27': [{ taskId: '222', minutes: 30, description: 'Schon da', ticket: '' }] } });
  config = normalizeConfig({
    url: bcs.url, username: 'max', timeoutMs: 20000, // großzügig: kalter Chrome-Start unter Last
    mapping: [{ source: 'ticket', regex: '^PROJ-', taskId: '111' }, { source: 'description', regex: 'daily', taskId: '222' }],
  });
});
after(() => bcs?.close());

const payload = (date) => parsePayload(JSON.stringify({ date, entries: [
  { id: 'a', ticket: 'PROJ-1', description: 'Review', minutes: 90, estimated: false },
  { id: 'b', ticket: 'PROJ-2', description: 'Fix', minutes: 30, estimated: false },
  { id: 'c', ticket: '', description: 'Daily', minutes: 15, estimated: false },
] }));

test('bucht einen leeren Tag und bestätigt per Gegenprobe', { skip }, async () => {
  const result = await book({ payload: payload('2026-10-26'), config, password: 'geheim' });
  assert.equal(result.exitCode, 0, result.lines.join('\n'));
  const saved = bcs.state.days.get('2026-10-26');
  assert.deepEqual(saved.records, [
    { taskId: '111', minutes: 90, description: 'Review', ticket: 'PROJ-1' },
    { taskId: '111', minutes: 30, description: 'Fix', ticket: 'PROJ-2' },
    { taskId: '222', minutes: 15, description: 'Daily', ticket: '' },
  ]);
  assert.deepEqual(saved.presence, [135 + 60, 60], 'Anwesenheit = Summe + Pause, zweite Zeile = Pause');
});

test('lehnt einen schon belegten Tag ohne --replace ab', { skip }, async () => {
  const saves = bcs.state.saves;
  const result = await book({ payload: payload('2026-10-27'), config, password: 'geheim' });
  assert.equal(result.exitCode, 2);
  assert.match(result.lines.join('\n'), /schon 1 Einträge/);
  assert.equal(bcs.state.saves, saves, 'darf nichts speichern');
});

test('Trockenlauf speichert nichts', { skip }, async () => {
  const saves = bcs.state.saves;
  const result = await book({ payload: payload('2026-10-27'), config, password: 'geheim', dryRun: true, replace: true });
  assert.equal(result.exitCode, 0);
  assert.match(result.lines.join('\n'), /Würde vorher ersetzen/);
  assert.equal(bcs.state.saves, saves);
});

test('--replace ersetzt vorhandene Einträge', { skip }, async () => {
  const result = await book({ payload: payload('2026-10-27'), config, password: 'geheim', replace: true });
  assert.equal(result.exitCode, 0, result.lines.join('\n'));
  const records = bcs.state.days.get('2026-10-27').records;
  assert.equal(records.length, 3);
  assert.ok(!records.some((r) => r.description === 'Schon da'));
});

test('falsches Passwort wird als Login-Fehler gemeldet', { skip }, async () => {
  await assert.rejects(book({ payload: payload('2026-10-28'), config, password: 'falsch' }), /Login fehlgeschlagen/);
});

test('Plan-Probleme brechen ab, bevor ein Browser startet', async () => {
  let opened = false;
  const p = parsePayload(JSON.stringify({ date: '2026-10-26', entries: [{ ticket: 'X-1', description: 'Unbekannt', minutes: 10 }] }));
  const cfg = normalizeConfig({ url: 'https://bcs.example.com', username: 'max' });
  const result = await (book ?? (await import('../src/book.mjs')).book)({ payload: p, config: cfg, password: 'x', openClient: () => { opened = true; } });
  assert.equal(result.exitCode, 2);
  assert.equal(opened, false);
});
