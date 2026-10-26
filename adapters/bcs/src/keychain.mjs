// BCS-Passwort im macOS-Schlüsselbund über das mitgelieferte `security`-Werkzeug.
import { execFile, spawn } from 'node:child_process';

const SERVICE = 'zeitbuch-bcs-adapter';

export function getPassword(username) {
  // Nur für automatisierte Tests gedacht; im Alltag immer den Schlüsselbund nutzen.
  if (process.env.ZEITBUCH_BCS_PASSWORD) return Promise.resolve(process.env.ZEITBUCH_BCS_PASSWORD);
  return new Promise((resolve) => {
    execFile('/usr/bin/security', ['find-generic-password', '-s', SERVICE, '-a', username, '-w'], (error, stdout) => {
      resolve(error ? null : stdout.replace(/\n$/, ''));
    });
  });
}

/** Fragt das Passwort interaktiv ab (`security` liest es selbst ein, es erscheint nie in Argumenten oder Logs). */
export function setPasswordInteractive(username) {
  return new Promise((resolve, reject) => {
    const child = spawn('/usr/bin/security', ['add-generic-password', '-U', '-s', SERVICE, '-a', username, '-w'], { stdio: 'inherit' });
    child.on('exit', (code) => (code === 0 ? resolve() : reject(new Error(`security beendet mit Code ${code}`))));
  });
}
