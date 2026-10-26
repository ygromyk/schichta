// Booking flow. Browser and password are passed in so tests can use a fake BCS.
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { AdapterError, buildPlan, formatTasks, germanDate, hhmm, verifySaved } from './plan.mjs';
import { BcsClient } from './bcs-client.mjs';

/**
 * @returns {Promise<{exitCode: number, lines: string[]}>}
 *   0 = booked or dry run ok, 1 = error, 2 = deliberately refused (plan problems, day already has entries)
 */
export async function book({ payload, config, password, dryRun = false, replace = false, openClient = BcsClient.open }) {
  const plan = buildPlan(payload, config);
  const lines = [`BCS ${germanDate(plan.date)} · ${plan.tasks.length} Einträge · ${hhmm(plan.totalMinutes)}${dryRun ? ' · TROCKENLAUF' : ''}`];
  if (plan.problems.length) {
    return { exitCode: 2, lines: [...lines, 'Nicht gebucht:', ...plan.problems.map((p) => '  ✗ ' + p)] };
  }
  if (!password) throw new AdapterError('Kein BCS-Passwort im Schlüsselbund. Einmalig ausführen: schichta-bcs set-password');

  const client = await openClient(config);
  try {
    await client.login(password);
    await client.openDay(plan.date);
    const existing = await client.fetchTasks();
    const mustReplace = existing.length > 0;

    if (mustReplace && !(replace || config.onExisting === 'replace')) {
      return {
        exitCode: 2,
        lines: [...lines, `Nicht gebucht: BCS hat für den Tag schon ${existing.length} Einträge (mit --replace überschreiben):`, ...formatTasks(existing)],
      };
    }
    if (dryRun) {
      return {
        exitCode: 0,
        lines: [...lines, 'Würde buchen:', ...formatTasks(plan.tasks),
          ...(mustReplace ? ['Würde vorher ersetzen:', ...formatTasks(existing)] : []),
          config.presence.set ? `Anwesenheit ${hhmm(plan.totalMinutes + config.presence.breakMinutes)} inkl. ${config.presence.breakMinutes} Min. Pause` : 'Anwesenheit unverändert'],
      };
    }

    if (mustReplace) await client.clearTasks();
    await client.fillTasks(plan.tasks);
    if (config.presence.set) await client.setPresence(plan.totalMinutes, config.presence.breakMinutes);
    await client.save();

    // Verification: reload the day and compare with what BCS actually saved.
    await client.openDay(plan.date);
    const mismatches = verifySaved(plan, await client.fetchTasks());
    if (mismatches.length) {
      return { exitCode: 1, lines: [...lines, 'Gespeichert, aber Gegenprobe weicht ab – bitte in BCS prüfen:', ...mismatches.map((m) => '  ✗ ' + m)] };
    }
    return { exitCode: 0, lines: [...lines, `✓ Gebucht${mustReplace ? ' (ersetzt)' : ''} und in BCS bestätigt:`, ...formatTasks(plan.tasks)] };
  } catch (error) {
    const shot = join(tmpdir(), `schichta-bcs-fehler-${Date.now()}.png`);
    await client.screenshot?.(shot);
    throw new AdapterError(`${error.message}\n  Screenshot der BCS-Seite: ${shot}`, error.exitCode ?? 1);
  } finally {
    await client.close();
  }
}

export async function fetchDay({ date, config, password, openClient = BcsClient.open }) {
  if (!password) throw new AdapterError('Kein BCS-Passwort im Schlüsselbund. Einmalig ausführen: schichta-bcs set-password');
  const client = await openClient(config);
  try {
    await client.login(password);
    await client.openDay(date);
    const tasks = await client.fetchTasks();
    const total = tasks.reduce((sum, t) => sum + t.minutes, 0);
    return [`BCS ${germanDate(date)} · ${tasks.length} Einträge · ${hhmm(total)}`, ...formatTasks(tasks)];
  } finally {
    await client.close();
  }
}
