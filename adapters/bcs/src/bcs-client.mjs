// Steuert die BCS-Weboberfläche (Tageserfassung). Selektoren und Ablauf stammen aus
// projektron-bcs-cli (src/bcsClient.ts, Commit 8fd277ec), erweitert um Prüfungen:
// Login-Fehler erkennen, angezeigtes Datum bestätigen, fehlende Task-Zeilen melden.
import puppeteer from 'puppeteer-core';
import { AdapterError, germanDate } from './plan.mjs';

const DATE_FIELD = 'daytimerecording,Selections,effortRecordingDate';
const DATE_DISPLAY = `span[id="${DATE_FIELD}_intervaldisplay"]`;
const TASK_ROWS = 'table[id="daytimerecording,Content,daytimerecordingTaskList_table"] > tbody > tr[data-listtaskgroupoid]';
const PRESENCE = (row, input) => `tr:nth-child(${row}) > td[name="attandenceDuration"] > span > input:nth-child(${input})`;

export class BcsClient {
  constructor(browser, page, config) {
    this.browser = browser;
    this.page = page;
    this.config = config;
  }

  static async open(config, { headless = true } = {}) {
    const browser = await puppeteer.launch({ executablePath: config.chromePath, headless }).catch((e) => {
      throw new AdapterError(`Chrome konnte nicht gestartet werden (${config.chromePath}): ${e.message}`);
    });
    const page = await browser.newPage();
    page.setDefaultTimeout(config.timeoutMs);
    await page.setViewport({ width: 1080, height: 1024 });
    return new BcsClient(browser, page, config);
  }

  async close() {
    await this.browser.close().catch(() => {});
  }

  async login(password) {
    const { url, username } = this.config;
    await this.page.goto(`${url}/bcs/login`).catch(() => {
      throw new AdapterError(`BCS nicht erreichbar: ${url}/bcs/login`);
    });
    await this.page.type('#label_user', username);
    await this.page.type('#label_pwd', password);
    await Promise.all([this.page.waitForNavigation(), this.page.click('#loginbutton')]);

    // BCS fragt nach Browser-Benachrichtigungen; nicht jede Instanz zeigt den Dialog.
    const later = await this.page.waitForSelector('input.notificationPermissionLater', { timeout: 3000 }).catch(() => null);
    if (later) await later.click();

    await this.page.goto(`${url}/bcs/mybcs/dayeffortrecording/`);
    if (await this.page.$('#label_pwd')) throw new AdapterError('BCS-Login fehlgeschlagen (Benutzername/Passwort prüfen).');
    await this.page.waitForSelector(DATE_DISPLAY);
  }

  /** Wechselt die Tageserfassung auf `date` (YYYY-MM-DD) und bestätigt das angezeigte Datum. */
  async openDay(date) {
    const [year, month, day] = date.split('-').map(Number);
    await this.page.waitForSelector(DATE_DISPLAY);
    await Promise.all([
      this.page.evaluate(([field, y, m, d]) => {
        // BCS-eigene Kalenderfunktion; Monat ist 0-basiert wie in JavaScript.
        PopupCalendar.reloadPageByCalendar(field, y, m, d, field, `popupCalendarLink.${field}`);
      }, [DATE_FIELD, year, month - 1, day]),
      this.page.waitForSelector('a.dayHighlighted').then((link) => link.click()),
      this.page.waitForNavigation(),
    ]);
    await this.page.waitForSelector(DATE_DISPLAY);

    // Schutz gegen Buchen auf den falschen Tag.
    const shown = await this.page.$eval(DATE_DISPLAY, (el) => el.textContent.trim());
    const variants = [germanDate(date), `${day}.${month}.${year}`];
    if (!variants.some((v) => shown.includes(v))) {
      throw new AdapterError(`BCS zeigt nicht den ${germanDate(date)} an (Anzeige: „${shown}“). Abbruch ohne Änderung.`);
    }
  }

  async fetchTasks() {
    const ticketField = this.config.ticketField;
    return this.page.$$eval(TASK_ROWS, (rows, ticketField) => rows.flatMap((row) => {
      const description = row.querySelector('td[name="description"] > textarea')?.value ?? '';
      const ticket = ticketField ? row.querySelector(`td[name="${ticketField}"] > input`)?.value ?? '' : '';
      const hours = parseInt(row.querySelector('td[name="effortExpense"] > span > input:nth-child(1)')?.value, 10) || 0;
      const minutes = parseInt(row.querySelector('td[name="effortExpense"] > span > input:nth-child(3)')?.value, 10) || 0;
      if (!description && !ticket && !hours && !minutes) return [];
      return [{ taskId: row.getAttribute('data-listtaskgroupoid').replace('_JTask', ''), ticket, description, minutes: hours * 60 + minutes }];
    }), ticketField);
  }

  async clearTasks() {
    await this.page.$$eval('a.cleanTimeRecordingRow_Link', (links) => links.forEach((a) => a.click()));
  }

  /** Füllt pro Task die letzte Zeile der Task-Gruppe und legt per „+“ eine neue leere Zeile an (wie die CLI). */
  async fillTasks(tasks) {
    const ticketField = this.config.ticketField;
    for (const task of tasks) {
      const found = await this.page.evaluate((task, ticketField) => {
        const rows = document.querySelectorAll(`tr[data-listtaskgroupoid="${task.taskId}_JTask"]`);
        const row = rows[rows.length - 1];
        if (!row) return false;
        const set = (el, value) => {
          el.value = value;
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        };
        const ticketInput = ticketField ? row.querySelector(`td[name="${ticketField}"] > input`) : null;
        const description = task.ticket && !ticketInput ? `${task.ticket} ${task.description}` : task.description;
        set(row.querySelector('td[name="effortExpense"] > span > input:nth-child(1)'), '0');
        set(row.querySelector('td[name="effortExpense"] > span > input:nth-child(3)'), String(task.minutes));
        set(row.querySelector('td[name="description"] > textarea'), description);
        if (ticketInput) set(ticketInput, task.ticket);
        return true;
      }, task, ticketField);
      if (!found) throw new AdapterError(`Task ${task.taskId} ist in deiner BCS-Tagesansicht nicht vorhanden (Mapping prüfen).`);
      const plus = await this.page.$(`tr[data-listtaskgroupoid="${task.taskId}_JTask"] > td[name="[plusminus]"] > button`);
      if (plus) await plus.click();
    }
  }

  /**
   * Anwesenheit = gebuchte Zeit + Pause; zweite Zeile = Pause (wie die CLI).
   * Werte direkt setzen statt tippen: Die CLI tippt hinter eine „0“, dann hängt das Ergebnis
   * davon ab, wo der Cursor landet (aus 195 kann 1950 werden).
   */
  async setPresence(totalMinutes, breakMinutes) {
    const values = [[1, totalMinutes + breakMinutes], [2, breakMinutes]];
    for (const [row, minutes] of values) {
      for (const [input, value] of [[1, '0'], [3, String(minutes)]]) {
        await this.page.$eval(PRESENCE(row, input), (el, value) => {
          el.value = value;
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
        }, value);
      }
    }
  }

  async save() {
    await this.page.waitForSelector('input.button[data-bcs-button-name="Apply"]').then((btn) => btn.click());
    await this.page.waitForSelector('div#TimeRecordingService_Success').catch(() => {
      throw new AdapterError('BCS hat das Speichern nicht bestätigt (keine Erfolgsmeldung).');
    });
  }

  async screenshot(path) {
    await this.page.screenshot({ path, fullPage: true }).catch(() => {});
  }
}
