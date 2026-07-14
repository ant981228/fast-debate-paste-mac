# Fast Debate Paste ⇄ CardMirror — Native Integration Spec

**Audience:** the CardMirror agent (implements the CardMirror side) and
the Fast Debate Paste maintainer (implements the client side).
**Status:** proposed; v1 of the wire contract.
**Goal:** replace the fragile "synthesize Return + F2 + clipboard" step
with a direct, structured, acknowledged insertion call that produces the
**same observable result** the keystroke bridge produces today — just
without the keystroke-timing races that make it brittle.

The single most important section is **§4 (what CardMirror should do on
insert)** — it is defined to exactly reproduce the proven keystroke
behavior described in §3.

---

## 1. Scope: CardMirror is the only target

This integration assumes Fast Debate Paste, in this revised version,
**only needs to work with CardMirror.** That is an accepted, intentional
constraint, not a limitation to design around:

- The **"Select Target Window" picker may list only CardMirror windows.**
  It does not need to offer arbitrary apps. (Other apps as a paste target
  are out of scope for the native version.)
- The client **activates the user-selected CardMirror window** before
  inserting (a reliable operation), so "the focused CardMirror doc" and
  "the target" are the same thing at insert time. CardMirror therefore
  does **not** need to track window identity, doc uids, or a send-to-speech
  registration for this feature — it inserts into its focused doc.
- There is no multi-app routing, no `target` selector, and no
  end-of-document mode (see §4.3). The endpoint's whole job is to do, more
  robustly, what Return-then-F2 does at the current cursor.

---

## 2. Why a localhost HTTP server (not a URL scheme)

| Option | Verdict |
| --- | --- |
| `cardmirror://` URL scheme | Rejected. OS-routed and simple, but one-way (no ack), focus-stealing, and evidence cards can be hundreds of KB — past practical URL-length limits on macOS/Windows. |
| **Loopback HTTP server in the Electron main process** | **Chosen.** Arbitrary payload size, request/response ack, trivial to test with `curl`. |
| WebSocket | Overkill for v1; revisit if CardMirror ever needs to push events back to the paster. |

The server binds **`127.0.0.1` only** (never `0.0.0.0`) and is gated by a
per-launch token (see §6). It is off the network entirely.

---

## 3. The behavior to reproduce (what the keystroke bridge does today)

Fast Debate Paste already works against CardMirror by synthesizing
keystrokes. The native endpoint must produce the **same end result** — so
this is the ground truth for §4.

**Platform note.** The keystroke references below (`Cmd+C`, `Cmd+V`,
`Cmd-Z`, the `Ctrl+Shift+…` hotkeys) describe the current **macOS** client.
They are illustrative context, not part of the wire contract: on Windows
they map to `Ctrl+C` / `Ctrl+V` / `Ctrl+Z` (the `Ctrl+Shift+…` hotkeys are
already the same), and `F2` ("Paste Plain Text") is identical on every
platform. The contract itself — the discovery file, `/ping`, `/insert`, the
JSON payloads, and the insertion semantics in §4 — is fully OS-agnostic, so
a future Windows (or Linux) rewrite of the client talks to the same
CardMirror with no CardMirror-side changes. The only OS-specific work lives
*inside* the client and is outside this contract: how it grabs the source
selection (synthesizing the platform copy shortcut) and how it activates
CardMirror's window. In HTTP mode the client never synthesizes the paste at
all — CardMirror performs the insert.

For every action the app:
1. Copies from the source app and **processes the text to a plain
   string** (equation-omission rule applied; line breaks collapsed for the
   "no line breaks" variants). There is never any rich/HTML/RTF content —
   only plain text.
2. Activates the target CardMirror window.
3. Inserts the text using CardMirror's **F2 = "Paste Plain Text"** command
   (not Cmd+V), having put the plain string on the clipboard. F2 is the
   default `pasteKey`.

Insertion always happens **at the current cursor** in that doc. The
per-action difference is only **whether a new paragraph is started first**
(a synthesized Return before F2) and a leading space:

