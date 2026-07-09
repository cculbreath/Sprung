# Discovery Cluster — "Tool, Not Toy": Integration Vision & Execution Plan

*Resolves the parked D-Strat decision (`plans/deferred_prompts/discovery-cluster-tool-not-toy.md`). Written 2026-07-08 against live source (three read-only source maps: the job-focus/deep-link substrate, the Discovery shell + contacts wiring, and the opportunity-workspace / relationship-join grounding). Decides the **product shape** of the Discovery cluster and its integration with the Resume Customizer, then gives a wave-structured build plan. Reconciles against the three prior docs — `discovery-module-vision-plan.md`, `discovery-module-parallel-execution-plan.md`, `discovery-product-audit-2026-07-06.md` — now **largely executed**; §0 states what actually shipped so this targets real code.*

**Ratified 2026-07-08 (developer):** shape approved. Contacts = **fold, not cut** (cut deferred out of the in-flight UX Wave 3; D-Strat owns it). Pipeline = **keep the board, hub the card**. Build the D-waves only after the in-flight UX refactor's Discovery waves (2, 3) land. See §11.*

---

## 0. Reconciliation — what already shipped, and what's still missing

The 2026-07-06 subtract-and-wire pass **landed**: `DiscoveryMainView` deleted (all main-window modules via `ModuleContentView.swift:19-46`); Sources tab gone; Scout **and** job-board Search re-homed onto the Pipeline header (`PipelineView.swift:70,76,174-214`); MCP boards import `.new` leads; the daily-task loop carries `relatedJobAppId/ContactId/EventId` (`DiscoveryModels.swift:89-91`), navigates (`DailyView.openRelated:449-460`), and writes back on completion (`:432-445`); the events→contacts→follow-up loop is fully wired.

**So the "toy" feeling is no longer internal dishonesty — that's fixed. It's that the cluster is a set of *dashboards about a job search* that never connect to *the work the search is made of*.** Two concrete deficits, and they are different in cost:

1. **The document edges exist but aren't wired.** `JobApp` already holds the packet (`resumes`/`coverLetters`, `:120-123`), stage (`status`, `:175`), and links (`jobApplyLink`/`postingURL`, `:169-171`); docs are UUID-addressable; `focusedTab` can aim the Studio at a phase. Yet the Pipeline card shows company·position·source·days·priority and **nothing** about the packet, with no route into the Studio (`PipelineView.swift:341-459`). This is *wiring* — cheap.
2. **The relationship edges don't exist at all.** There is **no** join from a contact or an event to an opportunity. `NetworkingContact.linkedJobAppIds` / `isAtTargetCompany` / `isRecruiter` / `isHiringManager` were never built (grep: zero). There is no first-class Company entity — "company" is free-text `String` on `JobApp.companyName` (`:154`) and `NetworkingContact.company` (`NetworkingModels.swift:270`). Event prep even passes `focusCompanies: []` (`DiscoveryCoordinator.swift:644`), so it researches target companies from scratch instead of from *your pipeline*. This is *building the missing edges of the opportunity graph* — real work, and it's where the "meat and integration" actually lives.

The only cross-object relationship join that exists today is **event ↔ contact** via `metAtEventId` (`DebriefView.swift:490,539`). Everything else company-keyed must be built.

---

## 1. The integrating concept — three lenses over one opportunity

> **The opportunity (`JobApp`) is the unit of work, and a tool gives it a *home* that shows its whole state and lets you act on all of it. Today that state is scattered: the packet lives in the Customizer, the stage in a Pipeline card, the people in a dead Contacts list, the next action in Daily. The "toy" is four windows onto one object that never look at each other. The "tool" is three deliberate lenses over that one object, each routing into the others.**

```
        MAP                            WORKSPACE                           AGENDA
   (all opportunities)             (one opportunity)                (next action, all opps)
  ┌───────────────────┐        ┌───────────────────────┐         ┌────────────────────┐
  │  PIPELINE board   │        │  CUSTOMIZER =         │         │  DAILY + COACHING  │
  │  funnel stages    │  open  │  the opportunity      │  "do X  │  today's plan,     │
  │  hubbed cards ────┼──────► │  workspace:           │  next"  │  each item deep-   │
  │  Scout / Search   │        │   • posting (Listing) │ ◄───────┼─ links into the    │
  │  (funnel input)   │ ◄──────┤   • packet (Résumé/CL)│  advance│  workspace at the  │
  └───────────────────┘ stage  │   • submit            │  stage  │  right doc         │
                                │   • PEOPLE facet      │         │  coach reasons     │
                                │   • EVENTS facet      │         │  across the graph  │
                                │   • status rail       │         └────────────────────┘
                                └───────────────────────┘
                        ── one JobApp / opportunity object throughout ──
```

