'use strict';
const $ = id => document.getElementById(id);
const Z = Zeitbuch, KEY = 'zeitbuch.v1';
const desktop = window.webkit?.messageHandlers?.zeitbuch;
const nativeCall = (action, values = {}) => desktop.postMessage({action, ...values});
const copyText = text => desktop ? nativeCall('copy', {text}) : navigator.clipboard.writeText(text);
let data = {version: 1, entries: []}, editing = null, storageBroken = false;
const berlinDay = () => new Intl.DateTimeFormat('sv-SE', {timeZone: 'Europe/Berlin', year: 'numeric', month: '2-digit', day: '2-digit'}).format(new Date());
const notify = message => { $('notice').textContent = message; };
try {
  const raw = localStorage.getItem(KEY);
  if (raw) data = Z.validate(JSON.parse(raw));
} catch (e) {
  storageBroken = true;
  notify('Gespeicherte Daten konnten nicht geladen werden. Sie werden nicht überschrieben. Bitte zuerst eine Sicherung exportieren und dann eine gültige Sicherung importieren.');
}
$('day').value = berlinDay();
function dayEntries() { return data.entries.filter(e => e.date === $('day').value); }
function persist(next) {
  if (storageBroken) throw new Error('Speicher gesperrt. Zuerst eine gültige Sicherung importieren.');
  localStorage.setItem(KEY, JSON.stringify(next));
  data = next;
  $('save-state').textContent = 'Lokal gespeichert';
}
function node(tag, text, className) {
  const el = document.createElement(tag);
  if (text !== undefined) el.textContent = text;
  if (className) el.className = className;
  return el;
}
function resetForm() {
  editing = null; $('entry-form').reset(); $('cancel').hidden = true;
  $('form-title').textContent = 'Was hast du gemacht?'; $('save-entry').textContent = '＋ Eintrag speichern';
}
function render() {
  const entries = dayEntries(), total = entries.reduce((s, e) => s + e.minutes, 0);
  const estimates = entries.filter(e => e.estimated).length;
  $('total').replaceChildren(document.createTextNode(Z.time(total)), node('span', ' h'));
  $('count').textContent = entries.length; $('estimates').textContent = estimates;
  $('day-name').textContent = new Intl.DateTimeFormat('de-DE', {weekday: 'long', day: 'numeric', month: 'long', year: 'numeric', timeZone: 'Europe/Berlin'}).format(new Date($('day').value + 'T12:00:00Z'));
  $('list-date').textContent = Z.date($('day').value);
  $('output').value = entries.length ? Z.report($('day').value, entries) : 'Dein Tagesentwurf erscheint hier, sobald du eine Tätigkeit speicherst.';
  $('copy').disabled = $('download').disabled = !entries.length;
  $('save-entry').disabled = storageBroken;
  $('save-state').textContent = storageBroken ? 'Speicher nicht verfügbar' : desktop ? 'In dieser Desktop-App' : 'In diesem Browser';
  const openTickets = entries.filter(e => !e.ticket || e.ticket === 'PROJ-0').length;
  $('review').textContent = !entries.length ? 'Noch keine Einträge. Beginne mit deiner ersten Tätigkeit.' : total > 1440 ? 'Die Summe überschreitet 24 Stunden. Bitte korrigieren.' : estimates ? `${estimates} geschätzte Zeit${estimates > 1 ? 'en' : ''} vor der Buchung prüfen.` : 'Zeiten erfasst. Prüfe zum Tagesabschluss, ob alles vollständig ist.';
  if (openTickets) $('review').textContent += ` ${openTickets} Ticketzuordnung${openTickets > 1 ? 'en' : ''} offen.`;
  $('review').classList.toggle('warning', Boolean(estimates || openTickets || total > 1440));
  $('tickets').replaceChildren(...[...new Set(data.entries.map(e => e.ticket).filter(Boolean))].sort().map(value => { const o = node('option'); o.value = value; return o; }));
  const list = $('entries'); list.replaceChildren();
  if (!entries.length) {
    const empty = node('div', undefined, 'empty');
    empty.append(node('div', '+', 'circle'), node('strong', 'Platz für deinen Arbeitstag.'), node('p', 'Auch kurze Abstimmungen und Analysen zählen.')); list.append(empty);
  }
  entries.forEach(e => {
    const row = node('div', undefined, 'entry'), left = node('div'), right = node('div');
    left.append(node('span', e.ticket || 'Ohne Ticket', 'badge'), node('p', e.description));
    const actions = node('div', undefined, 'actions');
    const edit = node('button', 'Bearbeiten'); edit.onclick = () => {
      editing = e.id; $('ticket').value = e.ticket; $('duration').value = Z.time(e.minutes); $('description').value = e.description; $('estimated').checked = e.estimated;
      $('form-title').textContent = 'Eintrag bearbeiten'; $('save-entry').textContent = 'Änderungen speichern'; $('cancel').hidden = false; $('description').focus();
    };
    const remove = node('button', 'Löschen'); remove.setAttribute('aria-label', `Löschen: ${e.description}`);
    remove.onclick = () => {
      if (!confirm('Diesen Eintrag löschen?')) return;
      try { persist({...data, entries: data.entries.filter(x => x.id !== e.id)}); if (editing === e.id) resetForm(); render(); notify('Eintrag gelöscht.'); } catch (err) { notify('Nicht gelöscht: ' + err.message); }
    };
    actions.append(edit, remove); left.append(actions); right.append(node('div', Z.time(e.minutes), 'entry-time'));
    if (e.estimated) right.append(node('div', 'Geschätzt', 'estimated'));
    row.append(left, right); list.append(row);
  });
}
$('entry-form').onsubmit = event => {
  event.preventDefault();
  try {
    const entry = {id: editing || crypto.randomUUID(), date: $('day').value, ticket: $('ticket').value.trim().toUpperCase(), description: $('description').value.trim(), minutes: Z.minutes($('duration').value), estimated: $('estimated').checked};
    const entries = editing ? data.entries.map(e => e.id === editing ? entry : e) : [...data.entries, entry];
    if (entries.filter(e => e.date === entry.date).reduce((sum, e) => sum + e.minutes, 0) > 1440) throw new Error('Die Tagessumme darf 24 Stunden nicht überschreiten.');
    persist(Z.validate({...data, entries})); resetForm(); render(); notify('Eintrag lokal gespeichert.');
  } catch (err) { notify('Nicht gespeichert: ' + err.message); }
};
$('cancel').onclick = resetForm;
function canLeave() { return !($('description').value || $('duration').value || $('ticket').value) || confirm('Nicht gespeicherte Eingabe verwerfen?'); }
let currentDay = $('day').value;
function selectDay(value) {
  if (!Z.validDate(value) || !saveJournal() || !canLeave()) { $('day').value = currentDay; return; }
  currentDay = value; $('day').value = value; resetForm(); render(); loadJournal();
}
$('day').onchange = () => selectDay($('day').value);
function moveDay(offset) { const d = new Date(currentDay + 'T12:00:00Z'); d.setUTCDate(d.getUTCDate() + offset); selectDay(d.toISOString().slice(0, 10)); }
$('previous').onclick = () => moveDay(-1); $('next').onclick = () => moveDay(1); $('today').onclick = () => selectDay(berlinDay());
function download(name, content, type) {
  if (desktop) { nativeCall('save', {name, content}).catch(err => notify('Export fehlgeschlagen: ' + err)); return; }
  const url = URL.createObjectURL(new Blob([content], {type})); const a = node('a'); a.href = url; a.download = name; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
$('download').onclick = () => download(`Tagesentwurf-${currentDay}.txt`, Z.report(currentDay, dayEntries()), 'text/plain;charset=utf-8');
$('backup').onclick = () => {
  try { download(`Zeitbuch-Sicherung-${berlinDay()}.json`, storageBroken ? (localStorage.getItem(KEY) || '{}') : JSON.stringify(data, null, 2), 'application/json'); } catch (err) { notify('Sicherung fehlgeschlagen: ' + err.message); }
};
$('copy').onclick = async () => {
  try { await copyText(Z.report(currentDay, dayEntries())); notify('Tagesentwurf kopiert. Es wurde nichts übertragen.'); }
  catch { $('output').focus(); $('output').select(); notify('Bitte den markierten Entwurf mit ⌘C oder Strg+C kopieren.'); }
};
$('restore').onchange = async event => {
  const file = event.target.files[0]; if (!file) return;
  try {
    if (file.size > 10000000) throw new Error('Die Sicherung ist zu groß (maximal 10 MB).');
    const incoming = Z.validate(JSON.parse(await file.text()));
    if (!confirm(`${incoming.entries.length} Einträge importieren? Die aktuellen Einträge werden ersetzt. Exportiere vorher eine Sicherung, wenn du sie behalten möchtest.`)) return;
    localStorage.setItem(KEY, JSON.stringify(incoming)); data = incoming; storageBroken = false; resetForm(); render(); loadJournal(); notify('Sicherung mit Einträgen und Tagesnotizen importiert.');
  } catch (err) { notify('Import fehlgeschlagen; vorhandene Daten bleiben erhalten. ' + err.message); }
  finally { event.target.value = ''; }
};
window.addEventListener('storage', event => {
  if (event.key !== KEY) return;
  try { data = event.newValue ? Z.validate(JSON.parse(event.newValue)) : {version: 1, entries: []}; resetForm(); render(); loadJournal(); notify('Daten aus einem anderen Fenster aktualisiert.'); }
  catch { storageBroken = true; render(); notify('Speicheränderung ungültig. Bitte Sicherung prüfen.'); }
});
let journalDirty = false;
function journalForDay() { return data.journal?.[currentDay] || {notes:'', logs:'', answer:''}; }
function saveJournal() {
  const item = {notes:$('notes').value, logs:$('activity').value, answer:$('ai-answer').value};
  if (!journalDirty) return true;
  try {
    persist({...data, journal:{...data.journal, [currentDay]:item}}); journalDirty = false;
    $('journal-status').textContent = 'Tagesnotizen lokal gespeichert.'; return true;
  } catch (err) {
    $('journal-status').textContent = 'Nicht gespeichert: ' + err.message;
    notify('Notizen konnten nicht gespeichert werden. Bitte kopieren, bevor du die Seite verlässt.'); return false;
  }
}
function loadJournal() {
  const item = journalForDay();
  $('notes').value = item.notes; $('activity').value = item.logs; $('ai-answer').value = item.answer;
  $('prompt-panel').hidden = true; $('proposals').replaceChildren(); journalDirty = false;
  $('journal-status').textContent = 'Notizen werden beim Tippen lokal gespeichert.';
}
for (const id of ['notes', 'activity', 'ai-answer']) $(id).addEventListener('input', () => {
  journalDirty = true; saveJournal(); $('prompt-panel').hidden = true;
  if (id === 'ai-answer') $('proposals').replaceChildren();
});
$('save-notes').onclick = () => { journalDirty = true; saveJournal(); };
$('load-logs').onclick = async () => {
  if (!saveJournal()) return;
  if ($('activity').value && !confirm('Die bisherigen Git-Logs dieses Tages durch die aktuelle Abfrage ersetzen?')) return;
  const requestedDay = currentDay, oldLogs = $('activity').value;
  $('load-logs').disabled = true; $('journal-status').textContent = 'Lokale Git-Aktivitäten werden gelesen …';
  try {
    let result;
    if (desktop) result = await nativeCall('activity', {date:requestedDay});
    else {
      const response = await fetch(`/api/activity?date=${encodeURIComponent(requestedDay)}`, {signal:AbortSignal.timeout(70000)});
      if (!response.ok) throw new Error('Lokaler Log-Server nicht erreichbar. Öffne die Desktop-App oder starte python3 server.py.');
      result = await response.json();
    }
    if (result.date !== requestedDay || !Array.isArray(result.repositories)) throw new Error('Unerwartete Serverantwort.');
    if (currentDay !== requestedDay || $('activity').value !== oldLogs) { notify('Tag oder Logtext wurde inzwischen geändert. Bitte Logs erneut laden.'); return; }
    const text = [result.scope, ...result.repositories.flatMap(repo => [
      `\nREPOSITORY: ${repo.repository}`,
      'Eigene Commits:', repo.commits.error || repo.commits.text || '(keine gefunden)',
      repo.commits.truncated ? '(Ausgabe gekürzt)' : '',
      'Lokale HEAD-Aktivitäten:', repo.head_activity.error || repo.head_activity.text || '(keine gefunden)',
      repo.head_activity.truncated ? '(Ausgabe gekürzt)' : ''
    ])].join('\n');
    if (text.length > 150000) throw new Error('Zu viele Logs für einen Tag; bitte relevante Auszüge manuell einfügen.');
    $('activity').value = text; journalDirty = true; saveJournal(); $('prompt-panel').hidden = true;
    notify('Git-Logs geladen. Du kannst sie vor der Analyse ansehen und kürzen.');
  } catch (err) { notify('Logs nicht geladen: ' + err.message); }
  finally { $('load-logs').disabled = false; }
};
$('prepare-analysis').onclick = () => {
  if (!saveJournal()) return;
  const item = journalForDay();
  if (!item.notes.trim() && !item.logs.trim()) { notify('Schreibe zuerst eine Notiz oder lade die Git-Logs.'); return; }
  $('analysis-prompt').value = Z.analysisPrompt(currentDay, item, dayEntries()); $('prompt-panel').hidden = false;
  $('analysis-prompt').focus();
};
$('copy-analysis').onclick = async () => {
  // Refresh to include entries added after the preview was opened.
  $('analysis-prompt').value = Z.analysisPrompt(currentDay, journalForDay(), dayEntries());
  try { await copyText($('analysis-prompt').value); notify('Kopiert. Hier im Chat einfügen; die JSON-Antwort danach unter „ChatGPT-Antwort übernehmen“ einfügen.'); }
  catch { $('analysis-prompt').focus(); $('analysis-prompt').select(); notify('Bitte den markierten Analyseauftrag mit ⌘C oder Strg+C kopieren.'); }
};
$('parse-answer').onclick = () => {
  try {
    if (!saveJournal()) return;
    const day = currentDay, result = Z.proposals($('ai-answer').value, day), target = $('proposals');
    target.replaceChildren();
    if (result.questions.length) {
      const questions = node('div', undefined, 'review warning'); questions.append(node('strong','Noch offen'));
      const ul = node('ul'); result.questions.forEach(q => ul.append(node('li',q))); questions.append(ul); target.append(questions);
    }
    if (!result.entries.length) target.append(node('p','Keine neuen Tätigkeiten vorgeschlagen.'));
    result.entries.forEach((p, index) => {
      const card = node('div', undefined, 'proposal'); card.append(node('h3',`Vorschlag ${index + 1}`));
      const ticketLabel = node('label', 'Ticket'), ticket = node('input'); ticket.value = p.ticket; ticket.maxLength = 100; ticketLabel.append(ticket);
      const textLabel = node('label','Tätigkeit'), description = node('textarea'); description.value = p.description; description.maxLength = 4000; textLabel.append(description);
      const timeLabel = node('label','Dauer prüfen / ergänzen'), time = node('input'); time.value = p.time || ''; time.placeholder = 'Noch offen, z. B. 0:30'; timeLabel.append(time);
      const evidence = node('p',p.evidence,'muted');
      const add = node('button','Als prüfbaren Eintrag übernehmen','primary');
      // Stable source identity also prevents reimport after editing an accepted entry.
      const id = 'ai:' + day + ':' + JSON.stringify([p.ticket,p.description]);
      if (data.entries.some(e => e.id === id || e.date === day && e.ticket === p.ticket && e.description === p.description)) { add.disabled = true; add.textContent = 'Bereits erfasst'; }
      add.onclick = () => {
        try {
          if (currentDay !== day) throw new Error('Bitte die Antwort für den aktuellen Tag erneut prüfen.');
          const entry = {id,date:day,ticket:ticket.value.trim().toUpperCase(),description:description.value.trim(),minutes:Z.minutes(time.value),estimated:true};
          if (data.entries.some(e => e.id === id || e.date === day && e.ticket === entry.ticket && e.description === entry.description)) throw new Error('Diese Tätigkeit ist bereits erfasst.');
          if (dayEntries().reduce((sum,e) => sum + e.minutes, entry.minutes) > 1440) throw new Error('Die Tagessumme darf 24 Stunden nicht überschreiten.');
          persist(Z.validate({...data,entries:[...data.entries,entry]})); render(); add.disabled = true; add.textContent = 'Übernommen'; notify('Vorschlag übernommen. Die Zeit bleibt als Schätzung markiert, bis du sie beim Bearbeiten bestätigst.');
        } catch (err) { notify('Nicht übernommen: ' + err.message); }
      };
      card.append(ticketLabel,textLabel,timeLabel,evidence,add); target.append(card);
    });
  } catch (err) { $('proposals').replaceChildren(); notify('Antwort nicht übernommen: ' + err.message); }
};
window.addEventListener('beforeunload', event => { if (journalDirty || $('description').value || $('duration').value || $('ticket').value) { event.preventDefault(); event.returnValue = ''; } });
render(); loadJournal();
window.zeitbuchNativeCheckIn = function (payload) {
  const p = payload || {};
  const day = berlinDay();
  if (p.mode === 'entry') {
    const entry = {id: crypto.randomUUID(), date: day, ticket: String(p.ticket || '').trim().toUpperCase(), description: String(p.text || '').trim(), minutes: 30, estimated: true};
    const entries = [...data.entries, entry];
    if (entries.filter(e => e.date === day).reduce((sum, e) => sum + e.minutes, 0) > 1440) throw new Error('Die Tagessumme darf 24 Stunden nicht überschreiten.');
    persist(Z.validate({...data, entries}));
    if (currentDay === day) render();
    notify('30-Minuten-Eintrag aus der Statusleiste gespeichert.');
    return {ok: true, mode: 'entry'};
  }
  if (currentDay === day && journalDirty) saveJournal();
  const cur = data.journal?.[day] || {notes: '', logs: '', answer: ''};
  const nextNotes = Z.appendCheckIn(cur.notes, p.time || 'Jetzt', p.text, p.ticket);
  persist(Z.validate({...data, journal: {...data.journal, [day]: {...cur, notes: nextNotes}}}));
  if (currentDay === day) {
    $('notes').value = nextNotes; journalDirty = false;
    $('journal-status').textContent = 'Check-in aus der Statusleiste gespeichert.';
  }
  notify('30-Minuten-Notiz aus der Statusleiste gespeichert.');
  return {ok: true, mode: 'note'};
};
