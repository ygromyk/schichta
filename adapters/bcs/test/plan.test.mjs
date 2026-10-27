import { test } from 'node:test';
import assert from 'node:assert/strict';
import { AdapterError, buildPlan, normalizeConfig, parsePayload, verifySaved } from '../src/plan.mjs';

const config = normalizeConfig({
  url: 'https://bcs.example.com/',
  username: 'max',
  mapping: [
    { source: 'ticket', regex: '^PROJ-', taskId: '111' },
    { source: 'description', regex: 'daily', taskId: '222' },
  ],
});

const payload = (entries) => parsePayload(JSON.stringify({ date: '2026-10-26', entries }));

test('parsePayload keeps the Schichta hook fields', () => {
  const p = payload([{ id: 'a', ticket: ' PROJ-1 ', description: ' Review ', minutes: 90, estimated: false, projectName: 'App' }]);
  assert.deepEqual(p.entries[0], { id: 'a', ticket: 'PROJ-1', description: 'Review', minutes: 90, estimated: false, project: 'App' });
});

test('parsePayload rejects broken input', () => {
  assert.throws(() => parsePayload('nope'), AdapterError);
  assert.throws(() => parsePayload('{"date":"26.10.2026","entries":[]}'), /YYYY-MM-DD/);
  assert.throws(() => payload([{ description: 'x', minutes: 0 }]), /minutes/);
  assert.throws(() => payload([{ description: 42, minutes: 5 }]), /description/);
});

test('parsePayload accepts entries without a description', () => {
  assert.equal(payload([{ ticket: 'PROJ-1', description: ' ', minutes: 15 }]).entries[0].description, '');
  assert.equal(payload([{ ticket: 'PROJ-1', minutes: 15 }]).entries[0].description, '');
});

test('mapping: first matching rule wins, case-insensitive', () => {
  const plan = buildPlan(payload([
    { ticket: 'proj-7', description: 'Daily', minutes: 15 },
    { ticket: '', description: 'Daily Standup', minutes: 15 },
  ]), config);
  assert.deepEqual(plan.tasks.map((t) => t.taskId), ['111', '222']);
  assert.equal(plan.totalMinutes, 30);
  assert.deepEqual(plan.problems, []);
});

test('no mapping means no silent default task', () => {
  const plan = buildPlan(payload([{ ticket: 'OTHER-1', description: 'Irgendwas', minutes: 30 }]), config);
  assert.equal(plan.tasks.length, 0);
  assert.match(plan.problems[0], /Kein BCS-Task/);

  const withDefault = buildPlan(payload([{ ticket: 'OTHER-1', description: 'Irgendwas', minutes: 30 }]), { ...config, defaultTaskId: '999' });
  assert.equal(withDefault.tasks[0].taskId, '999');
});

test('estimates are refused by default', () => {
  const entries = [{ ticket: 'PROJ-1', description: 'Review', minutes: 30, estimated: true }];
  assert.match(buildPlan(payload(entries), config).problems[0], /Schätzung/);
  assert.deepEqual(buildPlan(payload(entries), { ...config, allowEstimated: true }).problems, []);
});

test('config: https enforced, task IDs digits only', () => {
  assert.throws(() => normalizeConfig({ url: 'http://bcs.example.com', username: 'x' }), /https/);
  assert.doesNotThrow(() => normalizeConfig({ url: 'http://127.0.0.1:9', username: 'x' }));
  assert.throws(() => normalizeConfig({ url: 'https://a.test', username: 'x', mapping: [{ source: 'ticket', regex: 'x', taskId: '1"]' }] }), /Ziffern/);
  assert.throws(() => normalizeConfig({ url: 'https://a.test', username: 'x', onExisting: 'merge' }), /onExisting/);
  assert.equal(config.url, 'https://bcs.example.com');
  assert.equal(config.onExisting, 'refuse');
  assert.deepEqual(config.presence, { set: true, breakMinutes: 60 });
});

test('verifySaved compares minutes per task', () => {
  const plan = { tasks: [{ taskId: '111', minutes: 30 }, { taskId: '111', minutes: 15 }, { taskId: '222', minutes: 60 }] };
  assert.deepEqual(verifySaved(plan, [{ taskId: '111', minutes: 45 }, { taskId: '222', minutes: 60 }]), []);
  assert.match(verifySaved(plan, [{ taskId: '111', minutes: 45 }])[0], /Task 222/);
});
