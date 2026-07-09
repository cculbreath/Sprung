# Sprung Coach Companion — CloudKit iOS App Spec

*Subordinate to `plans/coach-agent-spec.md` (the coach spec). Resolves its §14.1 channel
fork per `plans/coach-agent-spec-review-2026-07-08.md` Addendum 4: the product channel is a
thin iOS companion app synced over the user's private CloudKit database. The phone — the
one always-on device every user carries — absorbs the "mailroom" role (durable queue,
scheduled delivery, watchdog, chat surface). The Mac app remains the brain. Telegram-bot
scaffolding may precede this build to validate coach behavior; both are adapters behind
the same channel protocol (§11).*

---

## 1. Purpose & non-goals

**Purpose.** Give the coach a surface that (a) reaches the user away from the Mac with real
push notifications, (b) never loses a message to a sleeping Mac, (c) delivers scheduled
nudges on time regardless of Mac state, (d) reports honestly when the brain is unavailable,
and (e) requires zero per-user setup beyond installing the app on a phone already signed
into the same iCloud account.

**Non-goals (hard).** The companion app is *not* a second brain and *not* a workspace:
- No LLM calls from the phone. No Anthropic API key on the phone. Ever.
- No coach logic (arbiter, decay, memory) on the phone — it renders and reports.
- No resume/packet functionality. The workspace is the Mac; the phone may at most queue a
  "show me this when I'm at my Mac" handoff (§7, phase 3).
- No developer-run server. The only parties in the content path are the user's two devices,
  the user's iCloud, and (from the Mac only) the Anthropic API.

---

## 2. Architecture at a glance

```
┌────────────────────┐         ┌──────────────────────┐         ┌────────────────────┐
│  Mac app (brain)   │  CKSync │  CloudKit private DB │  CKSync │ iOS companion       │
│  coach loop, memory│◄───────►│  custom zone "coach" │◄───────►│ (surface + mailroom)│
│  arbiter, decay,   │  + push │  CoachMessage        │  + push │ thread UI, local    │
│  tools, SwiftData  │         │  MessageReceipt      │         │ notif scheduling,   │
│  (canonical store) │         │  BrainStatus         │         │ receipts, watchdog  │
└────────────────────┘         └──────────────────────┘         └────────────────────┘
```

- **Mac** composes every message (full-context drafting), decides timing (arbiter), and
  ingests receipts into the decay model. Canonical conversation history lives in the Mac's
  SwiftData store; CloudKit is the synced transport/view, not the source of truth.
- **CloudKit private DB** is the queue: durable while either device is offline, hosted by
  Apple inside the user's own account, no quota cost to the developer.
- **iPhone** renders the thread, schedules local notifications for future-dated messages,
  reports engagement receipts, and runs the phone-side dead-man switch.

Auth = iCloud account identity. No accounts, tokens, or pairing flows.

---

## 3. CloudKit design

**Container:** one custom container (`iCloud.<bundle-prefix>.sprung-coach`), private
database only. **Zone:** a single custom zone `coach` (custom zone required for
change-token sync and atomic batches).

### Record types

Single-writer discipline: **every record type has exactly one writing side.** The other
side only reads. This makes CloudKit conflicts structurally impossible — no merge policy
code, no `serverRecordChanged` handling beyond retry-with-server-record.

| Record type | Writer | Fields |
|---|---|---|
| `CoachMessage` | author side only (Mac for coach turns, phone for user turns; a record is never edited by the non-author) | `direction` (`coachToUser`/`userToCoach`) · `body` (String) · `kind` (`nudge`/`greatFitAlert`/`outcomePing`/`warmLeadPrompt`/`progressNote`/`reply`/`ack`/`statusNote`) · `turnId` (String, conversation grouping) · `authoredAt` (Date) · `deliverAt` (Date?, nil = immediate) · `validUntil` (Date?, staleness guard) · `state` (`queued`/`delivered`/`revoked` — Mac-owned messages only) · `suggestedReplies` ([String]?) · `payload` (String?, JSON) |
| `MessageReceipt` | phone | `messageRef` (Reference) · `event` (`notifDelivered`/`notifOpened`/`readInApp`/`dismissed`/`replied`) · `at` (Date) |
| `BrainStatus` | Mac (singleton, fixed record name `brainStatus`) | `lastHeartbeatAt` (Date) · `presence` (`active`/`paused`) · `pauseReason` (String?, e.g. `budget`) · `appVersion` (String) |