**The workspace already half-exists — that's why this is grounded, not a rebuild.** The Customizer is *already* a two-column opportunity workspace: a sidebar of opportunities grouped by pipeline stage (`SidebarView.swift:29-46`) + a phased detail pane (`AppWindowView` tabs `.listing/.resume/.coverLetter/.submitApp`). The `.listing` phase is **already the opportunity's info hub** (`JobAppDetailView`: header + posting details + description + ApplySection). What it lacks to become a real workspace is exactly the two missing things from §0: a **persistent status rail** across phases (there's no per-job header spanning phases today — `ResumeBannerView` is résumé-phase-only) and the **people/events facets** (which need the graph edges built). Name it accordingly — this is what the F4 "Packet Preparation" rename was reaching for: not a résumé editor, the opportunity's home.

The three lenses map cleanly onto existing surfaces, so nothing is orphaned:

| Lens | Surface | Its job |
|---|---|---|
| **MAP** | Pipeline board (+ Scout/Search input) | see the whole funnel; route into a workspace |
| **WORKSPACE** | Customizer, extended | everything about one opportunity; where value is built |
| **AGENDA** | Daily + Coaching | what to do next across all opportunities; route into workspaces |

The daily-task loop is the **wiring between lenses** and already exists (`DailyTask.related{JobApp,Contact,Event}Id` → `openRelated`). The seams (§4) give it richer places to point.

---

## 2. The through-line — a day in the tool (Q1)

Concrete, so the integration is legible, not abstract. Every **bolded noun** is a deep-link or a real object edge:

> You open **Daily**. The coach's delta opener (already built) says: *"3 leads have sat in **New** for 6 days; you have a meetup **Thursday** whose attendees likely include people from **Anthropic** — where you have an open lead; and your follow-up to **Sarah** (met at last month's event) is 2 days overdue."* Today's plan lists **"Customize Anthropic"** → you tap it and land **in the workspace, Résumé phase, on the draft that's already started** (S1 deep-link). You finish the packet, hit **Submit** — the opportunity **auto-advances to Submitted** on the board (S3). Back on **Daily**, **"Prep for Thursday's meetup"** opens event prep whose **target companies are drawn from your own pipeline** (S5), and shows **which of your open opportunities have people you might meet there** (S4). You tap **"Follow up with Sarah"**; it opens her detail from **the Stripe opportunity she's attached to** (S4), you log the touch, the nag clears, warmth updates (already wired).

Nothing in that paragraph is a new app mode. It's the same objects the app already has, finally connected: the packet routes to the board (S3), the board routes to the packet (S1), the events route to the pipeline (S5), the people route to the opportunities (S4), and the agenda routes to all of them (existing loop, richer targets).

---

## 3. Surfaces — survive / sharpen / fold (Q2)

| Surface | Fate | Role after |
|---|---|---|
| **Pipeline** | **Survive, sharpen** | The MAP. Card becomes a hub (§4 S1). Board kept; overflow fixed cheaply (§5). |
| **Customizer** | **Survive, become the WORKSPACE** | Gains a persistent status rail + people/events facets; inbound per-doc deep-links; submit→advance. The deep module absorbs the integration. |
| **Daily + Coaching** | **Survive, become the AGENDA** | The cockpit. Already cross-opportunity; deepens by deep-linking each item into the workspace and by reasoning over the now-connected graph (§4 S6). |
| **Events** | **Survive, connect** | Networking thread top; gains a real edge to the pipeline (S5). |
| **Scout / Search** | **Survive (done)** | Funnel input on the Pipeline header. |
| **Weekly Review** | **Survive** | Reflection loop. No change. |
| **Contacts** | **FOLD, do not cut** | Kill the flat-CRM tab; **keep** model/store/loop; people re-home as a **facet built on a real company-join** (S4). |

**The Contacts fold is now backed by a specific build, not a hand-wave.** A full cut guts the follow-up loop (contacts feed `getDailyTaskContext` → `DailyTaskGenerator` → DailyView, with completion write-back). But the standalone *tab* is genuinely a toy — a flat list disconnected from the opportunities and events the people belong to. The fold replaces it with the **people facet** on the workspace, which requires building the contact↔opportunity edge (S4) that doesn't exist yet. That build **is** the fold's substance.

