const assert = require('node:assert/strict');
const {test} = require('node:test');
const Z = require('./core.js');
test('decimal hours and HH:MM produce exact minute totals', () => {
  assert.equal(Z.minutes('1,5'), 90); assert.equal(Z.minutes('1.25'), 75);
  assert.equal(Z.minutes('01:05'), 65); assert.equal(Z.time(90 + 65), '02:35');
  for (const input of ['1:60', '-2', '0', '1:2', 'abc', '24:01', '1,5abc']) assert.throws(() => Z.minutes(input));
});
test('backup validation rejects bad dates and invalid or duplicate records', () => {
  const e = {id:'a',date:'2026-10-26',ticket:'PROJ-2800',description:'Replay prüfen',minutes:90,estimated:false};
  assert.deepEqual(Z.validate({version:1,entries:[e]}).entries, [e]);
  assert.throws(() => Z.validate({version:1,entries:[e,e]}));
  assert.throws(() => Z.validate({version:1,entries:[{...e,date:'2026-02-30'}]}));
  assert.throws(() => Z.validate({version:1,entries:[{...e,minutes:-1}]}));
  assert.throws(() => Z.validate({version:1,entries:[{...e,description:''}]}));
});
test('day report preserves ticket and description, marks estimates, uses CLI time format', () => {
  const report = Z.report('2026-10-26', [{ticket:'PROJ-2800',description:'Replay prüfen',minutes:90,estimated:true},{ticket:'',description:'Abstimmung',minutes:15,estimated:false}]);
  assert.match(report,/Datum: 26\.10\.2026/); assert.match(report,/Gesamtzeit: 01:45/);
  assert.match(report,/Ticket: PROJ-2800/); assert.match(report,/Dauer: 01:30 \(Schätzung/);
  assert.match(report,/Ticket: Ohne Ticket/);
});
test('old backups migrate and journals survive a save/load cycle', () => {
  assert.deepEqual(Z.validate({version:1, entries:[]}).journal, {});
  const source = {version:1, entries:[], journal:{'2026-10-26':{notes:'30 Minuten Abstimmung',logs:'commit abc',answer:''}}};
  assert.deepEqual(Z.validate(JSON.parse(JSON.stringify(source))), source);
  assert.throws(() => Z.validate({...source,journal:{'2026-02-30':{notes:'x'}}}));
});
test('AI proposals accept unknown times but reject wrong days and invalid durations', () => {
  const response = {date:'2026-10-26',entries:[{ticket:'proj-2800',description:'Analyse',time:null,evidence:'Tagesnotiz'}],questions:['Wie lange?']};
  const parsed = Z.proposals('```json\n' + JSON.stringify(response) + '\n```', response.date);
  assert.equal(parsed.entries[0].ticket,'PROJ-2800'); assert.equal(parsed.entries[0].time,null);
  assert.throws(() => Z.proposals(JSON.stringify(response),'2026-10-27'));
  for (const time of ['25:00','01:90',-30,'1:30','null']) {
    assert.throws(() => Z.proposals(JSON.stringify({...response,entries:[{...response.entries[0],time}]}),response.date));
  }
});
test('analysis context includes notes, logs and existing entries without inferring duration', () => {
  const prompt = Z.analysisPrompt('2026-10-26',{notes:'Meeting 30 Minuten',logs:'abc123'},[{ticket:'X-1',description:'Schon erfasst',minutes:30}]);
  assert.match(prompt,/Meeting 30 Minuten/); assert.match(prompt,/abc123/); assert.match(prompt,/Schon erfasst/);
  assert.match(prompt,/Keine Arbeitsdauer aus Commit-Abständen/); assert.match(prompt,/NICHT DUPLIZIEREN/);
});
test('appendCheckIn formats 30-minute status check-ins with optional ticket and rejects empty text', () => {
  const first = Z.appendCheckIn('', '12:30', 'Replay getestet');
  assert.equal(first, '- 12:30 (30 Min.): Replay getestet');
  const second = Z.appendCheckIn(first, '13:00', 'Abstimmung mit dem Team', 'proj-2800');
  assert.equal(second, '- 12:30 (30 Min.): Replay getestet\n- 13:00 (30 Min.): [PROJ-2800] Abstimmung mit dem Team');
  assert.throws(() => Z.appendCheckIn('', '12:30', '   '), /Bitte eine Tätigkeit oder Notiz eingeben\./);
});