Field names camelCase (house JSON rule — keys we control). `payload` is the additive
escape hatch: **CloudKit production schema is append-only** (deployed record types and
fields can never be deleted or renamed), so the typed schema stays minimal and anything
speculative rides in `payload` until proven.

Retention: Mac store is canonical; CloudKit thread may be pruned (e.g., > 6 months old)
by the Mac without data loss. Records are small text — user iCloud quota impact is
negligible, but handle `CKError.quotaExceeded` with an honest in-thread status.

---

## 4. Sync

Both sides run **`CKSyncEngine`** (iOS 17+ / macOS 14+): it owns push registration, change
tokens, batching, retry/backoff, and account-change handling — no hand-rolled
`CKDatabaseSubscription` plumbing. Engine state serializes per device.

- **Mac:** registers for remote notifications (`aps-environment` entitlement); while awake,
  a user reply reaches the brain seconds after send. While asleep, nothing is lost — sync
  drains on wake. A defensive reconcile fetch runs on app activation and on a slow timer.
- **iPhone:** sync triggers on push (silent), on app open, and via `BGAppRefreshTask`
  opportunistically. Silent-push throttling is expected and absorbed by design (§5).
- **Account status:** both apps check `CKContainer.accountStatus` and surface
  no-iCloud/mismatched-account states explicitly (first-run and on change). No silent
  degradation (house rule).

---

## 5. Scheduled delivery & revocation (the load-bearing mechanics)

The trick that makes the phone the mailroom:

1. Mac drafts with full context whenever the brain runs (e.g., 11pm: tomorrow's morning
   nudge), writes `CoachMessage` with `deliverAt = 8:30am`, `state = queued`.
2. iPhone receives the record via sync (hours of slack absorbs any push throttling) and
   schedules a **local notification** (`UNCalendarNotificationTrigger`) for `deliverAt`.
3. The notification fires at 8:30am with the Mac asleep. On user interaction, the phone
   writes receipts; when the Mac wakes, receipts flow into the decay model.

**Edge handling:**
- *Sync arrives after `deliverAt`* (throttled push, phone off): deliver immediately **iff**
  `now < validUntil`; otherwise suppress and write a `dismissed` receipt with the reason in
  `payload`. A stale "good morning" at 3pm is the annoying-coach failure — `validUntil` is
  mandatory on every scheduled message.
- *Revocation:* circumstances change (user already did the thing) → Mac sets
  `state = revoked` → phone cancels the pending local notification on next sync.
  **Best-effort by nature** (local notifications can't run code at fire time; cancellation
  needs a sync to arrive first). Consequence for the arbiter (coach spec review C3): word
  scheduled nudges to stay true under mild staleness; anything volatile ships `validUntil`
  tight.
- *Multiple devices* (iPad later): receipts are unioned; local scheduling dedupes by
  message record name (notification identifier = record name — idempotent rescheduling).

---

## 6. Engagement telemetry → the decay model

This channel feeds the coach-spec §6 decay model better than any alternative (SMS has no
receipts; Telegram has coarse read state):

| Receipt event | Decay signal |
|---|---|
| `notifDelivered` | message reached the user's pocket |
| `notifOpened` / `readInApp` | attention — sustains cadence |
| `replied` (+ latency) | engagement — boosts cadence |
| `dismissed` / delivered-never-read | unheeded — decays cadence |

