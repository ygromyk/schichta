# Schichta

**Local-first time tracking for developers on macOS.** Schichta lives in your menu bar, asks
"what are you working on?" every few minutes, reads your own Git activity for the day, and turns
it all into a booking-ready day summary. If you want an AI to draft the summary, you choose the
model, and you can make it a fully local one.

> No account. No cloud. No telemetry. Your data stays in one JSON file on your Mac.

<p align="center">
  <img src="docs/screenshots/main-window.png" alt="Schichta main window: day entries with tickets and durations, estimated entries flagged, daily notes and the day-end booking draft" width="820">
</p>

<p align="center"><sub>All screenshots use invented demo data.</sub></p>

---

## Contents

- [Features](#features)
- [Privacy: what Schichta does and does not send](#privacy-what-schichta-does-and-does-not-send)
- [AI-ready: bring your own model](#ai-ready-bring-your-own-model)
- [Install](#install)
- [Build from source](#build-from-source)
- [Integrations: booking targets, hooks, Projektron BCS](#integrations)
- [Where your data lives](#where-your-data-lives)
- [Browser version (no install)](#browser-version-no-install)
- [Development](#development)
- [Releasing](#releasing)

## Features

- **Menu bar check-ins.** A check-in panel pops up at your chosen interval (or press `⌘K`).
  Save the answer as a timestamped note or directly as an estimated entry.
- **Day view.** Add entries with ticket, project and duration (`1:30`, `1,5` and `1.5` all work).
  Use quick +/− buttons and a progress bar against your daily target.
- **Estimates are flagged.** Anything guessed is marked *Estimated* and must be confirmed
  before you book the day, so nothing invented slips through.
- **Git activity.** Shows your own commits and HEAD reflog for the day from the repositories you
  pick. Each repository can carry a project name and a default ticket.
- **Day-end summary.** A booking draft (date, total, description, ticket, duration) that you can
  copy, save as TXT, or send to a booking target.
- **Morning and end-of-day reminders** for days that are not booked yet.
- **AI summary (optional).** Turns notes, Git activity and the day's Claude Code / Codex chats into
  editable proposals. See [AI-ready](#ai-ready-bring-your-own-model).
- **Booking targets.** Connect Clockify or any HTTP time-tracking API through a JSON file,
  with no code changes.
- **English and German UI**, plus light and dark mode.

<table>
  <tr>
    <td width="45%"><img src="docs/screenshots/check-in.png" alt="Check-in panel asking what you are working on, with recent tickets and quick durations"></td>
    <td><img src="docs/screenshots/settings-git.png" alt="Settings: tracked Git repositories with project names and default tickets"></td>
  </tr>
  <tr>
    <td align="center"><sub>Check-in panel from the menu bar</sub></td>
    <td align="center"><sub>Tracked repositories with project name and default ticket</sub></td>
  </tr>
</table>

## Privacy: what Schichta does and does not send

Schichta is built so that **nothing leaves your Mac unless you explicitly configure it and
click Send.**

| | |
| --- | --- |
| Analytics, telemetry, crash reporting | **None.** |
| Accounts, sign-in, license checks | **None.** |
| Update checks or other background network calls | **None.** |
| Third-party SDKs, fonts, trackers | **None.** The app is a single Swift file using only Apple frameworks. |
| Where entries are stored | One local JSON file, see [Where your data lives](#where-your-data-lives). |
| Where secrets are stored | macOS Keychain. Target files contain only the *name* of a secret. |

**Things Schichta reads locally** (only what you enable):

- Your own commits and HEAD reflog in the repositories **you** add, filtered by your Git author
  name. It never reads source files and never runs `git fetch`.
- For the AI summary only: Claude Code (`~/.claude/projects`) and Codex (`~/.codex/sessions`) chat
  logs from that day, **only for sessions inside your tracked repositories**. Prompts are
  shortened and run through a secret redactor (passwords, bearer tokens, `sk-…`/`ghp_…`/AWS keys,
  JWTs and long key-like strings are replaced). The redactor is a safety net, not a guarantee.

**The only ways data can leave your Mac**, all opt-in and all shown to you first:

1. **AI summary.** The full request is shown as a preview. Only after you click does it go via
   stdin to the command *you* configured. With Ollama it never leaves the machine at all.
2. **Booking targets.** HTTPS only (plain HTTP only for `localhost`) and redirects are refused.
   Every request is previewed first, with auth headers masked.
3. **Hooks.** A shell command or webhook URL that you set yourself in Settings › Integrations.

## AI-ready: bring your own model

Schichta **never calls an AI API itself** and ships no API keys. Instead it pipes a prompt to a
command-line tool of your choice and reads JSON back. You get proposals (always marked as
estimates; an unknown duration stays at 0 and must be filled in), a summary, and open questions.

Before anything is sent you see **exactly** the text that will go to the model, with obvious
secrets already removed. Nothing goes out until you click **Send**:

<p align="center">
  <img src="docs/screenshots/ai-preview.png" alt="AI summary preview showing the full request (notes and local commits) and the configured command, with Cancel and Send buttons" width="820">
</p>

Built-in presets (Settings › Integrations › AI summary), auto-detected if installed:

| Tool | Command | Where it runs | Safety |
| --- | --- | --- | --- |
| **Claude Code** | `claude -p --model sonnet --restricted --tools "" --strict-mcp-config --no-session-persistence` | Anthropic API via your Claude Code login | No tools, no MCP servers, no session saved |
| **Codex** | `codex exec --sandbox read-only --skip-git-repo-check -` | OpenAI via your Codex login | Read-only sandbox |
| **Ollama** | `ollama run --format json llama3.1` | **100 % local**, offline | Nothing leaves your Mac |

Tools are locked down because chat logs and commit messages are untrusted input: a prompt
injection in a commit message should not be able to run anything.

**Add your own model** by dropping a file into
`~/Library/Application Support/Schichta/ai-tools/<name>.json`:

```json
{ "name": "Ollama with Qwen", "command": "ollama run --format json qwen2.5" }
```

Any command that reads the prompt on stdin and prints JSON works, for example
[`llm`](https://llm.datasette.io), LM Studio's CLI, or a script of your own.

## Install

### Download (recommended)

1. Open the [**latest release**](../../releases/latest) and download `Schichta-<version>-macOS.zip`.
2. *(Optional, recommended)* Verify the download:

   ```bash
   shasum -a 256 -c SHA256SUMS.txt
   ```

   ```bash
   gh attestation verify Schichta-*-macOS.zip --repo <owner>/schichta
   ```

   The second command proves that the zip was built by this repository's GitHub Actions workflow
   from the tagged commit ([build provenance](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations)).
3. Unzip and move **Schichta.app** to `/Applications`.
4. Open it. **Schichta** appears in the menu bar.

**Requirements:** macOS 14 Sonoma or later, on Apple silicon or Intel (universal binary).

**"Schichta can't be opened because Apple cannot check it"?** Releases are notarized when the
maintainer has an Apple Developer ID configured. If a release is not notarized (ad-hoc signed),
open it once like this:

- macOS 15 or later: try to open it, then go to **System Settings › Privacy & Security** and click
  **Open Anyway**.
- macOS 14: right-click the app › **Open** › **Open**.

Or, after you have verified the checksum, remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/Schichta.app
```

## Build from source

You need the Xcode Command Line Tools (`xcode-select --install`). No Xcode project and no
dependencies are required.

```bash
./build-desktop.sh
```

```bash
open Schichta.app
```

Optional environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `VERSION` | `1.0` | `CFBundleShortVersionString` |
| `BUILD_NUMBER` | `1` | `CFBundleVersion` |
| `UNIVERSAL` | – | `1` builds arm64 + x86_64 |
| `SIGN_IDENTITY` | `-` (ad-hoc) | e.g. `Developer ID Application: Jane Doe (TEAMID)`; enables the hardened runtime |
| `APP` | `Schichta.app` | Output path |

## Integrations

### Booking targets (Clockify and any HTTP API)

Each `~/Library/Application Support/Schichta/targets/<name>.json` file describes one target.
Start from [`targets/clockify.example.json`](targets/clockify.example.json), which is copied into
that folder on first launch; `*.example.json` files are never loaded.

- `method`: `POST`, `PUT` or `PATCH`. `mode`: `perEntry` sends one request per entry, `perDay`
  sends one per day.
- `auth.type`: `none`, `bearer`, `basic` (+`username`) or `header` (+`header`). The file stores only
  the secret's **name**. Enter the value in Settings › Integrations, and it is kept in the Keychain.
- Placeholders: `{{date}}`, `{{dateFormatted}}`, `{{author}}`, `{{totalMinutes}}`,
  `{{totalHours}}`, `{{totalDuration}}`, `{{entries}}`, and per entry `{{entry.ticket}}`,
  `{{entry.description}}`, `{{entry.minutes}}`, `{{entry.hours}}`, `{{entry.duration}}`,
  `{{entry.estimated}}`, `{{entry.project}}`, `{{entry.start}}`/`{{entry.end}}` (UTC) and
  `{{entry.startTime}}`/`{{entry.endTime}}` (HH:mm). Entries are laid end to end from your work
  start time. `{{map.ticket}}` translates a ticket through the file's `map` table.
- A value that is *only* a placeholder keeps its type (number, boolean, list).

<p align="center">
  <img src="docs/screenshots/settings-integrations.png" alt="Settings: hook environment variables and a Clockify booking target whose API key is kept in the Keychain, with a preview button" width="560">
</p>

### Shell hook and webhook

In Settings › Integrations you can run a shell command or POST to a webhook when a day is booked.
The command receives the full day as JSON on stdin and in these environment variables:
`SCHICHTA_DATE`, `SCHICHTA_TOTAL_MINUTES`, `SCHICHTA_TOTAL_HHMM`, `SCHICHTA_JSON_FILE`
and `SCHICHTA_REPORT`. Hooks may run for up to 180 s.

### Projektron BCS

[`adapters/bcs`](adapters/bcs/README.md) is a standalone Node program that books a day into
Projektron BCS through browser automation. It keeps your password in the Keychain and rejects
estimates and already-booked days by default. Plug it in as a shell hook.

## Where your data lives

| What | Where |
| --- | --- |
| Entries, daily notes | `~/Library/Application Support/Schichta/schichta.json` |
| Last hook payload | `~/Library/Application Support/Schichta/last-export.json` |
| Booking targets, AI tools | `~/Library/Application Support/Schichta/targets/`, `…/ai-tools/` |
| Settings | macOS user defaults, domain `local.schichta` |
| Secrets | Keychain, service `Schichta.Targets` |

To back up, copy the folder. To uninstall, delete the app, that folder and
`~/Library/Preferences/local.schichta.plist`.

## Browser version (no install)

The repo also contains a minimal web version (`index.html`, `app.js`, `core.js`). Open
`index.html` directly in a browser to track time into the browser's `localStorage`. To load Git
activity, start the local read-only server:

```bash
SCHICHTA_REPOS=~/code/repo-a:~/code/repo-b python3 server.py
```

Then open <http://127.0.0.1:8765>. The server binds to `127.0.0.1` only and rejects cross-origin
and DNS-rebinding requests. `SCHICHTA_AUTHOR` overrides the author filter, which defaults to
`git config user.name`.

## Development

```bash
node --test core.test.cjs
```

```bash
python3 -m unittest server_test.py
```

```bash
Schichta.app/Contents/MacOS/Schichta --self-test
```

```bash
cd adapters/bcs && npm install && npm test
```

The desktop self-test reads the app's real user defaults, so run it on a profile with default
settings (CI does).

## Releasing

Releases are built by [`.github/workflows/release.yml`](.github/workflows/release.yml) when a
version tag is pushed:

```bash
git tag -a v1.2.0 -m "Schichta 1.2.0" && git push origin v1.2.0
```

The workflow runs all tests, builds a universal app with the tag's version, zips it with
`ditto`, writes `SHA256SUMS.txt`, creates a [build-provenance
attestation](https://docs.github.com/actions/security-for-github-actions/using-artifact-attestations)
and publishes a GitHub Release with generated notes. Tags with a suffix such as `v1.2.0-beta.1`
become pre-releases.

**Signing and notarization (optional).** Add these repository secrets and the workflow signs
with your Developer ID, notarizes and staples the app. Without them it ships ad-hoc signed builds.

| Secret | Content |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64 of your *Developer ID Application* certificate exported as `.p12` |
| `MACOS_CERTIFICATE_PASSWORD` | Password of that `.p12` |
| `MACOS_SIGN_IDENTITY` | e.g. `Developer ID Application: Jane Doe (TEAMID)` |
| `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` | For `notarytool`; the password is an [app-specific password](https://support.apple.com/102654) |
