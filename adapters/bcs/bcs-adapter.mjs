#!/usr/bin/env node
// schichta-bcs: books a Schichta day into Projektron BCS. Standalone; Schichta only calls it as a shell hook.
import { readFile } from 'node:fs/promises';
import { AdapterError, DEFAULT_CONFIG_PATH, normalizeConfig, parsePayload, buildPlan, formatTasks, germanDate, hhmm } from './src/plan.mjs';
import { getPassword, setPasswordInteractive } from './src/keychain.mjs';

const USAGE = `schichta-bcs <befehl> [optionen]

  plan              Payload prüfen und Zuordnung zeigen (ohne BCS-Zugriff)
  book              Tag in BCS buchen
    --dry-run       einloggen und prüfen, aber nichts speichern
    --replace       vorhandene Einträge des Tages ersetzen
  fetch --date D    vorhandene BCS-Einträge eines Tages (YYYY-MM-DD) anzeigen
  set-password      BCS-Passwort im Schlüsselbund speichern

  --config PFAD     Konfiguration (Standard: ${DEFAULT_CONFIG_PATH})
  --input PFAD      Payload aus Datei statt stdin (Schichta setzt auch SCHICHTA_JSON_FILE)

Exit-Codes: 0 ok · 1 Fehler · 2 abgelehnt (Plan-Probleme oder Tag schon belegt)`;

function parseArgs(argv) {
  const args = { command: argv[0], flags: new Set(), options: {} };
  for (let i = 1; i < argv.length; i++) {
    const a = argv[i];
    if (['--config', '--input', '--date'].includes(a)) args.options[a.slice(2)] = argv[++i];
    else if (a.startsWith('--')) args.flags.add(a.slice(2));
    else throw new AdapterError(`Unbekanntes Argument: ${a}\n\n${USAGE}`);
  }
  return args;
}

async function readStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf8');
}

async function loadConfig(path) {
  let text;
  try {
    text = await readFile(path, 'utf8');
  } catch {
    throw new AdapterError(`Konfiguration nicht gefunden: ${path}\nVorlage: config.example.json im Adapter-Ordner.`);
  }
  try {
    return normalizeConfig(JSON.parse(text));
  } catch (e) {
    throw e instanceof AdapterError ? e : new AdapterError(`Konfiguration ist kein gültiges JSON: ${path}`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (!args.command || args.command === 'help' || args.flags.has('help')) {
    console.log(USAGE);
    return 0;
  }
  const config = await loadConfig(args.options.config ?? DEFAULT_CONFIG_PATH);

  switch (args.command) {
    case 'set-password':
      await setPasswordInteractive(config.username);
      console.log(`Passwort für ${config.username} im Schlüsselbund gespeichert.`);
      return 0;

    case 'fetch': {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(args.options.date ?? '')) throw new AdapterError('--date YYYY-MM-DD fehlt.');
      const { fetchDay } = await import('./src/book.mjs');
      console.log((await fetchDay({ date: args.options.date, config, password: await getPassword(config.username) })).join('\n'));
      return 0;
    }

    case 'plan':
    case 'book': {
      const inputPath = args.options.input ?? (process.stdin.isTTY ? process.env.SCHICHTA_JSON_FILE : undefined);
      const payload = parsePayload(inputPath ? await readFile(inputPath, 'utf8') : await readStdin());
      if (args.command === 'plan') {
        const plan = buildPlan(payload, config);
        console.log([`Plan ${germanDate(plan.date)} · ${hhmm(plan.totalMinutes)}`, ...formatTasks(plan.tasks), ...plan.problems.map((p) => '  ✗ ' + p)].join('\n'));
        return plan.problems.length ? 2 : 0;
      }
      // Load the browser dependency only when needed (plan works without npm install).
      const { book } = await import('./src/book.mjs');
      const result = await book({
        payload, config,
        password: await getPassword(config.username),
        dryRun: args.flags.has('dry-run'),
        replace: args.flags.has('replace'),
      });
      console.log(result.lines.join('\n'));
      return result.exitCode;
    }

    default:
      throw new AdapterError(`Unbekannter Befehl: ${args.command}\n\n${USAGE}`);
  }
}

main().then(
  (code) => process.exit(code),
  (error) => {
    console.error('✗ ' + error.message);
    process.exit(error instanceof AdapterError ? error.exitCode : 1);
  },
);
