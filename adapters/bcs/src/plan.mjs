// Pure logic, no browser/network: validate input, map tickets to BCS tasks, compare results.
import { homedir } from 'node:os';
import { join } from 'node:path';

export const DEFAULT_CONFIG_PATH = join(homedir(), '.config', 'schichta-bcs-adapter', 'config.json');
export const DEFAULT_CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

export class AdapterError extends Error {
  constructor(message, exitCode = 1) {
    super(message);
    this.exitCode = exitCode;
  }
}

/** Reads the Schichta hook payload (stdin) and keeps only the fields booking needs. */
export function parsePayload(text) {
  let data;
  try {
    data = JSON.parse(text);
  } catch {
    throw new AdapterError('Eingabe ist kein gültiges JSON (erwartet: Schichta-Hook-Payload auf stdin).');
  }
  if (!/^\d{4}-\d{2}-\d{2}$/.test(data?.date ?? '')) throw new AdapterError('"date" fehlt oder ist nicht YYYY-MM-DD.');
  if (!Array.isArray(data.entries)) throw new AdapterError('"entries" fehlt.');
  const entries = data.entries.map((e, i) => {
    if (!Number.isInteger(e?.minutes) || e.minutes < 1 || e.minutes > 1440) {
      throw new AdapterError(`Eintrag ${i + 1}: "minutes" muss eine ganze Zahl zwischen 1 und 1440 sein.`);
    }
    if (e.description != null && typeof e.description !== 'string') {
      throw new AdapterError(`Eintrag ${i + 1}: "description" muss Text sein.`);
    }
    return {
      id: String(e.id ?? i),
      ticket: String(e.ticket ?? '').trim(),
      description: (e.description ?? '').trim(),
      minutes: e.minutes,
      estimated: e.estimated === true,
      project: String(e.projectName ?? e.project ?? '').trim(),
    };
  });
  return { date: data.date, entries };
}

export function normalizeConfig(raw) {
  const c = raw ?? {};
  let url;
  try {
    url = new URL(c.url);
  } catch {
    throw new AdapterError('config.url fehlt oder ist ungültig (z. B. "https://bcs.firma.de").');
  }
  const isLocal = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && isLocal)) {
    throw new AdapterError('config.url muss https verwenden (http nur für localhost).');
  }
  if (typeof c.username !== 'string' || !c.username) throw new AdapterError('config.username fehlt.');

  // Task IDs end up in CSS selectors: allow digits only.
  const taskId = (value, where) => {
    const id = String(value);
    if (!/^\d+$/.test(id)) throw new AdapterError(`${where}: Task-ID "${id}" muss aus Ziffern bestehen.`);
    return id;
  };
  const mapping = (c.mapping ?? []).map((m, i) => {
    if (!['ticket', 'description', 'project'].includes(m.source)) {
      throw new AdapterError(`mapping[${i}].source muss ticket, description oder project sein.`);
    }
    let regex;
    try {
      regex = new RegExp(m.regex, 'i');
    } catch {
      throw new AdapterError(`mapping[${i}].regex ist kein gültiger regulärer Ausdruck.`);
    }
    return { source: m.source, regex, taskId: taskId(m.taskId, `mapping[${i}]`) };
  });

  const onExisting = c.onExisting ?? 'refuse';
  if (!['refuse', 'replace'].includes(onExisting)) throw new AdapterError('config.onExisting muss refuse oder replace sein.');
  const ticketField = c.ticketField === undefined ? 'effortAttr1' : c.ticketField;
  if (ticketField !== null && !/^[A-Za-z0-9_]+$/.test(ticketField)) throw new AdapterError('config.ticketField ist ungültig.');

  return {
    url: url.origin + url.pathname.replace(/\/+$/, ''),
    username: c.username,
    mapping,
    defaultTaskId: c.defaultTaskId == null ? null : taskId(c.defaultTaskId, 'defaultTaskId'),
    onExisting,
    allowEstimated: c.allowEstimated === true,
    presence: { set: c.presence?.set !== false, breakMinutes: c.presence?.breakMinutes ?? 60 },
    ticketField,
    chromePath: c.chromePath ?? DEFAULT_CHROME,
    timeoutMs: c.timeoutMs ?? 30000,
  };
}

/** Maps every entry to a BCS task. Problems are collected instead of stopping at the first. */
export function buildPlan(payload, config) {
  const problems = [];
  const tasks = [];
  for (const e of payload.entries) {
    const label = `${e.ticket ? e.ticket + ' ' : ''}${e.description}`;
    if (e.estimated && !config.allowEstimated) {
      problems.push(`„${label}“ ist als Schätzung markiert – erst in Schichta bestätigen.`);
      continue;
    }
    const match = config.mapping.find((m) => m.regex.test(e[m.source]));
    const taskId = match?.taskId ?? config.defaultTaskId;
    if (!taskId) {
      problems.push(`Kein BCS-Task für „${label}“ – mapping in der Konfiguration ergänzen.`);
      continue;
    }
    tasks.push({ taskId, ticket: e.ticket, description: e.description, minutes: e.minutes });
  }
  if (payload.entries.length === 0) problems.push('Keine Einträge für diesen Tag.');
  const totalMinutes = tasks.reduce((sum, t) => sum + t.minutes, 0);
  return { date: payload.date, tasks, totalMinutes, problems };
}

export function hhmm(minutes) {
  return `${String(Math.floor(minutes / 60)).padStart(2, '0')}:${String(minutes % 60).padStart(2, '0')}`;
}

export function germanDate(date) {
  const [y, m, d] = date.split('-');
  return `${d}.${m}.${y}`;
}

export function formatTasks(tasks) {
  return tasks.map((t) => `  ${hhmm(t.minutes)}  Task ${t.taskId}  ${t.ticket ? '[' + t.ticket + '] ' : ''}${t.description}`);
}

/** After saving: do the minutes per task in BCS match the plan? */
export function verifySaved(plan, fetched) {
  const sum = (list) => list.reduce((acc, t) => acc.set(t.taskId, (acc.get(t.taskId) ?? 0) + t.minutes), new Map());
  const expected = sum(plan.tasks);
  const actual = sum(fetched);
  const mismatches = [];
  for (const [taskId, minutes] of expected) {
    const got = actual.get(taskId) ?? 0;
    if (got !== minutes) mismatches.push(`Task ${taskId}: erwartet ${hhmm(minutes)}, in BCS ${hhmm(got)}`);
  }
  return mismatches;
}