| Action (hotkey) | Return before paste? | Net result in CardMirror today |
| --- | --- | --- |
| Copy-Paste (`Ctrl+Shift+C`) | Yes | A **new body paragraph** is created at the cursor, holding the plain text. |
| Copy-Paste, no line breaks (`Ctrl+Shift+V`) | Yes | Same, but the text is already a single line (breaks collapsed to spaces). |
| Copy-Paste, no line breaks, no return (`Ctrl+Shift+B`) | No | The plain text (with a leading space) is appended **inline** into the current paragraph at the cursor. |
| Copy cite from Research Tracker (`Ctrl+Shift+Z`) | Yes | A **new paragraph** holding the citation string (plain text). |

So natively, "card"/"cite" ≈ *press Enter, then paste plain text at the
cursor*, and "inline" ≈ *paste plain text at the cursor with no new
paragraph*. Nothing more. The endpoint should not parse, re-style, or
restructure the text beyond this.

**On internal line breaks (important):** the plain Copy-Paste action does
*not* strip line breaks, so `text` for a `card` can contain newlines.
Multiple paragraphs are perfectly fine — the requirement is that **all of
them stay body paragraphs inside the same card.**

> **Resolved in CardMirror alpha.6.** Earlier F2 plain-paste got this
> wrong: it built `paragraph` nodes (not a legal child of `card`, whose
> content is `tag (card_body | undertag | …)*`) and let ProseMirror's
> schema-fitter resolve the mismatch — which bubbled the split to the card
> level and could synthesize a phantom tag from a pasted line (the "extra
> spacing that becomes tags" symptom). CardMirror's alpha.6 fix
> pre-converts those to `card_body` nodes before insertion, so F2 now
> produces exactly the §4.2 result. **The keystroke baseline therefore
> already matches §4.2 for the multi-line `card` case on alpha.6+** — it is
> no longer a bug the endpoint has to avoid mirroring. The native path will
> reuse the same `card_body` pre-fit primitive, so the two paths converge
> on byte-identical output.

---

## 4. `POST /insert` — required CardMirror behavior

This is the contract the CardMirror side must satisfy.

### 4.1 Request

`Content-Type: application/json`, header `X-FDP-Token: <token>` (see §6).

```json
{
  "text": "Smith 22 writes that …",
  "role": "card",
  "newParagraph": true,
  "omitted": false
}
```

| Field | Type | Meaning |
| --- | --- | --- |
| `text` | string, required | The final plain text to insert **verbatim**. Already processed by the client. CardMirror must NOT re-process, trim, re-wrap, or interpret it as markup. Treat exactly as F2 "Paste Plain Text" treats clipboard text. |
| `role` | `"card" \| "cite" \| "inline"` | Insertion intent (see §4.2). Unknown values degrade to `card`. |
| `newParagraph` | bool | Whether to start a new paragraph before inserting. `true` for `card`/`cite`, `false` for `inline`. Authoritative — `role` is a hint, `newParagraph` is the instruction. |
| `omitted` | bool | True when the equation-omission rule produced an `[EQUATION … OMITTED]` marker. Optional to honor (see §4.4). |

There is no `target` field: the insert always goes to the focused
CardMirror doc at its cursor (§1, §4.3).

### 4.2 Insertion semantics (the core requirement)

For each `role`, CardMirror must produce the result described in the §3
table, expressed natively against its ProseMirror schema:

- **`card` / `cite` (`newParagraph: true`)** — Insert `text` as **body
  content of the current card**, starting a new body paragraph at the
  cursor. This is the native equivalent of "press Return, then paste plain
  text": the inserted paragraph(s) are normal card body paragraphs (the
  same node a user gets by pressing Enter inside a card body and typing).
  The text goes in as **plain characters with no marks** — no underline,
  highlight, bold, cite mark, etc. If `text` contains line breaks,
  producing multiple paragraphs is fine — see "Line breaks become body
  paragraphs in the same card" below.

- **`inline` (`newParagraph: false`)** — Insert `text` as plain inline
  characters **at the current cursor**, without creating a new paragraph —
  i.e. it joins the paragraph the cursor is in. (The client may include a
  leading space in `text`; insert it as-is. CardMirror should not add or
  trim spacing itself.)

