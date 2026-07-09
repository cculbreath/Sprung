# Adversarial Review — `coach-agent-spec.md` (2026-07-08)

Feasibility assessment + failure-mode analysis of the coach-agent spec as written. Grounded
against live source (entitlements, DiscoveryCoordinator, BudgetPauseGate, ContactsImportService,
MCP client) and the repo's standing constraints. Organized: keystone risks → places current
systems under-deliver on the spec's assumptions → internal design tensions → verdict/sequencing.

---

## A. Keystone risks — things that can sink the plan as written

### A1. The iMessage channel has an unexamined identity problem (highest risk in the spec)

The spec frames the iMessage fork as "fragile + needs the Mac awake" vs Twilio. The real
problem is upstream of fragility: **who does the coach text *as*?**

- If the Mac's Messages is signed into *your* Apple ID and the coach sends to your own
  number/ID, the message lands in the **"Note to Self" thread — which does not fire a
  notification on your iPhone**. The proactive channel silently loses its proactivity. The
  entire value proposition ("reaches the stalled user where the app can't") dies on this
  detail.
- The standard fix is a **second Apple ID** acting as the coach, signed into Messages on the
  Mac. But macOS Messages runs one iMessage account per macOS user session — so the Mac
  either gives up the user's own iMessage, or the coach runs inside a separate macOS user
  account (always-logged-in fast-user-switched session: real, but a pile of operational
  weirdness the spec never mentions: separate TCC grants, separate chat.db, launch agents in
  another session).
- Receiving: polling `chat.db` requires Full Disk Access. The app is unsandboxed (verified:
  `Sprung.entitlements` has only font entitlements), so this is *grantable* — but the TCC
  grant is tied to the signed binary, and the app runs from DerivedData during development
  (standing constraint; the user previously declined copying to /Applications). DerivedData
  cleans/resigns → grant churn. Also `chat.db` message text has lived in `attributedBody`
  (archived typedstream) rather than the `text` column since Ventura; we're on macOS 26 —
  schema drift is likely and unverified.
- AppleScript send: `send ... to chat id` works for *existing* conversations; creating a
  *new* conversation to a recipient via AppleScript has been unreliable for years. Needs a
  once-manual conversation bootstrap. Fine, but must be known.

**Verdict:** iMessage-local is feasible but only after resolving the two-Apple-ID question,
and it deserves a 1–2 day spike *before anything else is built on top of it*. This is the
keystone; the spec defers it as "open decision #1" while phasing puts foundations first.
De-risk order is backwards for this one item.

### A2. "Always-on" on a Mac host is structurally not always-on

All three trigger surfaces (scheduler, iMessage egress, chat.db polling) require the Mac
**awake**. `NSBackgroundActivityScheduler` does not wake a sleeping Mac; LaunchAgents don't
either (only `pmset`-scheduled wakes / power-nap-class daemons do, and those aren't app
territory). A laptop with the lid closed = coach fully dead: no morning nudge, no reply to
the user's 11pm "yes, do it" until the next wake.

The Twilio path does **not** fix this — it moves only the *transport* to the cloud. The
brain, memory, and tools are on the Mac; an inbound SMS at 11pm still waits for the Mac.
The spec's "robust, always-on" framing for Twilio conflates transport availability with
agent availability.

**Verdict:** acceptable *if* the deployment reality is a desktop Mac with sleep disabled
(or scheduled wakes) — but the spec should state that hardware assumption explicitly,
because it silently determines whether "proactive" means "proactive" or "proactive during
banker's hours when the lid is open."

### A3. The Twilio branch underestimates its own friction, and the fork excludes the middle

- US SMS via Twilio now requires **A2P 10DLC registration** (sole-prop campaign
  registration, brand vetting, weeks of lead time, per-message carrier fees) or toll-free
  verification. Unregistered traffic is filtered. "Developer already knows Twilio" predates
  this regime.