The Mac ingests receipts on sync and updates decay state. No interpretation happens on the
phone — it reports events, the brain draws conclusions.

---

## 7. The iOS surface

Deliberately thin — one screen plus notifications:

- **Thread view** (SwiftUI): the single coach conversation. Message bubbles, coach
  presence header (§8), day separators. No tabs, no dashboard — the anti-dashboard
  principle from the coach spec applies doubly here.
- **Suggested-reply chips** from `suggestedReplies` — one tap sends. This is the
  activation-energy weapon: "Yes, set it up" / "Not today" as buttons, mirroring the
  graded-ask philosophy.
- **Notification UX:**
  - `UNNotificationCategory` with actions built from `suggestedReplies` (cap 2–3) plus a
    `UNTextInputNotificationAction` — **reply from the lock screen without opening the
    app**, the lowest-friction coaching interaction possible.
  - Interruption levels encode the coach's restraint: default `.active`; never
    `.timeSensitive` or `.critical`; Focus modes are respected as-is. A coach that
    punches through Do Not Disturb has already failed §3 of its constitution.
  - Notification permission denied → in-app-only mode, and the Mac app is told (via a
    receipt-style status record in `payload`) so the coach knows its reach is degraded and
    can say so in the thread rather than shouting into the void.
- **Apple Watch:** free win — iPhone notifications mirror to the Watch automatically, with
  suggested-reply actions intact. Glance-and-dismiss on the wrist is peak
  meet-you-where-you-are; no watchOS target needed for v1.
- **Handoff action (phase 3):** coach messages referencing a job/packet render a "queue it
  for my Mac" chip → writes a handoff record → Mac deep-links into the workspace
  (`deep_link` tool) on next activation. The phone never opens the workspace; it schedules
  intent.

---

## 8. Honesty states (presence, pause, dead-man switch)

The review's headline failure mode is the coach dying silently. The companion app is where
that becomes visible:

- **Presence header** derived from `BrainStatus`: fresh heartbeat → "●" (no copy needed);
  stale → "coach is away — replies when your Mac wakes"; `paused`/`budget` → "paused —
  out of API budget," honestly, in the thread (this is the unattended posture for
  `BudgetPauseGate` that review B1 demands — the pause is *communicated*, not modal).
- **Send-while-away:** user messages always send (CloudKit queues); the thread marks them
  "delivered — coach will reply when your Mac is back." Never dead air, never a lie.
- **Phone-side dead-man switch:** every sync bearing a fresh heartbeat cancels and
  reschedules a local notification "Your coach has been offline for a while — is your Mac
  asleep?" at `lastHeartbeatAt + 36h`. Heartbeats stop → the notification eventually
  fires. Zero infrastructure, no server, and the watchdog can't die with the thing it
  watches short of losing the phone itself.

---

## 9. Privacy & security

- Content path: user's devices ↔ user's private CloudKit DB ↔ (Mac only) Anthropic API.
  No third-party messaging service, no carrier plaintext, no developer server, no
  analytics.
- CloudKit private DB is encrypted in transit and at rest; **end-to-end only if the user
  enables Advanced Data Protection** — state this honestly in any privacy copy; don't
  claim E2E by default (review C4 discipline).
- The phone holds conversation content only — no dossier, no knowledge cards, no contacts
  DB, no API keys. Standard iOS data protection covers the local cache.

---

## 10. Distribution & signing

- **Apple Developer Program** ($99/yr, developer-side once) — required for CloudKit, APNs,
  and TestFlight regardless of channel choice.
- **Mac app:** Developer ID (non-MAS) apps support CloudKit + remote notifications via a
  Developer ID provisioning profile with iCloud entitlements. **Spike S1 verifies this
  end-to-end before anything else is built** — it is the one assumption that would
  restructure the plan if wrong (fallback: Mac App Store distribution, a larger product
  decision).
- **iOS app:** personal use via Xcode/TestFlight; product via App Store. The App Store
  listing names the coach — ties into the coach-spec §14.5 identity decision.

