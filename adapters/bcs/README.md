# schichta-bcs – Schichta → Projektron BCS

Standalone program that books a Schichta day into the BCS daily time recording.
Schichta knows nothing about BCS; it only calls the adapter as a shell hook and passes the
day's JSON on stdin.

BCS has no simple API for this, so the adapter drives the web UI with a headless Chrome
(puppeteer-core). Flow and selectors come from
[projektron-bcs-cli](https://github.com/pgebert/projektron-bcs-cli) (commit `8fd277ec`).

## Differences from the CLI (deliberately safer)

| CLI | Adapter |
| --- | --- |
| `add` always clears the day first | a day that already has entries is **refused**; replace only with `--replace` / `onExisting: "replace"` |
| unknown tickets land in a hard-coded task | no mapping means **no booking**, with an error explaining why |
| ticket number is not recorded | ticket goes into the `effortAttr1` field (configurable), otherwise in front of the description |
| presence time is typed (result depends on the cursor position) | values are set directly |
| no proof after saving | the day is reloaded and **verified** |
| password in `.env` | password in the **macOS Keychain** |
| estimates treated like everything else | entries marked as estimates are refused (`allowEstimated`) |

## Setup

```bash
cd adapters/bcs && npm install              # only puppeteer-core, uses your installed Chrome
mkdir -p ~/.config/schichta-bcs-adapter
cp config.example.json ~/.config/schichta-bcs-adapter/config.json   # adjust url, username, mapping
node bcs-adapter.mjs set-password           # asks for the BCS password (Keychain)
node bcs-adapter.mjs fetch --date 2026-10-26   # tests login and reading, changes nothing
```

**Finding task IDs:** in the BCS daily time recording every task row has an attribute
`data-listtaskgroupoid="1234567890123_JTask"` (right-click › Inspect). The digits before it
are the `taskId`. The `mapping` matches a regular expression against `ticket`, `description`
or `project`; the first matching rule wins.

## Connecting it to Schichta

Settings › Integrations & Hooks › Local Shell Command (use the absolute Node path, because apps
do not inherit your shell PATH):

```
/opt/homebrew/bin/node /path/to/schichta/adapters/bcs/bcs-adapter.mjs book --dry-run
```

Test with `--dry-run` first ("Test hook now"), then remove `--dry-run`. With
"Run hook automatically when a day is marked as booked", marking a day as booked books it
straight away. The output appears under "Last hook output".

## Commands

| Command | Effect |
| --- | --- |
| `plan` | check payload + mapping, without BCS |
| `book [--dry-run] [--replace]` | book |
| `fetch --date YYYY-MM-DD` | show existing entries |
| `set-password` | store the password in the Keychain |

Exit codes: `0` ok · `1` error · `2` deliberately refused (plan problems or day already has entries).
On browser errors a screenshot is saved as `$TMPDIR/schichta-bcs-fehler-*.png`.

## Tests

```bash
npm test
```

The end-to-end tests drive Chrome against a simulated BCS (`test/fake-bcs.mjs`).
They check the adapter's flow, **not** whether your BCS version has the same page structure.
For that, run `fetch` and `book --dry-run` against your real BCS.