- Two-way SMS needs an inbound webhook → public endpoint → tunnel (ngrok/Tailscale funnel)
  or polling the Twilio inbound-message API from the Mac. More moving parts than the spec
  implies.
- **The excluded middle:** a Telegram (or WhatsApp Business) bot is what OpenClaw-alikes
  actually ship: free, real push notifications on the phone, two-way via long-polling from
  the Mac (no public endpoint, no A2P, no second Apple ID), trivial API. It concedes
  "content transits Telegram's servers" — but see C4: content transits Anthropic's servers
  in *every* branch, so the marginal privacy loss is smaller than the spec's framing
  implies. The fork should be a three-way decision, and Telegram is arguably the rational
  default for v1 with iMessage as the aesthetic end-state.

---

## B. Where current systems will under-perform the spec's assumptions

### B1. `BudgetPauseGate` cannot be reused as-is for an unattended agent

Verified: it lives in `Onboarding/Core/`, is wired through `OnboardingDependencyContainer`,
and its contract is **halt-and-drive-a-modal-sheet** (`pendingPause` drives UI). For an
overnight coach, halt-and-prompt means the heartbeat **silently dies** until the user
happens to open the Mac app — the exact "coach disappears" failure the decay model exists
to prevent. Worse, the user's reply over text can *itself* need an LLM turn to process, so
a budget pause mid-conversation strands the user mid-dialogue with no explanation.

