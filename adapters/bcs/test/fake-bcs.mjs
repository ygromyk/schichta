// Minimaler Nachbau der BCS-Tageserfassung mit genau den Selektoren, die bcs-client.mjs nutzt.
// Prüft unseren Ablauf (Login, Tageswechsel, Füllen, Speichern, Gegenprobe) – nicht, ob ein echtes BCS gleich aussieht.
import { createServer } from 'node:http';

export function startFakeBcs({ username = 'max', password = 'geheim', initial = {} } = {}) {
  const days = new Map(Object.entries(initial).map(([d, records]) => [d, { records, presence: [0, 0] }]));
  const state = { days, saves: 0 };
  const groups = ['111', '222'];

  const loginPage = () => `<!doctype html><form method="post" action="/bcs/login">
    <input id="label_user" name="user"><input id="label_pwd" name="pwd" type="password">
    <button id="loginbutton" type="submit">Anmelden</button></form>`;

  const row = (taskId, r = {}) => `<tr data-listtaskgroupoid="${taskId}_JTask">
    <td name="effortExpense"><span><input value="${r.minutes ? Math.floor(r.minutes / 60) : ''}"><b>:</b><input value="${r.minutes ? r.minutes % 60 : ''}"></span></td>
    <td name="description"><textarea>${r.description ?? ''}</textarea></td>
    <td name="effortAttr1"><input value="${r.ticket ?? ''}"></td>
    <td name="[plusminus]"><button type="button" onclick="addRow(this)">+</button></td>
    <td><a class="cleanTimeRecordingRow_Link" href="#" onclick="cleanRow(this);return false">x</a></td></tr>`;

  const dayPage = (date, saved) => {
    const day = days.get(date) ?? { records: [], presence: [0, 0] };
    const [y, m, d] = date.split('-');
    const rows = groups.map((g) => day.records.filter((r) => r.taskId === g).map((r) => row(g, r)).join('') + row(g)).join('');
    const presence = day.presence.map((p) => `<tr><td name="attandenceDuration"><span><input value="${Math.floor(p / 60)}"><b>:</b><input value="${p % 60}"></span></td></tr>`).join('');
    return `<!doctype html><input class="notificationPermissionLater" type="button" onclick="this.remove()">
    ${saved ? '<div id="TimeRecordingService_Success">Gespeichert</div>' : ''}
    <span id="daytimerecording,Selections,effortRecordingDate_intervaldisplay">Mo ${d}.${m}.${y}</span><div id="cal"></div>
    <table id="daytimerecording,Content,daytimerecordingTaskList_table"><tbody>${rows}</tbody></table>
    <table id="presence"><tbody>${presence}</tbody></table>
    <input class="button" data-bcs-button-name="Apply" type="button" value="Übernehmen" onclick="save()">
    <script>
      var PopupCalendar = { reloadPageByCalendar(field, y, m, d) {
        const a = document.createElement('a'); a.className = 'dayHighlighted'; a.textContent = d;
        a.href = '/bcs/mybcs/dayeffortrecording/?date=' + y + '-' + String(m + 1).padStart(2, '0') + '-' + String(d).padStart(2, '0');
        document.getElementById('cal').append(a);
      } };
      function addRow(btn) {
        const g = btn.closest('tr').dataset.listtaskgroupoid;
        const rows = document.querySelectorAll('tr[data-listtaskgroupoid="' + g + '"]');
        const clone = rows[rows.length - 1].cloneNode(true);
        clone.querySelectorAll('input, textarea').forEach((el) => { el.value = ''; });
        rows[rows.length - 1].after(clone);
      }
      function cleanRow(a) { a.closest('tr').querySelectorAll('input, textarea').forEach((el) => { el.value = ''; }); }
      async function save() {
        const num = (el) => parseInt(el.value, 10) || 0;
        const records = [...document.querySelectorAll('tr[data-listtaskgroupoid]')].map((tr) => {
          const [h, , m] = tr.querySelector('td[name="effortExpense"] > span').children;
          return { taskId: tr.dataset.listtaskgroupoid.replace('_JTask', ''), minutes: num(h) * 60 + num(m),
                   description: tr.querySelector('textarea').value, ticket: tr.querySelector('td[name="effortAttr1"] > input').value };
        }).filter((r) => r.minutes || r.description || r.ticket);
        const presence = [...document.querySelectorAll('td[name="attandenceDuration"] > span')].map((s) => num(s.children[0]) * 60 + num(s.children[2]));
        await fetch('/bcs/save?date=${date}', { method: 'POST', body: JSON.stringify({ records, presence }) });
        location = '/bcs/mybcs/dayeffortrecording/?date=${date}&saved=1';
      }
    </script>`;
  };

  const server = createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    const body = await new Promise((resolve) => { let b = ''; req.on('data', (c) => { b += c; }); req.on('end', () => resolve(b)); });
    const loggedIn = /sid=ok/.test(req.headers.cookie ?? '');
    const send = (html, headers = {}) => { res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', ...headers }); res.end(html); };
    const redirect = (to, headers = {}) => { res.writeHead(302, { Location: to, ...headers }); res.end(); };

    if (url.pathname === '/bcs/login' && req.method === 'POST') {
      const form = new URLSearchParams(body);
      if (form.get('user') === username && form.get('pwd') === password) return redirect('/bcs/mybcs/dayeffortrecording/', { 'Set-Cookie': 'sid=ok; Path=/' });
      return send(loginPage());
    }
    if (url.pathname === '/bcs/login') return send(loginPage());
    if (!loggedIn) return redirect('/bcs/login');
    if (url.pathname === '/bcs/mybcs/dayeffortrecording/') {
      return send(dayPage(url.searchParams.get('date') ?? '2026-10-01', url.searchParams.has('saved')));
    }
    if (url.pathname === '/bcs/save' && req.method === 'POST') {
      days.set(url.searchParams.get('date'), JSON.parse(body));
      state.saves += 1;
      res.writeHead(204); return res.end();
    }
    res.writeHead(404); res.end();
  });

  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => {
    resolve({ url: `http://127.0.0.1:${server.address().port}`, state, close: () => new Promise((r) => server.close(r)) });
  }));
}
