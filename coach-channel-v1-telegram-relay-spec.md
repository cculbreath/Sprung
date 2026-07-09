# Sprung Coach Channel v1 — Telegram + Debian Relay

*Resolves the channel fork in `coach-agent-spec.md` §14.1. v1 = a Telegram bot fronted by
an always-on relay service on the home Debian/Home-Assistant box. The CloudKit iOS companion
(`coach-companion-app-spec.md`) is deferred until the $99 Apple Developer fee is paid and
becomes a second `CoachChannelAdapter` — this document is the v1 adapter + its relay.
Grounded against `coach-agent-spec-review-2026-07-08.md` Addenda 2–6.*

---

## 1. Why a relay at all (the one-paragraph justification)

Telegram is a message **relay**, not always-on **compute**: a bot can't schedule a future
send (Bot API `sendMessage` is immediate-only) and can't run our code on the user's phone,
and a sleeping Mac can't fire a morning nudge or announce its own death. The Debian box —
already an always-on managed server in the house — supplies the missing compute: it owns the
bot, holds the schedule, fires scheduled sends on time, and watches the Mac's heartbeat so a
silent coach gets surfaced. The Mac stays the brain; the relay is a dumb mailroom.

---

## 2. Topology

```
┌──────────────────────┐   Tailscale/LAN HTTP   ┌───────────────────────┐   Telegram Bot API   ┌──────────┐
│  MacBook (the brain) │◄──────────────────────►│  Debian box (relay)   │◄────long-poll───────►│ Telegram │──► user's
│  coach loop, memory, │  heartbeat / drain-in  │  owns bot, SQLite      │     sendMessage      │  servers │    phone
│  arbiter, decay,     │  push-out / revoke     │  queue+schedule+hb,    │                      └──────────┘
│  TelegramRelayChannel│                        │  fires scheduled+dead- │
│  : CoachChannelAdapter                        │  man autonomously      │
└──────────────────────┘                        └───────────────────────┘
```

- **Mac** composes every message (full context) and decides timing; connects **out** to the
  relay when awake+online (from anywhere, via Tailscale) to: send its heartbeat, drain
  inbound, push outbound (immediate or future-dated), revoke.
- **Relay** never composes content. It owns the bot (long-poll — no public webhook, no
  inbound exposure), durably queues inbound for the Mac, fires due scheduled sends on a
  minute cron, and fires the dead-man message when the heartbeat goes stale.