Needs a runtime-mode budget policy, not reuse: cap per unattended window, degrade to
silence **plus one cheap pre-drafted text** ("out of budget, paused — top up when you get a
chance"), and a morning report. The house rule "halt and prompt, never silent fallback"
was designed for attended flows; unattended flows need an explicit third posture.

### B2. The fatigue fields the spec plans to "resurrect" no longer exist

`notificationFatiguePauseOffered` / `notificationsPausedAt` grep to **zero hits** — they
were deleted in one of the cleanup passes after the dossier/audit that the spec drew on.
Trivial to rebuild, but it flags a broader issue: the spec's grounding ledger (§11) was
accurate at synthesis time and is already drifting. Anything in "Reuse (real today)" should
be re-verified at `/tackleplan` time, not trusted.

### B3. LinkedIn excavation ambition vs. a 30/hr budget on the user's *primary account*

The spec's marquee example — mining ~1,243 former students via LinkedIn alumni/geo search —
collides with two facts: the MCP budget is 30 requests/hr, and the MCP drives the user's
**real LinkedIn account** (session-cookie auth). Bulk people-search is precisely the
pattern LinkedIn's anti-automation heuristics flag; the downside is restriction of the
user's primary professional identity *during a job search*. The excavation engine must be
designed as **slow-drip and conversation-led** (Contacts + memory + the category interview
carrying most of the load, LinkedIn used for targeted lookups of already-named people), not
as a sweep. The spec gestures at this but the "make the invisible network visible" framing
reads as batch; the implementation must not be.

### B4. Scout's match signal is enums, not a scalar — the "≥ threshold" trigger doesn't type-check

The great-fit alert trigger assumes a scalar score ("Scout finds a ≥ threshold match"), but
the 2026-07-08 Scout redesign deliberately replaced numeric scores with **dimensioned enum
signals**. Small, but it means trigger policy needs a real mapping (e.g., "strong on ≥2
dimensions, none weak") — a design decision, not a comparison operator. Whoever builds the
trigger layer will discover mid-build that the spec's contract doesn't exist.

### B5. Single-process assumption: SwiftData vs. the launchd relaunch idea

`SMAppService`/LaunchAgent relaunching "when closed" implies a second process touching
`default.store` while the app may also be open. SwiftData's multi-process story is
effectively "don't" (no persistent-history merging surfaced in the API). The realistic
architecture is **single-process**: the app itself is a login item that stays resident
(menu-bar presence when windows close), scheduler inside it. That's simpler than the spec's
either/or — but it hardens A2: quit the app, coach is gone. The spec should just commit to
single-process + login-item and delete the launchd branch.

### B6. Prompt-cache economics are hostile to a heartbeat agent

House caching is tuned for dense interactive sessions (≤4 breakpoints, byte-stable
prefixes, 5-minute TTL). A proactive coach's turns are **sparse** — one nudge at 9am, a
reply at 9:40, an outcome ping at 6pm. Every turn outside the 5-min window re-reads
constitution + dossier + funnel state cold. Quality-first (Opus-class) × full-context ×
several turns/day is plausibly **dollars per day** — and the observed reality of this
project is metered credits topped up $10 at a time, with lean-orchestration as a standing
preference. §10's "cost is a small consideration" is the one claim in the spec that
observed behavior directly contradicts. Mitigations exist (1h-TTL cache tier, trimmed
per-trigger context — a morning nudge doesn't need the full dossier, only the diagnostic
altitude does) but they must be *designed in*, or the coach gets budget-paused into the B1
failure mode within a week.

### B7. Zero notification/scheduler primitives is confirmed — but the scheduler isn't the hard part

Verified: no `NSBackgroundActivityScheduler`, no `SMAppService`, no `UNUserNotificationCenter`
anywhere in the codebase; autoruns fire only at coordinator startup
(`DiscoveryCoordinator.swift:202,204`). The spec calls the proactive runtime "the largest
single build." Adversarially: the *timer* is a day of work. The actual largest build is the
**inbound conversational loop** — chat.db watermark polling, thread/session state across
hours-long gaps, mid-conversation tool use, idempotent delivery, trigger-vs-reply
collision handling ("morning nudge fires while user is mid-reply about yesterday's
outcome"). None of that is enumerated in §11's build list, which means it isn't costed.

### B8. The diagnostic altitude is statistically underpowered and data-starved

Funnel-leak analysis segmented by track (controls vs SWE) on a personal search means
comparing response rates on n≈15–40 per cell where base rates are 5–15%. Confidence
intervals will overlap almost totally for months. LLMs are exceptionally good at narrating
noise as signal, and the coach's voice ("honest, concrete") makes confident-wrong diagnosis
*more* damaging — a plausible-sounding "your controls apps out-respond your SWE apps" based
on 3 vs 1 responses could redirect an entire search. The sufficiency gate must be
**hard-coded arithmetic** (min n per cell, min CI separation) that gates whether the
diagnostic tool is even *callable* — never LLM judgment about whether it has enough data.

Compounding: outcome capture depends on the user answering "did you hear back from
Dragonfly?" texts — the same user whose disengagement is the coach's core problem. Expect
episodic data to be sparse *and* censored (rejections without reasons are the norm).
Diagnosis (phase 5) should be scoped down to "top-of-funnel vs mid-funnel, market vs you"
rather than the spec's finer-grained localization until a real season of data exists.

---

## C. Internal design tensions

### C1. Dossier writeback vs. "KC quality never regresses"

§4.1/§4.4 have the coach continuously re-synthesizing and writing back to the dossier — the
same dossier produced by the extraction pipeline that is under a standing
quality-never-regresses guarantee, with "do not touch extraction" in the same paragraph.
A month of LLM writebacks (confabulated "learned traits," over-generalized one-off remarks
— user says "I hate networking events" on one bad day → permanent trait) will corrupt the
highest-quality asset in the system, slowly and silently. The fix is architectural:
**extracted dossier stays immutable; learned traits live in an append-only overlay** (one
fact per record, provenance + timestamp + source-quote, revocable); the runtime "dossier"
is a *synthesized view* that can always be regenerated from the two layers. The spec's
"one fact per record + an index" reference model is compatible — but "written back to the
dossier" as literal mutation must be ruled out during ratification, not left ambiguous.

### C2. The autonomy ceiling contradicts the tool table

§5 defines `send_message` as "draft-and-notify only" — but the coach's entire premise is
**autonomously sending** coaching texts (morning nudge, stall check-in). The ceiling needs
recipient-scoping: autonomous sends **to the principal** are the product; anything
addressed to a third party is draft-only, no exceptions. As written, an implementer either
builds a coach that can't text (following §5) or quietly drops the ceiling (following §6–7).
One sentence fixes it; without the fix it's a genuine spec bug.

### C3. "One ask at a time" has no arbiter

Six trigger types run on independent logic (Scout alert, morning nudge, stall check,
outcome collection, warm-lead prompt, progress note). Nothing in the spec owns the outbound
channel. On any given morning three triggers can legitimately fire. The decay model
modulates *frequency*, not *contention*. Needs a named component — an outbound arbiter
holding a priority order, per-day quota, suppression rules ("outcome-collection defers to
an in-flight conversation"), and the decay state. This is the single most
important *new* runtime component and it appears nowhere in §11's build list.

### C4. The privacy framing overstates locality

"iMessage-local keeps everything on the Mac" is false in the sense that matters: every
coaching turn ships the dossier, contact names, employer names, and outcome history to the
Anthropic API. Channel choice affects *transport of the final rendered text only*. That may
be perfectly acceptable (it's already true of the whole app) — but §9 should say it
honestly, because "private, yours, local" is inherited OpenClaw rhetoric describing a
local-LLM system, which this is not.

### C5. The character is the product, and there's no way to test it

Non-annoying-ness, restraint, and tone under decay pressure are the deliverable — and the
plan has no eval story. The repo already owns the right primitive: the tape
record/replay seam. Extend it to coach turns from day one (record every proactive
turn + context + decision), and build a small scenario battery (stalled-user week,
bad-news week, silent week) replayed against constitution changes. Otherwise every
constitution edit is a blind deploy against the user's patience, and the failure mode —
trained-to-ignore-the-coach — is exactly the unrecoverable one the decay model warns about.

### C6. Cache-prefix churn from continuous personalization

Learned-trait writeback mutates the dossier that sits in the prompt prefix. Fine — but
order matters (constitution | dossier | volatile state), writebacks should batch (e.g.,
nightly re-synthesis, not per-message), and the existing byte-stability discipline
(CachePrefixAuditor) should extend to the coach's prompt builder. Compatible with C1's
overlay design: the synthesized view regenerates on a schedule, giving stable bytes
between syntheses.

---

## D. Verdict & sequencing

**Feasible?** Yes — as a single-user personal tool on an always-awake desktop Mac, with the
channel question resolved and the budget posture redesigned. No pillar is impossible;
several are mis-costed. The spec is strongest on character/policy (§3, §7b are genuinely
good design) and weakest on runtime mechanics (channel identity, arbitration, inbound loop,
cost) — which is exactly the half that has no precedent in the codebase.

**Most likely failure mode if built as written:** not a crash — a coach that works in
week 1, gets budget-paused or sleep-killed silently in week 2, re-appears awkwardly in
week 3, and is ignored by week 4. Every sub-risk above (A2, B1, B6, C3, C5) feeds that
one outcome. The anti-annoyance decay model gets all the spec's attention, but
*reliability* is what actually earns the right to interrupt.

**Sequencing (answers §14.6):**
1. **Channel spike first** (1–2 days, throwaway code): resolve second-Apple-ID vs
   separate-macOS-user vs Telegram; verify chat.db parse + AppleScript send on macOS 26;
   verify FDA grant survives a rebuild. Everything else in the plan is hostage to this.
2. **Episodic capture immediately and in parallel** — it's cheap (a SwiftData entity +
   `record_outcome` + hooks on existing stage transitions), and every week without it is
   training data lost forever. This is the one part of "memory first" that is genuinely
   time-sensitive.
3. Then the spec's phasing holds (constitution + memory schema → channel for real →
   tactical coach → excavation → diagnosis), with three additions to §11's build list:
   the **outbound arbiter** (C3), the **unattended budget posture** (B1), and the
   **coach-turn tape/eval harness** (C5).

**Spec edits to make before `/tackleplan`:** scope the autonomy ceiling by recipient (C2);
commit to single-process login-item runtime and delete the launchd branch (B5); replace
"resurrect fatigue fields" with "build decay state" (B2); state the awake-Mac hardware
assumption (A2); rewrite §9's privacy paragraph honestly (C4); rule literal dossier
mutation out in favor of the overlay (C1); add Telegram to the §14.1 fork (A3); define the
great-fit trigger against the dimensioned enum signal (B4); hard-code the diagnosis
sufficiency gate (B8).

---

## Addendum (same day): Twilio/SMS assessed as the channel — ENDORSED for v1

Registration regime verified against Twilio docs 2026-07-08. Corrections to A3 and a
resolution of the §14.1 fork:

**Registration reality (better than A3 claimed).** The *sole-proprietor* A2P 10DLC lane is
open to individuals/hobbyists with no EIN: $4 one-time brand fee + $15 one-time campaign
vetting + $2/mo campaign fee; OTP to a personal US mobile (not a Twilio number); largely
automated, days not weeks (A3's "weeks" applies to the standard-brand lane). One number per
sole-prop campaign — exactly one is needed. **New wrinkle:** the toll-free alternative
closed to individuals on 2026-02-17 (Business Registration Number/EIN now mandatory for new
toll-free verifications), so sole-prop 10DLC with a local number is the lane.

**What SMS dissolves:** the entire A1 identity problem (dedicated number = real iPhone
notifications, contact-card identity for the coach, no second Apple ID, no separate macOS
user); all chat.db/AppleScript/FDA/TCC/macOS-26 fragility; the DerivedData TCC churn; and
it makes the channel fully testable/mockable HTTP (feeds C5's eval harness).

**Inbound without a server:** skip webhooks; poll the Twilio Messages REST API from the Mac
app (~15–30s). No tunnel, no public endpoint, latency irrelevant at coaching cadence.

**What SMS does not fix:** A2 in full — transport queues while the Mac sleeps, but the
brain still waits for the lid. Privacy in transit is *worse* (SMS is carrier-visible
plaintext) → add a discretion rule to the constitution (first names, no salary figures,
no employer+outcome pairings). UX texture: green bubble, no typing indicators, ~160-char
segments (constitution already mandates short — convergent), iPhone tapbacks arrive as
literal `Loved "…"` text (inbound parser must normalize), no quick-reply buttons (the one
real loss vs a Telegram bot — "type yes" is higher activation energy than "tap Yes").

**Cost:** ~$1.15/mo number + $2/mo campaign + ~$0.008/segment + carrier fees ≈ **$5–8/mo**
at coach cadence — noise next to LLM spend.

**Thesis fit:** SMS lands in Messages, where the user's attention already lives — a
stronger match for "meets you where you are" than a separate bot app. Verdict: Twilio SMS
via sole-prop 10DLC for v1; the channel spike shrinks from an identity-architecture
question to an afternoon of REST; kick off sole-prop registration immediately since its
approval latency (days) is the long pole.

---

## Addendum 2 (same day): DigitalOcean droplet as always-on relay — ENDORSED as "mailroom, not brain"

The user has a DO droplet. Decision: use it for **clock and transport, never content and
state**. This downgrades A2 from structural to residual.

**Droplet owns (dumb, ~200–400 lines, any stack):**
- Twilio webhook ingress (signature-validated, sender allowlisted) → durable inbound queue
  (SQLite); entries delete on Mac ack. Replaces Mac-side polling entirely; lossless while
  the Mac sleeps.
- **Scheduled egress**: Mac drafts with full context (e.g., 11pm), droplet fires on the
  clock (8:30am). Morning nudges / outcome pings / decay-paced check-ins are all plannable
  sends needing no inference at fire time — most of the heartbeat's practical value becomes
  genuinely always-on.
- **Dead-man watchdog** on Mac heartbeat check-ins → surfaces "coach offline 18h." Directly
  kills the review's headline failure mode (week-2 silent death). Highest-value 30 lines in
  the build.
- Optional canned ack (Mac-pre-authored) sent only after Mac unreachable >20 min — honest
  holding pattern, zero server-side intelligence.

**Droplet must NOT own:** LLM turns (needs dossier/funnel context → either a two-writer
memory-sync problem + PII on a public VPS, or a dumber coach exactly when latency matters);
any tools (start_packet/deep_link/Scout/RevisionAgent are Mac-bound — a droplet brain talks
but can't act); the LinkedIn MCP (real session cookie from a datacenter IP = anti-abuse
trip-wire on the primary account); any second implementation of the coach loop (Swift/
SwiftData code isn't Linux-portable as-is; parallel stack = drift = sprawl).

**Topology:** Mac connects outbound over Tailscale (drain queue, push schedules,
heartbeat); droplet exposes only the Twilio webhook publicly. Single-process conclusion
(B5) unchanged — droplet is a peer service, not a second writer to the store. §2's
three-layer model gains a fourth infrastructural layer: **droplet = the mailroom**.

**Caveat:** if the host Mac is a plugged-in desktop, `pmset` scheduled wakes deliver ~80%
of this with zero new infra; the droplet's decisive wins are the watchdog, lossless
inbound, and laptop/travel. Residual gap either way: live conversational turns remain
Mac-gated (covered honestly by the canned ack).

---

## Addendum 3 (same day): home-infrastructure hosts — final topology

User surfaced three in-house candidates: mom's always-plugged-in iMac, a Hackintosh
laptop, and a Debian box running Home Assistant. Role assignments decided:

**The constraint no host removes:** brain must be co-located with the SwiftData store, and
the store lives with the workspace on the user's primary Mac. SwiftData is not
client-server; a second Sprung instance elsewhere = two stores + a cross-machine two-writer
sync problem (CloudKit sync would force invasive schema changes). The candidate machines
compete only for the mailroom role.

**Debian/HA box → the mailroom** (replaces the droplet). Already managed as a server, free,
and queued message content never rests off-site. Twilio webhook ingress via the remote
access an HA operator already has (Nabu Casa / Cloudflare tunnel / reverse proxy), with
signature validation + sender allowlist. Trade conceded: watchdog independence — a house
power/ISP outage kills watchdog and coach together. Fix: one dumb *external* heartbeat
check (droplet demoted to ping-only, or a free uptime monitor).

**iMac → no v1 role, but it RESURRECTS the iMessage branch for v2.** A dedicated coach
Apple ID signed into Messages in a fast-user-switched background session on an always-on
Mac dissolves review point A1's identity problem (real notifiable blue-bubble texts, no
Twilio, no per-message cost, no carrier plaintext). macOS-26 fragility caveats (AppleScript
send, attributedBody parsing) still apply; FDA/TCC churn mostly evaporates on a stable
installed build. v1 stays Twilio SMS (testable REST vs private-format spelunking); the
mailroom is transport-agnostic so the swap is contained. Not the mailroom host: shared
machine, socially/administratively unmanaged ("always plugged in" ≠ "managed as a server").

**Hackintosh → nothing load-bearing.** OpenCore in the macOS-26 era is effectively EOL;
every update is a boot gamble; and iMessage/Apple ID on spoofed serials risks getting the
coach's Apple ID banned — disqualifying for exactly the role it might have played. Dev/
staging sandbox at most.

**Latent HA asset for later:** presence detection (phone-on-wifi, room occupancy) is a
direct input to the C3 outbound arbiter — delivery timing ("just sat down at the desk")
and suppression windows ("family dinner") that no decay curve can infer from message
history. Not v1 scope; noted for the arbiter's design.

**Final v1 topology:** MacBook = brain + workspace + store (single process, unchanged) ·
Debian box = mailroom · external ping = watchdog · iMac = penciled iMessage bridge (v2) ·
Hackintosh = none. Everything except SMS transport and the Anthropic API stays in the
house.

---

## Addendum 4 (same day, SUPERSEDES Addenda 1–3 topology): portability constraint — CloudKit companion app + Telegram scaffolding

User constraint: Sprung should run on a setup *others might have* — exotic personal infra
makes it an N-of-1 tool. This kills, honestly assessed:
- **Twilio SMS as the product channel** (Addendum 1's endorsement): sole-prop A2P 10DLC is
  a *per-user* registration (their identity, their OTP, their monthly fee) — not a
  shippable onboarding step. Fine never.
- The Debian-box mailroom, droplet, iMac-iMessage-bridge, Hackintosh (Addenda 2–3): all
  personal-only scaffolding.

**The reframe:** for a product, the always-on device is not a server — it is the user's
iPhone. The entire mailroom role = a thin companion iOS app synced over CloudKit:
- **Queue = CloudKit private database** (user's own iCloud): durable while the Mac sleeps,
  free to the developer, and the best PII story of any option — no Twilio/Telegram/carrier/
  developer-server in the content path; only the Anthropic API remains external (inherent).
- **Scheduled egress moves to the phone**: Mac drafts with full context (11pm), writes
  record + delivery time to CloudKit; iPhone receives silent push (hours of slack absorbs
  APNs throttling; fetch-on-open fallback) and schedules a **local notification** (8:30am).
  Fires on time with the Mac asleep — fully solves the scheduled half of A2, zero infra.
- **Push both ways** via CKSubscription→APNs. Developer ID (non-MAS) Mac apps can carry
  CloudKit entitlements — no forced App Store distribution of the Mac side.
- **Watchdog is local**: companion app surfaces thread staleness ("coach hasn't checked in
  since yesterday — Mac awake?").
- Residual (all architectures share it): live conversational turns wait for a Mac wake —
  handled at product level ("delivered — coach will reply when your Mac is back").
- Cost: iOS thin chat app (SwiftUI, shared model types) + CloudKit schema + $99/yr Apple
  Developer Program once for the developer. Product investment, not infra exotica.

**Channel ladder (portability-ranked):**
1. CloudKit companion app — the product answer (biggest build).
2. **Telegram bot — v1 scaffolding**: 2-min per-user BotFather setup (paste token into
   settings), long-polling from the Mac (no server), real push, inline quick-reply buttons
   (best activation-energy UX of any channel). Validates constitution/arbiter/decay
   immediately, and is itself replicable by other users.
3. Email — universal but emotionally disqualified: a job seeker's inbox is where the
   rejections live; wrong room for a morale-protecting coach.
4. Twilio / iMessage-spare-Mac / home boxes — dead under portability (above).

**Architectural consequence (spec edit for ratification):** the channel is a protocol from
day one — `CoachChannelAdapter` (send / receive / scheduleDelivery / capabilities) — so
constitution, memory, arbiter, and decay are channel-agnostic. Telegram and CloudKit are
two adapters on one coach; any personal in-house channel can be a third without touching
the product.

---

## Addendum 5 (same day): what Telegram-only cannot do — scaffolding limits

CloudKit is paid-gated ($99/yr Apple Developer Program, gates BOTH CloudKit AND APNs; free
"Personal Team" excludes iCloud+Push — no free path, no simulator workaround). Telegram bot
is $0 and validates the coach's *brain* (constitution/arbiter/decay/conversation feel), but
it is a message **relay**, not always-on programmable **compute** — and the two capabilities
that need non-Mac compute are exactly what it loses:

1. **Scheduled proactive send with the Mac asleep — BROKEN.** Bot API `sendMessage` is
   immediate-only (no `schedule_date`; scheduling is MTProto/client-API, not bots), and the
   phone's Telegram app can't run our scheduling code. Only the Mac can hold the schedule →
   laptop closed at 8:30am = nudge never fires. The outbound heartbeat degrades to "fires
   if the Mac happens to be awake." (Inbound is fine — Telegram retains getUpdates ~24h.)
2. **Dead-man switch — IMPOSSIBLE.** The review's #1 failure mode (silent coach death) can't
   be surfaced: the only always-on compute is the Mac, and a dead Mac can't announce it's
   dead. No non-Mac party runs our code to notice the silence.
3. **Decay telemetry — DEGRADED.** Bots get no delivery/read receipts — only reply +
   inline-button-tap. "Unread," "unreachable," and "read-but-silent" collapse to one bucket
   → the decay model can misread unreachability as disengagement.
4. **Privacy — DOWNGRADED.** All content transits Telegram in plaintext to them (bot chats
   not E2E). CloudKit path is devices ↔ user's private iCloud ↔ Anthropic only.
5. **Onboarding + US reach** — install Telegram / make account / find bot / paste token, on
   a platform many US users don't have; vs CloudKit "install app, already signed into
   iCloud."
6. **Notification-layer restraint** — can't enforce interruption-level discipline (never
   time-sensitive, respect Focus); inherits the user's Telegram settings.

**NOT lost:** real push, two-way chat, quick-reply buttons, lock-screen reply, Watch
glance (mirroring), inbound durability while Mac asleep.

**Synthesis:** "Telegram-only" implicitly = "Mac is the compute," and the Mac sleeps. The
recurring requirement across every option is *always-on programmable compute somewhere*;
only two portable answers exist — the phone (CloudKit, $99, works for every user) or a home
server (Debian box, free, personal-only). Telegram is neither; it rides on whichever compute
you pick. So a ~200-line Telegram relay on the user's Debian box restores losses #1 and #2
**for the user personally** (free, private-enough) — but neither reliability guarantee
reaches *other* users until the CloudKit companion exists. The $99 buys the always-on
compute that makes "proactive" true for people who don't run servers, not a nicer bubble.
Recommended: Telegram (± Debian relay) to prove the coach is worth building; CloudKit
companion for the product-grade heartbeat.

---

## Addendum 6 (same day): free-tier compute + self-signing — dead-ends documented

**Free cloud relay (no Apple fee) restores what Telegram-only lost.** The "always-on
compute" role is a dumb Telegram-bot relay, not an iOS app — free tiers host it with zero
Apple involvement: Cloudflare Workers + Cron Triggers + KV (cleanest — serverless, cron
fires scheduled sends + checks heartbeat staleness, free tier dwarfs coach volume), Oracle
"Always Free" ARM VM, or GCP e2-micro always-free. AVOID AWS free tier (12-mo then bills)
and idle-spindown PaaS (Render/Railway). One relay can serve all users (one bot, many
chat_ids) → more portable than the Debian box. **Consequence: $99/CloudKit comes OFF the
reliability critical path** — it demotes to a privacy + telemetry + polish upgrade.
CloudKit's un-substitutable value = the ONLY path where content never leaves the user's own
iCloud (relay/Telegram paths route content through third parties). Verify current free-tier
terms before committing (knowledge ~Jan 2026).

**Self-signing (free Apple ID) does NOT rescue a native app.** You CAN sideload your own app
to your own phone free (Personal Team; 7-day re-sign treadmill, AltStore automates; 3-app
cap) — but a Personal Team CANNOT provision Push (APNs) or iCloud/CloudKit entitlements, the
two the companion is built on. Steelman (relay-poll + free local notifications + overnight
`BGAppRefreshTask` to set a precise local notif) ALMOST works — local notifications are free
and precise, and the background pull only needs to land in the ~9h draft→fire window — but
breaks on: (1) `BGAppRefreshTask` is opportunistic and STARVES for users who don't open the
app = exactly the disengaged users the coach targets; (2) no remote push = no timely inbound;
(3) 7-day re-sign = personal-only, non-portable. Verdict: self-signing = a UI sketchpad
(prototype native SwiftUI on your own phone pre-$99), NOT a working channel. Telegram beats
it on every axis by borrowing a heavily-used app's push for free.
