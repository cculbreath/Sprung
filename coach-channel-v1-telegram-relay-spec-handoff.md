# coach-relay — Parallel-Execution Handoff (V1-A)

*Cold-start handoff. A fresh session with no memory of the design conversation can execute
this end-to-end. Produced by `/tackleplan` from `coach-channel-v1-telegram-relay-spec.md`.
Run it with `/tackle` (execution line at the bottom).*

---

## 1. Goal

Build **coach-relay**: a small, always-on Telegram relay service that runs on a home Debian
box and acts as the "mailroom" for the Sprung Coach. It owns a Telegram bot (long-poll),
durably queues inbound user messages for a Mac to drain, fires **scheduled** outbound
messages on time even while the Mac is asleep, and fires a **dead-man** message when the
Mac's heartbeat goes stale. It is a *dumb relay*: it never composes content and never calls
an LLM — the Mac (out of scope here) is the brain.

**Done looks like:** a standalone git repo at `/Users/cculbreath/devlocal/codebase/coach-relay`
containing a pure-stdlib Python 3 package (`coach_relay/`) that compiles, passes its unit
tests, ships a systemd unit + `config.example.json` + `PROTOCOL.md` + `README.md`, and can
be smoke-tested against a real BotFather bot over Tailscale. **Zero pip dependencies.**

---

## 2. Authoritative sources

- **`plans/coach-channel-v1-telegram-relay-spec.md`** — the spec (topology, storage schema,
  API surface, decisions D1–D3). Its *what/why* is **settled — do not relitigate**:
  standalone repo (D3), Tailscale-bound API (D2), standalone systemd service / pure stdlib
  (D1). §3 is the relay contract; §5 the scheduled-delivery + dead-man mechanics; §6 the
  telemetry the Mac later consumes.
- This handoff §7 pins the **exact interface contracts** so parallel agents never guess a
  signature. Where handoff and spec differ in detail, **the handoff wins** (it is the later,
  execution-precise document).

---

## 3. Hard constraints

- **Pure Python stdlib only. No pip, no venv, no third-party packages.** Do NOT reach for
  `requests`, `python-telegram-bot`, `aiohttp`, `httpx`, `flask`, etc. Use `urllib.request`,
  `http.server`, `sqlite3`, `threading`, `json`, `argparse`, `signal`, `dataclasses`,
  `time`. Target **Python 3.9+** (Debian-stable floor).
- **No coach logic, no LLM calls, no Anthropic key** anywhere in this repo. The relay
  forwards and schedules; it does not think. Content it sends was authored elsewhere (or is a
  pre-configured canned/dead-man string).
- **Never build in parallel.** Only the *main session* runs the compile/test, **once per
  wave**, after that wave's agents finish. Subagents write files; they do not run
  `compileall`/`unittest`.
- **Disjoint file ownership per wave.** Within a parallel wave, no two agents touch the same
  file. New files parallelize cleanly; the one integration file (`__main__.py`) is a **serial
  zone** (§5).
- **Secrets never committed.** Commit `config.example.json` with placeholders only. Real
  `config.json` is gitignored. Same for `*.db`.
- **API auth + binding.** Every endpoint except `GET /health` requires
  `Authorization: Bearer <macApiToken>`. The server binds to `config.bind` (the Tailscale
  interface IP), never hardcoded `0.0.0.0`.
- **Per-wave cadence:** wave agents finish → main session runs the wave's compile/test gate
  (§8) → fixes → **one commit** in the coach-relay repo. Commit messages concise, imperative;
  **no AI attribution**, no `Claude-Session` trailer.
- **Clean breaks** (greenfield, so mostly N/A): no dead scaffolding, no "TODO later," no
  commented-out alternatives.
- **Parked scope is off-limits (§9).** Agents do not create Swift files, LLM code, HA
  integration, or CloudKit anything.

---

## 4. Waves