---

## 4. The integration — six seams in three tiers

Honest tiering by cost, because "wire the docs" and "build the graph edges" are not the same size.

### Tier 1 — wire the document edges (they already exist; cheap, high-value)

- **S1 · Pipeline card-hub.** Card surfaces the opportunity's packet as first-class deep-links: each résumé and cover letter opens the workspace at its phase *with that exact version selected* (`focusedTab = .resume/.coverLetter` **and** `selectedResId/selectedCoverId` set — grounded: pickers enumerate by UUID in `ResumeBannerView.swift:47-101` / `CoverLetterPicker.swift`). Disclosure when multiple; badge = collapsed state. Plus editor deep-link, external apply/posting links, "Open in Studio."
- **S2 · Lead → "Start a Packet."** From a `.new` lead card, one action creates/opens a résumé and lands the Résumé phase — the missing *forward* edge from triage into the deep workflow.
- **S3 · Submit → auto-advance stage.** Submitting in the workspace advances `JobApp.status` → `.submitted` (dates already stamped by `JobAppStore.setStatus:371`) — the missing *backward* edge from the workflow to the map.
- **S1r · Opportunity status rail.** A slim, phase-persistent rail in the workspace (attach above `AppWindowView.tabPickerBar`, or as a third trailing column) showing stage, apply/posting links, and doc counts — all real `JobApp` fields. This is the workspace's identity/state header that doesn't exist today.

### Tier 2 — build the missing relationship edges (this is the "meat")