---

## 11. Repo & code structure

- **`CoachKit`** — local SPM package shared by both targets: record-type definitions,
  schema constants, message/receipt/status models, state machines, `CoachChannelAdapter`
  protocol. Pure Foundation + CloudKit; no AppKit/UIKit/SwiftData.
- **Mac side:** `CloudKitCoachChannel: CoachChannelAdapter` (send / receive /
  scheduleDelivery / revoke / capabilities). The coach loop, arbiter, and decay model see
  only the protocol — Telegram scaffolding and any personal channels are sibling adapters;
  swapping channels never touches coach behavior.
- **iOS side:** new iOS app target in `Sprung.xcodeproj` (`SprungCoach` — name pending
  §14.5), filesystem-synced group, depends on `CoachKit` only. It must not import the Mac
  app's modules; anything both need moves into `CoachKit` deliberately.
- Naming per house taxonomy: `…Channel`/`…Service` for doers, `…Store` for the phone's
  local thread cache, no `Manager`.

---

## 12. Failure modes

| Failure | Mitigation |
|---|---|
| Silent push throttled/dropped | schedule far ahead; `BGAppRefreshTask` + fetch-on-open fallbacks; `validUntil` suppresses stale delivery |
| Mac asleep at reply time | CloudKit queues; thread shows honest "replies when Mac wakes"; canned-ack pattern optional via pre-queued `ack` message |
| Revocation misses (no sync before fire) | arbiter words scheduled sends to survive mild staleness; tight `validUntil` on volatile content |
| iCloud signed out / account mismatch | `accountStatus` check, explicit blocking UI both sides — never silent |
| Notification permission denied | in-app-only mode; Mac informed; coach acknowledges degraded reach in-thread |
| iCloud quota exceeded | tiny records make it unlikely; on `quotaExceeded`, honest in-thread status + Mac warning |
| Coach dies silently (budget, crash, sleep) | heartbeat + presence header + 36h phone-side dead-man notification |
| CloudKit schema mistake shipped to production | append-only discipline; minimal typed fields; `payload` JSON for anything unproven |

---

## 13. Build phasing

- **S1 (spike, gates all):** Developer ID Mac app + CloudKit entitlement + push,
  end-to-end record round-trip Mac ↔ scratch iOS app. 1–2 days, throwaway.
- **P0:** `CoachKit` package; `CoachChannelAdapter` protocol; `CloudKitCoachChannel` on
  the Mac; schema deployed to the dev environment.
- **P1:** iOS thread UI + CKSyncEngine + immediate notifications + receipts + presence
  header. (Coach becomes usable away from the Mac.)
- **P2:** scheduled local delivery, revocation, `validUntil`, dead-man switch, budget-pause
  honesty. (The mailroom is complete; review A2/B1 items close.)
- **P3:** lock-screen text reply, suggested-reply chips/actions, handoff-to-Mac records,
  Watch polish, pruning.

Coordination: the Telegram scaffolding adapter (review Addendum 4) can precede or parallel
P0 to validate constitution/arbiter/decay behavior on a live channel while S1/P0 land;
both adapters ship behind the same protocol, so nothing is thrown away.

---

## 14. Open decisions

1. **App + coach name** (inherits coach-spec §14.5) — the App Store listing makes it
   public and semi-permanent.
2. **OS floor** — CKSyncEngine sets iOS 17 / macOS 14 minimum; default to current-−1
   unless a reason emerges.
3. **History retention** in CloudKit (default: prune > 6 months; Mac canonical).
4. **v1 device scope** — iPhone only (Watch via mirroring, iPad later)?
5. **Distribution endgame** — TestFlight indefinitely vs App Store, and whether the Mac
   app's own distribution moves under the same Developer ID profile umbrella.
6. **Quiet hours** — phone-local setting, learned dossier preference, or both (default:
   both — hard windows local, cadence learned).