### Wave 0 — Bootstrap (SERIAL · main session · `sonnet`)
Main session creates the repo and the shared scaffolding that defines the config contract.
Not a fan-out.
| Step | Creates | Task |
|---|---|---|
| 0 | `/Users/cculbreath/devlocal/codebase/coach-relay/` | `mkdir` + `git init`; add `.gitignore` (`config.json`, `*.db`, `__pycache__/`, `.venv/`), `coach_relay/__init__.py` (empty or version string), `config.example.json` (§7 schema, placeholders), `LICENSE` (match Sprung's license). Commit. |

### Wave 1 — Foundation modules (PARALLEL · 2 agents)
Depend only on the pinned contracts in §7. Disjoint files.
| Agent | Owns | Task | Model |
|---|---|---|---|
| A | `coach_relay/config.py`, `coach_relay/store.py` | `Config` dataclass + `load()` (§7.1); `Store` class wrapping a lock-guarded `sqlite3` connection with the 4-table schema + all methods (§7.2). Thread-safe: `check_same_thread=False` + a `threading.Lock` around every write. | `sonnet` — schema + methods fully specified in §7. |
| B | `coach_relay/telegram.py` | `Telegram` pure client (§7.3): `get_updates`, `send_message` (builds inline keyboard from `suggested_replies`), `answer_callback`. `urllib` only; catch network errors, return `[]`/`None` after logging — never crash the caller. | `sonnet` — well-defined HTTP client against a known API. |

### Wave 2 — Consumers (PARALLEL · 3 agents)
All import config + store + telegram from Waves 0–1. Disjoint files.
| Agent | Owns | Task | Model |
|---|---|---|---|
| C | `coach_relay/poller.py` | `run_poller(config, store, telegram, stop_event)` (§7.4): long-poll loop; chatId allowlist (drop others silently); write inbound (messages + callback taps); `answer_callback` on taps; one-per-outage **canned ack** when the Mac is stale; persist offset via `store`. | `sonnet` — loop + allowlist + ack rule spelled out in §7.4. |
| D | `coach_relay/api.py` | `make_server(config, store, telegram) -> ThreadingHTTPServer` (§7.5): Bearer auth; routes `POST /heartbeat`, `GET /inbound`, `POST /outbound` (immediate send vs enqueue by presence of `deliverAt`), `POST /revoke`, unauth `GET /health` (returns `protocolVersion`). | `sonnet` — routes + payloads fixed in §7.5/PROTOCOL. |
| E | `coach_relay/ticks.py` | `run_ticks(config, store, telegram, stop_event)` (§7.6): 60s interruptible tick; fire due outbound (expire past `validUntil`); dead-man fire once per outage. | `sonnet` — state transitions fully specified; single file. |

### Wave 3 — Wiring / entrypoint (SERIAL · 1 agent · `opus`)
| Agent | Owns | Task | Model |
|---|---|---|---|
| F | `coach_relay/__main__.py` | Argparse `--config` (default `/etc/coach-relay/config.json`); load config; open store; construct telegram; `threading.Event` stop; start poller + ticks daemon threads; `make_server` on the main thread; `SIGTERM`/`SIGINT` → `stop_event.set()` + `server.shutdown()`; clean exit. `python -m coach_relay` runs it. | `opus` — concurrency wiring + signal handling + integration point; a wrong guess here is expensive. |

### Wave 4 — Docs / ops / tests (PARALLEL · 4 agents)
Depend on the finished code (for accuracy). Disjoint files.
| Agent | Owns | Task | Model |
|---|---|---|---|
| G | `tests/test_logic.py` | Pure-logic `unittest` against a temp-file `Store` (no network): inbound cursor round-trip; `deliver_at`/`validUntil` due+expiry logic; `revoke` only when `queued`; heartbeat update clears `deadman_fired_at`+`ack_sent_at`; offset kv. | `sonnet` — deterministic store tests. |
| H | `README.md` | BotFather bot creation, finding your chat id, Tailscale note, install (`git clone`, config, systemd), run, smoke test, update (`git pull && systemctl restart`). | `sonnet` — docs from spec §10. |
| I | `PROTOCOL.md` | Single source of truth for the Mac↔relay wire contract: every endpoint, request/response JSON, auth, `protocolVersion`. The Swift adapter (other repo) will code against this. | `sonnet` — transcribe §7.5. |
| J | `coach-relay.service` | systemd unit template: `ExecStart=/usr/bin/python3 -m coach_relay --config /etc/coach-relay/config.json`, `Restart=always`, `WorkingDirectory`, a dedicated user, `After=network-online.target`. | `sonnet` — standard unit. |

---

## 5. Serial-zone file map

There is no app-shell here (standalone service), so the serial zone is small:
- **`coach_relay/__main__.py`** — the integration point that imports every module and wires
  the threads + server + signal handling. Built alone in **Wave 3**, after all modules exist;
  never fanned out.
- **Repo bootstrap** (`git init`, dir creation, `.gitignore`, `config.example.json`) —
  **Wave 0**, main session only. Everything downstream imports the config contract it fixes.

Every other file is a disjoint new file owned by exactly one agent in its wave.

---

## 6. Build / test gate (per wave, main session only)

This repo has **no** `agents.md`; commands are self-contained here:
- **Compile gate (every wave):** `cd /Users/cculbreath/devlocal/codebase/coach-relay && python3 -m compileall coach_relay`
- **Test gate (Wave 4+):** `python3 -m unittest discover -s tests -v`
- **No pip install step exists** — if any agent introduced an import outside the stdlib, the
  compile/test gate is where you catch and remove it.
- Commit after each green gate. No AI attribution.

**User-driven QA gate (after Wave 4 — cannot be automated here):**
1. Create a bot via **@BotFather**; copy the token. Find your numeric **chat id**
   (e.g. message `@userinfobot`).
2. Install **Tailscale** on the Debian box + your Mac; note the box's Tailscale IP.
3. `cp config.example.json config.json`; fill `botToken`, `allowedChatIds`, `macApiToken`
   (a long random string), `bind` (the Tailscale IP).
4. Run `python3 -m coach_relay --config ./config.json`.
5. Text the bot → confirm it appears via `GET /inbound?since=0` (with the Bearer token).
6. `POST /outbound` an immediate message → confirm it arrives in Telegram.
7. `POST /outbound` with a near-future `deliverAt` + tight `validUntil` → confirm on-time
   fire; and one already past `validUntil` → confirm it's suppressed (`expired`).
8. Stop sending heartbeats past `deadmanThresholdHours` (temporarily lower it) → confirm the
   dead-man message fires once.

---

## 7. Interface contracts (pin these EXACTLY — parallel agents code against them)

### 7.1 `config.py` / `config.example.json`
`@dataclass Config` with, and `load(path) -> Config` reading, these JSON keys (camelCase on
the wire; snake or same in Python — expose as attributes):
| Key | Type | Notes |
|---|---|---|
| `botToken` | str | required, non-empty |
| `allowedChatIds` | list[int] | required, non-empty |
| `macApiToken` | str | required, non-empty (Bearer for the Mac API) |
| `bind` | str | required (Tailscale interface IP) |
| `port` | int | default 8765 |
| `dbPath` | str | default `/var/lib/coach-relay/coach_relay.db` |
| `deadmanThresholdHours` | float | default 36 |
| `ackThresholdMinutes` | float | default 20 |
| `cannedAck` | str | pre-authored "Mac asleep, reply later" text |
| `deadmanMessage` | str | pre-authored "coach offline?" text |
`load()` raises a clear error on any missing/empty required key (no silent defaults for
required keys).

### 7.2 `store.py` — `class Store(db_path)`
Thread-safe (`check_same_thread=False` + a `threading.Lock` around writes). Epoch-seconds
(`time.time()`) timestamps. Creates on init:
```
inbound(id PK AUTOINCREMENT, chat_id INT, text TEXT, kind TEXT['message'|'callback'], payload TEXT, received_at REAL, drained INT DEFAULT 0)
outbound(id PK AUTOINCREMENT, chat_id INT, text TEXT, suggested_replies TEXT, deliver_at REAL, valid_until REAL, kind TEXT, turn_id TEXT, state TEXT['queued'|'sent'|'revoked'|'expired'], tg_message_id INT, created_at REAL)
mac_status(id PK CHECK(id=1), last_heartbeat_at REAL, presence TEXT, pause_reason TEXT, app_version TEXT, deadman_fired_at REAL, ack_sent_at REAL)
kv(key TEXT PK, value TEXT)
```
Methods:
`add_inbound(chat_id, text, kind, payload) -> int` · `inbound_since(cursor_id) -> list[dict]`
(id > cursor, ordered) · `enqueue_outbound(chat_id, text, suggested_replies, deliver_at,
valid_until, kind, turn_id) -> int` · `record_sent(chat_id, text, tg_message_id, kind,
turn_id) -> int` (immediate sends, state='sent') · `due_outbound(now) -> list[dict]`
(state='queued' AND deliver_at<=now) · `mark_sent(id, tg_message_id)` · `mark_expired(id)` ·
`revoke(id) -> bool` (True only if it was still 'queued') · `get_mac_status() -> dict` ·
`update_heartbeat(presence, pause_reason, app_version)` (sets last_heartbeat_at=now, clears
deadman_fired_at + ack_sent_at) · `set_deadman_fired(now)` · `set_ack_sent(now)` ·
`get_offset() -> int` · `set_offset(v)`.

### 7.3 `telegram.py` — `class Telegram(token)`
`get_updates(offset, timeout=50) -> list[dict]` (GET getUpdates, socket timeout `timeout+10`,
return `result` list, on any exception log + return `[]`) · `send_message(chat_id, text,
suggested_replies=None) -> int|None` (POST sendMessage, **no** parse_mode/plain text; if
`suggested_replies`, `reply_markup={"inline_keyboard":[[{"text":r,"callback_data":r[:60]}] for
r in suggested_replies]}`; return `result.message_id`, or `None` on failure) ·
`answer_callback(callback_query_id)` (POST answerCallbackQuery to clear the phone spinner).

### 7.4 `poller.py` — `run_poller(config, store, telegram, stop_event)`
Loop until `stop_event.is_set()`: `updates = telegram.get_updates(store.get_offset(), 50)`;
for each, advance offset to `update_id+1`; **message** from an allowed chat → `add_inbound(...,
'message', None)` then canned-ack check; **callback_query** from an allowed chat →
`add_inbound(..., 'callback', json.dumps(...))` + `answer_callback`; non-allowlisted chats
dropped silently. Persist offset via `store.set_offset` after each batch.
**Canned-ack rule:** on a new inbound message, if `mac_status.last_heartbeat_at` exists and
`now - last > ackThresholdMinutes*60` and `ack_sent_at is None` → `send_message(chat_id,
config.cannedAck)` and `set_ack_sent(now)`. (One ack per outage; cleared by the next
heartbeat.)

### 7.5 `api.py` — `make_server(config, store, telegram) -> ThreadingHTTPServer`
Bound to `(config.bind, config.port)`. JSON in/out. Bearer `macApiToken` on all but `/health`
(else 401).
| Route | Body → Response |
|---|---|
| `GET /health` | *(no auth)* → `200 {"ok":true,"protocolVersion":"1"}` |
| `POST /heartbeat` | `{presence, pauseReason?, appVersion}` → `update_heartbeat(...)` → `200 {"dueCount": <int>}` |
| `GET /inbound?since=<id>` | → `200 {"messages":[<inbound rows id>since>]}` |
| `POST /outbound` | `{chatId, text, suggestedReplies?, deliverAt?, validUntil?, kind, turnId}` → if `deliverAt` absent: `send_message` now + `record_sent` → `200 {"id":..,"tgMessageId":..}`; else `enqueue_outbound` → `200 {"id":..,"state":"queued"}` |
| `POST /revoke` | `{outboundId}` → `{"revoked": <bool>}` |

### 7.6 `ticks.py` — `run_ticks(config, store, telegram, stop_event)`
Loop until stopped, `stop_event.wait(60)` between ticks. Each tick: **(a)** for
`store.due_outbound(now)`: if `valid_until` and `now > valid_until` → `mark_expired(id)`; else
`send_message(...)` (with its `suggested_replies`) → `mark_sent(id, message_id)`. **(b)**
dead-man: if `last_heartbeat_at` and `now - last > deadmanThresholdHours*3600` and
`deadman_fired_at is None` → send `deadmanMessage` to every `allowedChatIds` → `set_deadman_fired(now)`.

---

## 8. Parked / out-of-scope (do NOT touch — carry forward verbatim)

- **V1-B — the Swift `CoachChannelAdapter` + `TelegramRelayChannel`.** Lives in the *Sprung*
  repo, not here. This handoff builds only the relay.
- **V1-D — the coach brain / any LLM call / Anthropic anything.** The relay is a dumb
  mailroom; it contains no coaching logic.
- **Home Assistant presence detection.** A later enhancement (read HA's REST API from the
  relay); not v1.
- **CloudKit iOS companion.** A separate future channel adapter.
- **Third-party dependencies.** Forbidden — pure stdlib (§3).

---

## 9. Execution line

From a fresh session in the Sprung working directory, run:

```
/tackle plans/coach-channel-v1-telegram-relay-spec-handoff.md
```

`/tackle` reads this document, fans out each wave's agents (disjoint files), and serializes
Wave 0 bootstrap + Wave 3 wiring + every compile/test gate in the main session. After Wave 4,
run the user-driven QA gate (§6) with a real BotFather bot over Tailscale.