- **S4 · People ↔ opportunity (the Contacts fold's real substance).** Build the join: match `NetworkingContact.company` to `JobApp.companyName` (extend the existing `getContactsAtCompanies` exact-match at `DiscoveryContextProvider.swift:259-280` into a reusable, case/whitespace-normalized store query), **and/or** add an explicit `linkedJobAppIds` link a user can set. Surface "people at this company" on the workspace people facet; `ContactDetailSheet` becomes reachable from there (and stays reachable from Daily). Decision on the join mechanism → §11 Q-E.
- **S5 · Events ↔ opportunity.** Feed `JobApp.companyName`s from the active pipeline into `performEventPrep`'s `focusCompanies` (today `[]`, `DiscoveryCoordinator.swift:644`) so prep is grounded in *your* search, and surface on the workspace which upcoming events touch this company (same company-match layer as S4). Ready injection point; no model change required for the prep side.

### Tier 3 — the payoff (why the connected graph is a tool, not a tracker)

- **S6 · Cross-opportunity intelligence.** The coach and `DailyTaskGenerator` already ingest pipeline + contacts + events + time; they just reason over a graph with missing edges. Once S4/S5 exist, the agenda can say "this stale lead is at a company where you *know someone* / have an *event Thursday*" — turning generic nudges into opportunity-aware ones. This is mostly *context assembly* (feed the new joins into the existing prompt builders), not new UI — the highest leverage-per-line in the plan, and it's unlocked only by Tier 2.

---

## 5. Pipeline board shape (Q2 sub) — RATIFIED: keep the board, hub the card

Ground truth: `ScrollView(.horizontal)` of fixed-`280` columns (`PipelineView.swift:100,332`) × up to 9 statuses ≈ 2,050pt inside a 620pt floor (`PipelineModuleView.swift:22`) — it overflows. **Keep the board** (glanceable whole-funnel is real MAP value); fix overflow cheaply by collapsing terminal columns (`rejected`/`withdrawn`) behind a toggle and letting the pane own a clean horizontal scroll. Reshaping to a list is a speculative rebuild the anti-goals forbid — the empty card was the problem, not the board. *(The low-risk width fix belongs to the in-flight UX Wave 2; S1's hub content is D-Strat's — §11.)*

---

## 6. The daily-task loop's role (Q4)

Unchanged in shape, central in role. It already carries related ids, navigates, and writes back. Integration **deepens** it: S1's deep-link makes a "customize/submit" task land *in the workspace at the right doc*; S6 makes its generator opportunity-aware. No parallel loop is added.

---

## 7. What genuinely gets built vs. reused (honesty ledger)

| Piece | Reuse or build |
|---|---|
| Packet, stage, apply/posting links on `JobApp` | **Reuse** (real) |
| Deep-link substrate (`.selectJobApp` + `focusedTab`) | **Extend** (small: add doc-id + tab to payload) |
| Event ↔ contact join (`metAtEventId`) | **Reuse** (real) |
| Daily cross-object cockpit | **Reuse** (real) |
| Opportunity status rail across phases | **Build** (no per-job header spans phases today) |
| People ↔ opportunity join | **Build** (company string-match layer and/or link field — no join today) |
| Event ↔ opportunity | **Build** (wire `focusCompanies`; reuse the S4 match layer) |
| Company as an entity | **Not building one** — string-match on `companyName`; revisit only if fuzziness bites |

---

## 8. Execution plan (wave-structured, for `/tackleplan` → `/tackle`)

Edit-only agents, one owner per file, main-session builds at each checkpoint (house rules; no parallel builds). Gated on §11 ratification; start **after** the in-flight UX refactor's Discovery waves (2, 3) land, to avoid `PipelineView.swift` / shell contention.

**Wave D0 — Deep-link substrate + status rail (serial; shared-shell + workspace).**
A nav helper `openStudio(job:tab:resumeId:coverLetterId:)` (extend `.selectJobApp` payload with `tab`/`resumeId`/`coverLetterId`; receiver sets `selectedResId/selectedCoverId + focusedTab` before `selectModule(.resumeEditor)`), and the phase-persistent **status rail** (S1r) in `AppWindowView`. Files: `UnifiedJobFocusState.swift`, `PipelineModuleView.swift`, `ResumeEditorModuleView.swift`, `AppWindowView.swift`, nav service, `MenuCommands.swift`.

**Wave D1 — Card-hub (S1) + loop-closers (S2, S3).** `PipelineView.swift` (card renders packet deep-links via D0 helper; `.new` lead → "Start a Packet"); Submit-phase path (S3 auto-advance). After UX Wave 2.

**Wave D2 — The graph edges (S4 people ↔ opportunity, S5 events ↔ opportunity).** The company-match layer (reusable normalized query on `NetworkingContactStore`, optional `linkedJobAppIds` link field + migration), the workspace **people facet** + **events facet**, and wiring `JobApp.companyName`s into `performEventPrep.focusCompanies`. Files: `NetworkingModels.swift` (+ migration if link field), `NetworkingContactStore.swift`, `DiscoveryContextProvider.swift`, `DiscoveryCoordinator.swift`, the workspace facet views. **This is the meat wave.**

**Wave D3 — Contacts fold + cross-opportunity intelligence (S6).** Remove the standalone Contacts tab (`AppModule.contacts`, icon slot, `ModuleContentView` route, `ContactsModuleView`); re-home `ContactDetailSheet` onto the workspace people facet (D2) + Daily; feed the new joins into `CoachingContextBuilder` / `DailyTaskGenerator` context so the agenda is opportunity-aware. Grep tab symbols → zero; grep loop inputs → unchanged.

---

## 9. Anti-goals (from the D-Strat prompt)
- Don't polish Pipeline styling / fix its scroll / build the hub before the shape is ratified (that's the toy-polishing trap; the scroll fix is UX Wave 2's).
- Don't preserve a surface just because it exists — but the code proves Contacts' loop earns its keep (fold, don't cut).
- Don't add a first-class Company entity, new agents, or new chat surfaces on spec — string-match the join, reuse the existing coach/loop, and only escalate if fuzziness or scale demands it.
- Don't treat this as a coat-of-paint pass — it's the "real workflow that adds real value" question, answered by connecting the graph, not repainting the nodes.

---

## 10. Not in scope
Contact-CRM depth beyond the workspace people facet; a Company `@Model` entity; fuzzy company-name resolution (start exact/normalized); any surface that isn't one of the three lenses.

---

## 11. Developer decisions — ratified 2026-07-08

| # | Question | Decision |
|---|---|---|
| **Q-A** | Contacts: cut, narrow, or fold? | **RATIFIED — fold** (cut deferred out of UX Wave 3; D-Strat Wave D3 owns tab-removal + people-facet re-home together) |
| **Q-B** | Pipeline: board or list? | **RATIFIED — keep the board, hub the card** (§5) |
| **Q-C** | Build now or defer? | **RATIFIED — ratify now, build after the UX refactor's Discovery waves (2, 3) land** |
| **Q-D** | S3 submit hook | **Open (build-time)** — verify the Submit/`SubmittedPacket` path has one clean "submitted" event for the auto-advance |
| **Q-E** | Where does the workspace live, and how is the people/events join keyed? | **Proposed (needs confirm):** workspace = **extend the Customizer** (not a new surface); join = **normalized `companyName` string-match**, optional user-set `linkedJobAppIds` for overrides. Confirm before Wave D2. |
