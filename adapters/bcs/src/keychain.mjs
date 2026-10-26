// BCS password in the macOS Keychain via the built-in `security` tool.
import { execFile, spawn } from 'node:child_process';

const SERVICE = 'schichta-bcs-adapter';

export function getPassword(username) {
  // For automated tests only; day to day always use the Keychain.
  if (process.env.SCHICHTA_BCS_PASSWORD) return Promise.resolve(process.env.SCHICHTA_BCS_PASSWORD);
  return new Promise((resolve) => {
    execFile('/usr/bin/security', ['find-generic-password', '-s', SERVICE, '-a', username, '-w'], (error, stdout) => {
      resolve(error ? null : stdout.replace(/\n$/, ''));
    });
  });
}

/** Asks for the password interactively (`security` reads it itself; it never appears in arguments or logs). */
export function setPasswordInteractive(username) {
  return new Promise((resolve, reject) => {
    const child = spawn('/usr/bin/security', ['add-generic-password', '-U', '-s', SERVICE, '-a', username, '-w'], { stdio: 'inherit' });
    child.on('exit', (code) => (code === 0 ? resolve() : reject(new Error(`security beendet mit Code ${code}`))));
  });
}