Hard requirements for all roles:
- **Plain text only.** Mirror F2 behavior: no marks/styles on the inserted
  run, and no source formatting exists to carry over.
- **Line breaks become body paragraphs in the same card.** Line breaks
  inside `text` (`\n`, `\r\n`, or `\r`) may split the text into **multiple
  paragraphs — that is fine and expected** — but every resulting paragraph
  must be a **card body paragraph that stays inside the same card** as the
  insertion point. A newline must **never** produce a `tag` (Heading 4), a
  heading (pocket / hat / block), a new card, or anything that breaks out
  of the current card. Newlines being misread as tags / structure was the
  stray-tags bug fixed in F2 as of alpha.6 (§3); the endpoint must not
  reintroduce it. Structural changes come
  **only** from the explicit `newParagraph` field (one new body paragraph
  to begin with); they are never inferred from the content of `text` beyond
  splitting it into further body paragraphs within that same card.
  Conversely, `text` with **no** line breaks yields **exactly one** body
  paragraph (or, for `inline`, a single inline run) — the "no line breaks"
  client actions (`Ctrl+Shift+V` / `Ctrl+Shift+B`) depend on this by
  stripping all breaks before sending (§8), so they never produce multiple
  paragraphs.
- **One transaction.** The whole insert is a single undoable step, so one
  Cmd-Z removes exactly what was inserted.
- **No re-processing.** Insert `text` as-is (aside from splitting on its
  newlines into body paragraphs per above). Do not parse authors/dates,
  detect URLs, run the omission rule, collapse runs of spaces, or otherwise
  alter whitespace.
- **Scroll the insertion into view** after applying.

**Implementation note (construct `card_body` nodes directly).** The
historical stray-tag bug came from building `paragraph` nodes and handing
them to ProseMirror's *contextual fitting*: `paragraph` isn't a legal child
of `card`, so the fitter's open-depth resolution bubbled the split up and
could promote a pasted line to a `tag`. The fix — landed in F2's
`applyPlainPasteFromText` as of CardMirror alpha.6 — is to **pre-convert
the pieces to `card_body` nodes before insertion**, leaving the fitter with
no mismatch to resolve. The endpoint must do the same: split `text` on
`/\r\n|\r|\n/`, build each piece as a `card_body` node — or the matching
body type for the cursor's container (`paragraph` when the cursor is at doc
level, outside any card / analytic_unit) — assemble a closed `Slice` of
those sibling body paragraphs, and `tr.replaceSelection(slice)`. Because the
node types and sibling level are chosen directly rather than inferred by
fitting, nothing can be elevated to a tag. Sharing this primitive with the
now-fixed F2 path is what makes the HTTP and keystroke outputs identical.
(`inline` builds inline content at the cursor instead; its `text` is
single-line by client guarantee, so no splitting is needed.)

### 4.3 Where to insert

Always at the **current cursor / selection of the focused CardMirror
doc** — the window the client just activated. That is exactly what the
keystroke path does.

- **No end-of-document mode.** The existing keystroke version has no
  "append at end of doc" behavior, so the endpoint must not add one. Insert
  where the cursor is.
- **"No target doc" = no live editable `EditorView`, not window focus.**
  `BrowserWindow.getFocusedWindow()` can be valid while the user is on a
  settings dialog, the home screen, a recovery sidebar, or any other
  non-editable surface — there is no document there to insert into. So the
  destination check is "is there a live `EditorView` we can dispatch a
  transaction onto?" If not, return `ok:false, error:"no-target-doc"`
  (§4.5). (In normal use the client has just activated a CardMirror doc
  window, so this should be rare.)

Because the client activates the target window first, CardMirror can treat
"the doc to insert into" as simply that focused window's live editor — no
window or doc identifier is sent or needed.

### 4.4 The `omitted` flag (optional)

When `omitted` is true, `text` is a placeholder like
`[EQUATION 3.14 OMITTED]` standing in for an equation/figure deliberately
left out of the card. CardMirror **may** render this run in a
de-emphasized / analytic style to match how omitted content should read,
but a v1 that simply inserts it as plain body text is fully acceptable.
Treat it as a presentation hint, not a structural instruction.

### 4.5 Response

