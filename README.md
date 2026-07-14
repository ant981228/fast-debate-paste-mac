# Fast Debate Paste (Mac)

A native macOS menu-bar app that ports the *Fast Debate Paste* AutoHotkey
workflow to the Mac. It copies evidence from a source app (usually a
browser), runs the same equation-omission text processing, then switches
to a target window (your
[CardMirror](https://github.com/ant981228/cardmirror) speech doc) and
pastes — all from global hotkeys.

It lives in the menu bar only (no Dock icon). Copying from the source app
is synthesized keystrokes + the clipboard; delivery into CardMirror goes
through its native integration bridge when it's running, with a fixed
Return + F2 keystroke fallback (CardMirror's "Paste Plain Text") when
it isn't.

## Install

One line in Terminal — no Gatekeeper warnings (curl-downloaded apps carry
no quarantine flag), and updates re-run the same line without re-prompting
for Accessibility:

```sh
curl -fsSL https://raw.githubusercontent.com/ant981228/fast-debate-paste-mac/main/install.sh | bash
```

Apple Silicon only. The one thing macOS still requires is the one-time
**Accessibility** grant on first launch (System Settings → Privacy &
Security → Accessibility) — that permission is what allows synthesized
Cmd-C/Cmd-V, and no distribution method can skip it.

## Build from source

Requires the Swift toolchain (Xcode or Command Line Tools — `xcode-select
--install`).

```sh
./build.sh            # → dist/Fast Debate Paste.app
./build.sh install    # also copies it to /Applications
```

Then launch the app. On first run macOS will ask for **Accessibility**
permission (System Settings → Privacy & Security → Accessibility) — this
is required so the app can send Cmd-C / Cmd-V and activate windows on your
behalf. Grant it and relaunch. The menu-bar icon (clipboard) exposes every
action, the target picker, Help, and config controls.

## Default hotkeys

| Action | Hotkey |
| --- | --- |
| Select target window | `Ctrl+Shift+W` |
| Copy-Paste | `Ctrl+Shift+C` |
| Copy-Paste (no line breaks) | `Ctrl+Shift+V` |
| Copy-Paste (no line breaks, no return) | `Ctrl+Shift+B` |
| Help | `Ctrl+Shift+H` |

`Select target window` pops a list of open windows at your cursor; pick the
one to paste into. The choice persists until you change it or its app quits.

## How an action works

1. Copy from the frontmost app (`copyKey`, default `Cmd+C`).
2. Process the text:
   - a bare number / short `token number` becomes `[EQUATION … OMITTED]`
     (the debate convention for omitting equations & figures),
   - the "no line breaks" variants collapse line breaks into spaces.
3. Deliver into the target: natively via CardMirror's bridge when it's
   running, else by activating the target window and pressing Return +
   `F2` (CardMirror's "Paste Plain Text" — fixed, not configurable).
4. Return focus to the source app.

## Configuration

Everything is configurable via JSON at:

```
~/Library/Application Support/FastDebatePaste/config.json
```

Use **Edit Config…** in the menu to open it, then **Reload Config** to apply
(re-registers hotkeys live). Hotkey strings use `cmd`, `shift`, `opt`,
`ctrl` joined with `+`, plus a key — e.g. `cmd+shift+c`, `f10`, `ctrl+0`,
`shift+home`.

Notable keys to set for your setup:

- the four hotkey bindings, if `Ctrl+Shift+C/V/B/W` collide with anything
  on your machine.
- `integrationMode` — see below.

## Features intentionally omitted

The "Copy-Paste Current Header", "Copy URL and Paste", Zotero, and
Research Tracker actions from the Windows version are not included, and
the fallback paste key is fixed to `F2` — this port is deliberately
CardMirror-only and minimal.

## Native CardMirror integration

When CardMirror (alpha.6+) is running, the app delivers evidence through
CardMirror's **native HTTP bridge** instead of synthesizing a paste —
sidestepping the keystroke/clipboard timing fragility entirely and letting
CardMirror place the text natively (correct `card_body` paragraphs, no
stray tags). It still copies *from* the source app via keystrokes; only the
*insert into CardMirror* step goes native.

How it works (`CardMirrorClient.swift`): CardMirror writes a discovery file
at `~/Library/Application Support/CardMirror/fast-paste-bridge.json` with a
per-launch loopback port + token. Each action reads it, `GET /ping`s to
confirm the bridge is live, activates the target CardMirror window, then
`POST /insert`s `{text, role, newParagraph, omitted}`. The full contract is
in [`docs/cardmirror-integration-spec.md`](./docs/cardmirror-integration-spec.md).

**Never loses a paste.** Any failure (CardMirror not running, stale file,
wrong token, error, timeout) falls back to the keystroke path. Controlled
by `integrationMode` in the config:

- `auto` (default) — native bridge, silent keystroke fallback.
- `http` — bridge only, no fallback; surfaces an error if the native insert
  doesn't go through (use to verify the bridge actually works).
- `keystroke` — never use the bridge; always synthesize keystrokes.

The target-window picker is filtered to CardMirror windows by
`targetAppMatch` (default `"CardMirror"`; set empty to offer all windows).

## Project layout

```
Package.swift                 SwiftPM manifest
build.sh                      builds + packages the .app bundle
Sources/FastDebatePaste/
  main.swift                  app bootstrap (accessory / menu-bar only)
  CardMirrorClient.swift      native HTTP bridge client (discovery→ping→insert)
  AppDelegate.swift           status item, menu, hotkey wiring, help
  Config.swift                JSON config model + persistence
  AppState.swift              shared config/target state + alerts
  Keys.swift                  keycode map + hotkey-string parser
  Keyboard.swift              CGEvent keystroke synthesis
  HotKeyManager.swift         Carbon global-hotkey registration
  WindowTargeting.swift       AX-based window list + activation
  TextProcessor.swift         equation-omission + line-break rules
  PasteActions.swift          the copy → process → paste engine
legacy/                       the original Windows AutoHotkey version
```