- **Telegram** carries push to the phone for free (its own app's notifications).

Single-writer discipline carries over: the Mac authors coach→user content; the relay authors
only the dead-man/canned-ack messages it was pre-told to send. No shared mutable state.

---

## 3. Component A — the relay service (Debian box)

**Packaging:** DECISION D1 (§8) — standalone Python systemd service (default) vs a Home
Assistant AppDaemon app (unlocks HA presence detection for the arbiter). Either way: full
Python, SQLite, no public endpoint.

**Storage (SQLite):**
| Table | Rows |
|---|---|
| `inbound` | user→coach messages + button taps: `id`, `chatId`, `text`, `kind`(`message`/`callback`), `payload`(JSON), `receivedAt`, `drained`(bool) |
| `outbound` | coach→user queued/scheduled: `id`, `chatId`, `text`, `suggestedReplies`(JSON), `deliverAt`(nullable), `validUntil`(nullable), `kind`, `turnId`, `state`(`queued`/`sent`/`revoked`/`expired`), `tgMessageId`(after send) |
| `mac_status` | singleton: `lastHeartbeatAt`, `presence`(`active`/`paused`), `pauseReason`, `appVersion`, `deadmanFiredAt` |
| `config` | `botToken`, `allowedChatIds`(JSON), `macApiToken`, `deadmanThresholdHours`(default 36), `cannedAck`(pre-authored text) |

**Loops (async, one process):**
1. **Telegram long-poll** — `getUpdates` (offset-tracked); allowlist by `chatId` (drop all
   others silently); append messages + `callback_query` taps to `inbound`; ack callbacks so
   the phone's spinner clears.
2. **Scheduler tick** (every 60s) — for `outbound` where `state=queued` and
   `deliverAt <= now`: if `validUntil` set and `now > validUntil` → `state=expired` (suppress
   stale "good morning at 3pm"); else `sendMessage` (with inline keyboard from
   `suggestedReplies`), store `tgMessageId`, `state=sent`.
3. **Dead-man tick** (same cadence) — if `now - lastHeartbeatAt > deadmanThresholdHours` and
   not already fired this outage → send the pre-authored "coach offline — Mac asleep?" text;
   set `deadmanFiredAt`; reset on next fresh heartbeat.

**Mac-facing HTTP API** (bound to Tailscale/LAN interface only, `Authorization: Bearer
<macApiToken>`):
| Method + path | Purpose |
|---|---|
| `POST /heartbeat` | `{presence, pauseReason?, appVersion}` → update `mac_status`; returns due-count hint |
| `GET /inbound?since=<id>` | drain undrained inbound; Mac marks drained via cursor ack |
| `POST /outbound` | `{chatId, text, suggestedReplies?, deliverAt?, validUntil?, kind, turnId}` — immediate (no `deliverAt`) or scheduled |
| `POST /revoke` | `{outboundId}` → `state=revoked` if not yet sent (best-effort; can't unsend) |

**Security:** bot token + Mac API token in relay env/`config`, never in the repo; `chatId`
allowlist; no public webhook (long-poll is outbound-only); API bound to the private-network
interface. Content transits Telegram's servers (not E2E — bots can't do secret chats) and
rests transiently in home SQLite; nothing on a cloud provider. Optional off-site
"heartbeat-of-the-heartbeat" (a free uptime ping to a relay health URL) so a house
power/ISP outage that kills the relay is itself noticed.

---

## 4. Component B — `TelegramRelayChannel: CoachChannelAdapter` (Mac)

The protocol the coach brain sees (channel-agnostic — CloudKit later conforms the same way):

```
protocol CoachChannelAdapter {
    func send(_ message: OutboundCoachMessage) async throws           // immediate
    func schedule(_ message: OutboundCoachMessage, at: Date, validUntil: Date?) async throws
    func revoke(_ messageId: String) async throws
    func drainInbound() async throws -> [InboundCoachMessage]         // messages + taps
    func heartbeat(_ status: BrainStatus) async throws
    var capabilities: ChannelCapabilities { get }
}
```

`TelegramRelayChannel` implements each as a call to the relay's HTTP API. Capabilities
advertise Telegram's real limits so the coach adapts honestly:
`hasQuickReplies = true` (inline keyboards), `hasScheduledDelivery = true` (via relay),
`hasDeathDetection = true` (via relay), **`hasReadReceipts = false`** (bots are blind to
delivery/read — decay sees reply + tap vs silence only; §6). The coach never imports
Telegram or HTTP types — only the protocol.

---

## 5. Telegram specifics

- **Quick replies:** `suggestedReplies` → an inline keyboard (`callback_data` per button,
  cap 2–3 per the graded-ask philosophy); taps arrive as `callback_query` → normalized into
  `InboundCoachMessage(kind: .tap)`. This is the activation-energy weapon ("tap Yes").
- **Length:** Telegram's 4096-char limit is generous; the constitution's "short and human"
  keeps us far under. No SMS-style segmentation.
- **Parse mode:** plain text by default (avoid Markdown/HTML injection from
  dynamically-composed content); escape if formatting is ever added.
- **Restraint caveat (documented limit):** notification interruption level is the user's
  Telegram setting, not ours — the constitution's restraint can't be enforced at the
  notification layer here (a CloudKit-companion gain, deferred).

---

## 6. Decay telemetry under Telegram's blindness

| Signal available | → decay model |
|---|---|
| reply text | engagement — boost cadence |
| inline-button tap (`callback_query`) | engagement — boost |
| silence (no reply/tap before next tick) | unheeded — decay |
| NOT available: delivered / read receipts | — |

Blind spot to design around (review Addendum 5): "unread," "unreachable," and "read-but-
silent" collapse into one "silence" bucket, so the decay model must not over-read a single
silent window as disengagement (e.g., require N consecutive silent nudges before stepping
cadence down, and treat a resumed reply as a full boost). Richer receipts are a
CloudKit-companion upgrade.

---

## 7. What's unblocked vs gated

- **Relay (Component A): FULLY UNBLOCKED.** Separate service, not in `Sprung.xcodeproj`,
  zero file contention with the in-flight UX refactor. Buildable + testable in isolation
  today (as an echo/queue bot before any coach exists).
- **`CoachChannelAdapter` + `TelegramRelayChannel` (Component B): NEARLY UNBLOCKED.** New
  files in the Sprung codebase, not edits to the contended `PipelineView`/shell files.
- **Coach brain** (constitution, memory, arbiter, decay, tools): still needs the
  ratification must-fixes from the review (unattended budget posture, outbound arbiter,
  dossier append-only overlay, coach-turn eval harness, diagnosis sufficiency gate) AND the
  UX-refactor Discovery-wave gate. NOT part of this slice.

---

## 8. Build phasing (this slice only)

1. **V1-A — relay as standalone echo/queue bot.** systemd service (or AppDaemon per D1):
   long-poll + allowlist + SQLite + the Mac-facing API, with a trivial echo so a real bot
   token can be smoke-tested end-to-end (text the bot → appears in `inbound` → `POST
   /outbound` echoes back). Proves Telegram + relay + API in isolation.
2. **V1-B — Mac adapter.** `CoachChannelAdapter` protocol + `TelegramRelayChannel`; wire to
   a stub coach that echoes/canned-replies. Proves Mac↔relay round-trip + quick-reply taps.
3. **V1-C — scheduled + dead-man.** Scheduler tick, `validUntil` expiry, revoke, dead-man
   fire + reset. Proves the always-on guarantees (send-while-Mac-asleep, silent-death
   surfacing) with the Mac deliberately quit/asleep.
4. **V1-D — integrate the real coach brain.** Gated on coach-spec ratification + the UX
   Discovery-wave gate. Out of scope here.

---

## 9. Decisions (RESOLVED 2026-07-08)

- **D1 — relay packaging: standalone Python systemd service.** Decoupled from HA's
  lifecycle, most robust, portable to any Linux box. Trade accepted: no HA presence
  detection in v1 (presence-aware arbiter timing is a later enhancement, addable by reading
  HA's REST API from the relay if wanted, without repackaging).
- **D2 — Mac↔relay connectivity: Tailscale.** The relay's Mac-facing API binds to the
  Tailscale interface; the MacBook reaches it from anywhere. Coach functions while traveling.
- **D3 — repo structure: a standalone git repo at `../coach-relay`** (i.e.
  `/Users/cculbreath/devlocal/codebase/coach-relay`, sibling to Sprung; NOT a submodule, NOT
  a subdir of the Xcode repo). Optimizes for the Debian deploy (small clone + `git pull`, no
  Xcode noise) and independent shareability. **Accepted tradeoff:** the wire contract lives
  in two repos (Swift `TelegramRelayChannel` in Sprung; Python relay here) → drift risk.
  Mitigations: a `PROTOCOL.md` here is the single source of truth for the endpoint/JSON
  contract, and `/health` advertises a `protocolVersion` + capabilities string so the Mac
  adapter detects skew at runtime rather than failing cryptically. Contract is 4 endpoints,
  so drift is low-frequency.

## 10. Implementation status & proposed layout

**Nothing built yet — this is a spec.** No `../coach-relay` repo exists. Proposed V1-A scope
when implementation is greenlit: pure-stdlib Python 3 (zero pip deps, runs on system
`python3` — no venv) — long-poll + chatId allowlist, SQLite queue/schedule/heartbeat,
Tailscale-bound Mac HTTP API (`/heartbeat`, `/inbound`, `/outbound`, `/revoke`, unauth
`/health`), scheduler tick (`validUntil` expiry), dead-man tick, one-per-outage canned ack.

**Proposed repo layout** (`/Users/cculbreath/devlocal/codebase/coach-relay`, own git repo):
```
coach-relay/
├── coach_relay/                # the package (python -m coach_relay)
│   ├── __init__.py
│   ├── __main__.py             # entrypoint: load config, start threads, serve
│   ├── config.py               # load + validate config.json
│   ├── store.py                # SQLite: inbound, outbound, mac_status, kv(tg_offset)
│   ├── telegram.py             # long-poll getUpdates · sendMessage · inline keyboards · answerCallbackQuery
│   ├── api.py                  # Tailscale-bound HTTP handlers (ThreadingHTTPServer)
│   └── ticks.py                # scheduler tick (validUntil expiry) + dead-man + canned-ack
├── tests/
│   └── test_logic.py           # pure-logic unit tests (validUntil, allowlist, staleness) — stdlib unittest
├── config.example.json         # template (placeholders); real config.json is gitignored
├── coach-relay.service         # systemd unit template
├── PROTOCOL.md                 # single source of truth for the Mac↔relay wire contract
├── README.md                   # BotFather · Tailscale · install · run · smoke test
├── .gitignore                  # config.json, *.db, __pycache__/
└── LICENSE
```
(Single-file `coach_relay.py` is an acceptable lighter alternative if you'd rather not have a
package for ~400 lines — same modules, one file. Default above is the package.)

**Deploy story (standalone repo → Debian box):** `git clone` to e.g. `/opt/coach-relay`;
put real secrets in `/etc/coach-relay/config.json` (chmod 600, never in the repo); install
the systemd unit; `systemctl enable --now coach-relay`. Update = `git pull && systemctl
restart coach-relay`. No pip, no venv (pure stdlib).

- **User prerequisites (only you can do these), before V1-A can be smoke-tested:** create
  the bot via **@BotFather** and grab the token; find your numeric chat id; install
  **Tailscale** on the Debian box + MacBook.
- **Then V1-B** — `CoachChannelAdapter` protocol + `TelegramRelayChannel` on the Mac (new
  Sprung files). V1-C (scheduled/dead-man) is folded into V1-A above; V1-D (real coach
  brain) waits on coach-spec ratification.