Success (`200`):

```json
{ "ok": true, "inserted": true, "docTitle": "1AC — Heg.cmir" }
```

Handled failure (`200` with `ok:false`, or the matching non-2xx):

```json
{ "ok": false, "error": "no-target-doc" }
```

`error` values:
- `no-target-doc` — no live editable `EditorView` to dispatch onto (§4.3):
  the focused surface is a dialog, the home screen, a non-editable view,
  etc.
- `doc-readonly` — the destination doc exists but is in **read mode /
  locked** (the read-mode plugin would swallow the edit). Reject rather
  than insert: this matches what a user pressing F2 in read mode
  experiences (the keystroke is swallowed), so the result is consistent
  across both paths.
- `bad-request` (also `400`), `unauthorized` (also `403`), `internal`
  (also `500`).

The client treats any non-2xx, any `ok:false`, connection refused, or a
>1500 ms timeout as "integration unavailable" and **falls back to the
keystroke path**, so a paste is never lost. (Note: for `doc-readonly` the
keystroke fallback would be swallowed too, so the user simply sees nothing
inserted — the same outcome as pressing F2 in read mode. The client may
optionally surface a "target doc is in read mode" message instead of
silently retrying; that's a client-side choice.) CardMirror should fail
fast and clearly rather than hang.

---

## 5. `GET /ping` — health probe

Lets the client decide HTTP-vs-keystroke before sending. Requires the
token (§6).

Response `200`:

```json
{
  "ok": true,
  "app": "cardmirror",
  "appVersion": "0.1.0-alpha.5",
  "schema": 1,
  "hasActiveDoc": true
}
```

`hasActiveDoc` ← the focused window currently has an editable doc. (The
client may still attempt an insert when this is false and rely on the
`no-target-doc` response, but the hint lets it skip a doomed round-trip.)

---

## 6. Discovery handshake & security

CardMirror owns a **discovery file**. On server start it writes (atomic
tmp-then-rename), and on quit it deletes:

```
macOS:   ~/Library/Application Support/CardMirror/fast-paste-bridge.json
Windows: %APPDATA%/CardMirror/fast-paste-bridge.json
Linux:   ~/.config/CardMirror/fast-paste-bridge.json
```

i.e. `path.join(app.getPath('userData'), 'fast-paste-bridge.json')`:

```json
{
  "schema": 1,
  "port": 17699,
  "token": "f3a1c9…(32+ random hex chars)",
  "pid": 4123,
  "app": "cardmirror",
  "appVersion": "0.1.0-alpha.5"
}
```

- Fresh `token` each launch (`crypto.randomBytes(24).toString('hex')`).
- Prefer port `17699`; on `EADDRINUSE` bind an ephemeral port and record
  the real one. The client always reads the port from the file.
- Delete the file on `before-quit`. A stale file is tolerated: the client
  treats a failed `/ping` as "not running" and falls back to keystrokes.

Security:
- Bind `127.0.0.1` only.
- Require `X-FDP-Token` on **both** endpoints; constant-time compare;
  mismatch/absent → `403`.
- No CORS headers. Optionally reject requests carrying an `Origin`/
  `Referer` header, to blunt DNS-rebinding from a page in the user's
  browser.
- The token lives only in the user-readable discovery file under the
  user's profile — same trust boundary as their documents.

---

## 7. CardMirror-side implementation sketch

Maps onto the architecture already in `apps/desktop/src/main.ts`.

### 7.1 Main process — the server
1. New module, e.g. `apps/desktop/src/fast-paste-bridge.ts`, started from
   `app.whenReady()` after the first window exists. Use Node's built-in
   `http` (no new dependency).
2. `server.listen(17699, '127.0.0.1')`; on `EADDRINUSE` retry
   `listen(0, '127.0.0.1')` and read `server.address().port`.
3. Generate the token; write the discovery file (atomic) using the same
   tmp-then-rename discipline as the journal/quick-cards writers; delete
   it on `before-quit`.
4. Route `GET /ping` and `POST /insert`. For `/insert`, hand the payload to
   the **focused window's** renderer over IPC and await its ack.

### 7.2 Routing — just the focused window
Because the client activates the target CardMirror window before calling,
routing is simply `BrowserWindow.getFocusedWindow()` (fall back to
`mainWindow`). No speech-doc registry, no per-uid lookup.

- Send a new channel, e.g.
  `win.webContents.send('external:insert-text', { requestId, text, role, newParagraph, omitted })`.
- Correlate the ack: the renderer replies
  `ipcRenderer.send('external:insert-result', { requestId, ok, error?, docTitle? })`;
  main keeps a `Map<requestId, resolve>` with a timeout. (Avoid
  `executeJavaScript` under `contextIsolation`.)
- **Preload, not `executeJavaScript`.** Expose both sides through the
  existing contextIsolation preload (the one already vending the
  `window.cardmirror`-style channels): add the receive side
  (`external:insert-text`) and the send side (`external:insert-result`)
  there, so the renderer handler is wired over a real bridged channel
  rather than injected script.

### 7.3 Renderer — the actual insertion
Add a handler for `'external:insert-text'`. It must implement §4.2 exactly,
against the focused window's live `EditorView`. **Do not route through F2's
`applyPlainPasteFromText` / `buildPlainTextSlice` / contextual fitting**
(see the §4.2 implementation note) — build the nodes directly:

1. Resolve the destination: get the live `EditorView`. If there is none
   (settings dialog / home screen / non-editable surface), reply
   `{ ok:false, error:"no-target-doc" }`. If the doc is in read mode /
   locked, reply `{ ok:false, error:"doc-readonly" }`.
2. Build a transaction at the current selection:
   - `newParagraph` → split `text` on `/\r\n|\r|\n/`; build each piece as a
     `card_body` node (or the matching body type for the cursor's
     container — `paragraph` at doc level, outside any card / analytic_unit)
     with the text as a plain text node and **no marks**; assemble a closed
     `Slice` of those sibling body paragraphs and `tr.replaceSelection`.
   - `!newParagraph` → insert `text` as plain inline content **at the
     current selection**, no new block. (`text` is single-line by client
     guarantee, so no splitting is needed.)
   - `omitted` → optionally apply the de-emphasized/analytic style to the
     inserted run (§4.4); otherwise leave plain.
3. Dispatch as **one** transaction; `scrollIntoView()`.
4. Reply with `{ ok: true, docTitle }`.

### 7.4 Settings & lifecycle
- Gate the server behind a setting (default **on**), surfaced in
  Settings → General (e.g. "Allow Fast Debate Paste to insert evidence").
  Off → stop the server and delete the discovery file.
- One server per app instance; start lazily on the first window; do not
  start a second on `second-instance`.

---

## 8. Fast Debate Paste-side behavior (client)

Implemented in this repo once the endpoint exists; listed so both sides
agree. `text` is produced exactly as in the keystroke path today.

- The **target-window picker offers only CardMirror windows** (§1).
- `Config.integrationMode`: `"auto" | "http" | "keystroke"` (default
  `"auto"` = try HTTP, fall back to keystrokes).
- `CardMirrorClient` per action:
  1. Read the discovery file; if absent → keystroke path.
  2. `GET /ping` (1 s timeout); if not `ok` → keystroke path.
  3. **Activate the selected CardMirror window** (so it's focused).
  4. `POST /insert`; on any failure → keystroke path (a paste is never
     lost).
- Per-action payloads:

  | Action | `role` | `newParagraph` | `text` line breaks |
  | --- | --- | --- | --- |
  | Copy-Paste (`Ctrl+Shift+C`) | `card` | `true` | **kept** — may be multi-line |
  | Copy-Paste, no line breaks (`Ctrl+Shift+V`) | `card` | `true` | **stripped** — single line |
  | Copy-Paste, no line breaks, no return (`Ctrl+Shift+B`) | `inline` | `false` | **stripped** — single line |
  | Copy cite from Research Tracker (`Ctrl+Shift+Z`) | `cite` | `true` | kept |

  `omitted` = true whenever the equation-omission rule changed the text.
- **Line breaks are a client responsibility.** The two "no line breaks"
  actions (`Ctrl+Shift+V`, `Ctrl+Shift+B`) collapse/remove every line break
  **before** sending, exactly as they do today. Their `text` is therefore
  always a single line, so they can only ever produce **one** body
  paragraph (`V`) or a **single inline run** (`B`) — never multiple
  paragraphs. Only the plain Copy-Paste (`Ctrl+Shift+C`) sends
  newline-bearing `text`, and thus is the only action that can yield
  multiple body paragraphs (all in the same card, per §4.2). CardMirror
  applies the same uniform rule to all of them; the single-vs-multi
  paragraph difference comes entirely from what the client puts in `text`.
- In HTTP mode the client still activates the target window (as today) but
  does **not** synthesize Return, F2, or clipboard operations — those
  fragile steps are exactly what the endpoint replaces. It still returns
  focus to the source app afterward.
- **Keystroke fallback is now reliable for multi-line `Ctrl+Shift+C`** on
  CardMirror alpha.6+, since the F2 multi-line fix (see §3) means
  `F2-after-Return` no longer promotes pasted lines to tags. No client
  change is needed; this is just a quality improvement on the fallback path
  that previously was the most likely to show the artifact.

---

## 9. Test plan

With CardMirror running and a doc open and focused, cursor placed in a
card body:

```sh
DISCOVERY="$HOME/Library/Application Support/CardMirror/fast-paste-bridge.json"
PORT=$(python3 -c "import json,os;print(json.load(open(os.environ['DISCOVERY']))['port'])")
TOKEN=$(python3 -c "import json,os;print(json.load(open(os.environ['DISCOVERY']))['token'])")

curl -s "http://127.0.0.1:$PORT/ping" -H "X-FDP-Token: $TOKEN" | jq .

# card: new body paragraph at the cursor
curl -s "http://127.0.0.1:$PORT/insert" -H "X-FDP-Token: $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"text":"Test card text.","role":"card","newParagraph":true}' | jq .

# inline: appended at the cursor, no new paragraph
curl -s "http://127.0.0.1:$PORT/insert" -H "X-FDP-Token: $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"text":" inline addition","role":"inline","newParagraph":false}' | jq .

# multi-line card: multiple body paragraphs, all inside the SAME card
curl -s "http://127.0.0.1:$PORT/insert" -H "X-FDP-Token: $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"text":"First line of the card.\nSecond line.\nThird line.","role":"card","newParagraph":true}' | jq .
```

Acceptance:
- `/ping` reports `ok` and `hasActiveDoc`.
- `card` → a new body paragraph at the cursor with the **plain** text (no
  marks); one Cmd-Z removes it entirely.
- `inline` → text joins the current paragraph at the cursor; no new block.
- **Multi-line `card`** → multiple **body paragraphs** is fine, but **all
  of them stay inside the same card**; **no line becomes a tag / heading /
  new card**. One Cmd-Z removes the whole insert.
- Inserted text is byte-identical to `text` (no trimming/re-wrapping).
- Wrong/missing token → `403`.
- No editable doc focused → `ok:false, error:"no-target-doc"`.
- **Convergence check (alpha.6+):** running the same multi-line text
  through the *keystroke* path (`F2-after-Return`) should produce the same
  result — multiple body paragraphs, same card, no tag promotion. HTTP and
  keystroke outputs for this case should be byte-identical, which is exactly
  what §3 asks for.

---

## 10. Versioning & forward-compat

- Discovery file and payloads carry `schema: 1`. Bump on breaking changes;
  the client refuses unknown majors and falls back to keystrokes.
- Unknown JSON fields are ignored on both sides (additive evolution).
- Unknown `role` values degrade to `card`.
- **CardMirror `appVersion` ≥ `0.1.0-alpha.6`** is the meaningful baseline:
  alpha.6 carries the F2 multi-line `card_body` fix (§3) and is the target
  for the `/insert` endpoint itself. The discovery file's `appVersion`
  reflects the running build, so the client can gate on it — e.g. "use
  HTTP, and trust the keystroke fallback for multi-line paste, on alpha.6+."
  Older builds simply won't write a discovery file (no endpoint), so the
  client falls back to keystrokes anyway; the version gate mainly governs
  whether the multi-line keystroke fallback is known-good.
