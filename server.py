"""Local UI and read-only Git summaries. No credentials, writes, or remote calls."""
import datetime as dt
import json
import os
import re
import subprocess
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent
# Configured via environment so no personal paths or names live in the code.
REPOS = [Path(p).expanduser() for p in os.environ.get('SCHICHTA_REPOS', '').split(os.pathsep) if p]

def git_user_name():
    try:
        return subprocess.run(['git', 'config', '--global', 'user.name'], capture_output=True,
                              text=True, timeout=5, check=False).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ''

AUTHOR = os.environ.get('SCHICHTA_AUTHOR') or git_user_name()
STATIC = {'/', '/index.html', '/style.css', '/core.js', '/app.js'}
HOST = '127.0.0.1:8765'

def day_bounds(value):
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}', value):
        raise ValueError('Datum muss YYYY-MM-DD sein.')
    day = dt.date.fromisoformat(value)
    zone = ZoneInfo('Europe/Berlin')
    return (dt.datetime.combine(day, dt.time.min, zone),
            dt.datetime.combine(day + dt.timedelta(days=1), dt.time.min, zone))

def run_git(repo, args):
    try:
        result = subprocess.run(['git', '-C', str(repo), *args], capture_output=True,
                                text=True, timeout=15, check=False)
        if result.returncode:
            return {'error': 'Git-Abfrage fehlgeschlagen; Repository oder Berechtigungen prüfen.'}
        return {'text': result.stdout[:100000], 'truncated': len(result.stdout) > 100000}
    except (OSError, subprocess.TimeoutExpired):
        return {'error': 'Git nicht verfügbar oder Zeitlimit überschritten.'}

def activity(value):
    start, end = day_bounds(value)
    # Git until is inclusive, so exclude next day's midnight explicitly.
    dates = [f'--since={start.isoformat()}', f'--until={(end - dt.timedelta(seconds=1)).isoformat()}']
    repos = []
    for repo in REPOS:
        repos.append({
            'repository': repo.name,
            'commits': run_git(repo, ['log', '--all', '--since-as-filter=' + start.isoformat(),
                                     dates[1], '--author=^' + re.sub(r'([.^$*+?()\[\]{}|\\])', r'\\\1', AUTHOR) + ' <', '-n', '150',
                                     '--format=%h | Autorzeit: %aI | Commitzeit: %cI | %s']),
            'head_activity': run_git(repo, ['reflog', 'show', 'HEAD', *dates, '-n', '200',
                                            '--date=iso-strict', '--format=%gD | %gs']),
        })
    return {'date': value, 'timezone': 'Europe/Berlin', 'repositories': repos,
            'scope': 'Lokale Git-Referenzen; kein Fetch. Maximal 150 eigene Commits und 200 HEAD-Aktivitäten je Repository. Commit-Auswahl nach Commitzeit; Autorzeit separat. Merges und Reflogs belegen keine Arbeitsdauer. Keine Chat-, Teams- oder Kalenderdaten.'}

class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        # Restrict local access, including browser cross-origin/DNS-rebinding requests.
        if self.headers.get('Host') != HOST:
            self.send_error(403); return
        origin = self.headers.get('Origin')
        if origin and origin != 'http://' + HOST:
            self.send_error(403); return
        if self.headers.get('Sec-Fetch-Site') == 'cross-site':
            self.send_error(403); return
        url = urlsplit(self.path)
        if url.path == '/api/activity':
            try:
                query = parse_qs(url.query, strict_parsing=True)
                if set(query) != {'date'} or len(query['date']) != 1:
                    raise ValueError('Genau ein Datum ist erforderlich.')
                payload = activity(query['date'][0])
                body = json.dumps(payload, ensure_ascii=False).encode()
                self.send_response(200)
                self.send_header('Content-Type', 'application/json; charset=utf-8')
                self.send_header('Cache-Control', 'no-store')
                self.send_header('Content-Length', str(len(body)))
                self.end_headers(); self.wfile.write(body)
            except ValueError:
                self.send_error(400, 'Invalid date')
            return
        if url.path not in STATIC:
            self.send_error(404); return
        super().do_GET()

if __name__ == '__main__':
    print('Schichta: http://' + HOST, flush=True)
    ThreadingHTTPServer(('127.0.0.1', 8765), Handler).serve_forever()
