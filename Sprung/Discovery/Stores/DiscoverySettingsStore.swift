//
//  DiscoverySettingsStore.swift
//  Sprung
//
//  Store for managing Discovery module settings (UserDefaults-backed).
//

import Foundation

@Observable
@MainActor
final class DiscoverySettingsStore {
    /// Injectable seam for the UserDefaults keys owned by this store.
    /// Defaults to `.standard` in production; tests pass `TestDefaults().store`
    /// so these round-trips never touch the developer's real defaults.
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Event-Discovery Auto-Run State

    /// UserDefaults key for the last SUCCESSFUL networking-event discovery run
    /// (manual or automatic — both funnel through the same completion point).
    /// Failed or cancelled runs never update it.
    private static let lastSuccessfulEventDiscoveryKey = "discoveryLastSuccessfulEventDiscoveryAt"

    var lastSuccessfulEventDiscoveryAt: Date? {
        defaults.object(forKey: Self.lastSuccessfulEventDiscoveryKey) as? Date
    }

    func recordSuccessfulEventDiscovery(at date: Date = Date()) {
        defaults.set(date, forKey: Self.lastSuccessfulEventDiscoveryKey)
    }

    // MARK: - Event-Discovery Auto-Run Toggle + Standing Guidance

    private static let eventDiscoveryAutoRunEnabledKey = "discoveryEventDiscoveryAutoRunEnabled"

    /// Opt-in gate for the unattended weekly networking-event discovery run.
    /// Defaults to `false`: an automatic run at coordinator startup spends real
    /// LLM budget without the user in the loop, so it must be explicitly enabled.
    var eventDiscoveryAutoRunEnabled: Bool {
        get { defaults.bool(forKey: Self.eventDiscoveryAutoRunEnabledKey) }
        set { defaults.set(newValue, forKey: Self.eventDiscoveryAutoRunEnabledKey) }
    }

    private static let eventDiscoveryStandingGuidanceKey = "discoveryEventDiscoveryStandingGuidance"

    /// Standing guidance applied to every automatic weekly run. Manual runs use
    /// their own per-run guidance instead (see `EventsView`'s discover trigger).
    /// Empty means no guidance — the auto run proceeds plain.
    var eventDiscoveryStandingGuidance: String {
        get { defaults.string(forKey: Self.eventDiscoveryStandingGuidanceKey) ?? "" }
        set { defaults.set(newValue, forKey: Self.eventDiscoveryStandingGuidanceKey) }
    }

    // MARK: - Job-Scout Auto-Run Cadence

    /// How often the Job Scout auto-runs at coordinator startup. Defaults to
    /// `.off` — like the events auto-run, unattended LLM spend must be an
    /// explicit opt-in.
    enum ScoutCadence: String, CaseIterable {
        case off
        case daily
        case weekly

        /// Days that must have passed since the last successful run before an
        /// auto-run fires again. Nil = never auto-runs.
        var minimumDaysBetweenRuns: Int? {
            switch self {
            case .off: return nil
            case .daily: return 1
            case .weekly: return 7
            }
        }

        /// Whether enough time has passed since `lastRun` for an auto-run.
        /// A never-run history counts as elapsed (except for `.off`). Same
        /// calendar-day math as the events auto-run guard.
        func hasElapsed(since lastRun: Date?, now: Date = Date()) -> Bool {
            guard let minimumDays = minimumDaysBetweenRuns else { return false }
            guard let lastRun else { return true }
            let days = Calendar.current.dateComponents([.day], from: lastRun, to: now).day ?? 0
            return days >= minimumDays
        }
    }

    private static let scoutAutoRunCadenceKey = "discoveryScoutAutoRunCadence"

    var scoutAutoRunCadence: ScoutCadence {
        get {
            defaults.string(forKey: Self.scoutAutoRunCadenceKey)
                .flatMap(ScoutCadence.init(rawValue:)) ?? .off
        }
        set { defaults.set(newValue.rawValue, forKey: Self.scoutAutoRunCadenceKey) }
    }

    // MARK: - Job-Scout Boards + Run Parameters

    private static let scoutEnabledBoardsKey = "discoveryScoutEnabledBoards"

    /// Boards the scout searches by default (persistent toggles; the run
    /// modal can override per run). Defaults to the no-key boards until the
    /// user saves a choice — the aggregator boards (JSearch/SerpApi) stay off
    /// until the user adds a key, so a keyless install never nags. An
    /// explicitly-saved empty selection persists as empty.
    var scoutEnabledBoards: [JobScoutService.ScoutBoard] {
        get {
            guard let raw = defaults.array(forKey: Self.scoutEnabledBoardsKey) as? [String] else {
                return JobScoutService.ScoutBoard.allCases.filter { !$0.requiresAPIKey }
            }
            return raw.compactMap(JobScoutService.ScoutBoard.init(rawValue:))
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Self.scoutEnabledBoardsKey) }
    }

    private static let scoutStandingGuidanceKey = "discoveryScoutStandingGuidance"

    /// Standing guidance applied to every automatic scout run (manual runs
    /// pre-fill from it but pass their own per-run text). Empty = none.
    var scoutStandingGuidance: String {
        get { defaults.string(forKey: Self.scoutStandingGuidanceKey) ?? "" }
        set { defaults.set(newValue, forKey: Self.scoutStandingGuidanceKey) }
    }

    private static let scoutRecommendationCountKey = "discoveryScoutRecommendationCount"

    /// How many recommendations a scout run may submit. Default 5.
    var scoutRecommendationCount: Int {
        get {
            guard defaults.object(forKey: Self.scoutRecommendationCountKey) != nil else { return 5 }
            return defaults.integer(forKey: Self.scoutRecommendationCountKey)
        }
        set { defaults.set(newValue, forKey: Self.scoutRecommendationCountKey) }
    }

    // MARK: - Job-Scout Run History

    private static let lastSuccessfulScoutRunKey = "discoveryLastSuccessfulScoutRunAt"

    /// The last SUCCESSFUL scout run (manual or automatic — both funnel
    /// through the same completion point). Failed or cancelled runs never
    /// update it.
    var lastSuccessfulScoutRunAt: Date? {
        defaults.object(forKey: Self.lastSuccessfulScoutRunKey) as? Date
    }

    func recordSuccessfulScoutRun(at date: Date = Date()) {
        defaults.set(date, forKey: Self.lastSuccessfulScoutRunKey)
    }

    private static let scoutRunHistoryKey = "discoveryScoutRunHistory"

    /// How many completed runs are retained — enough for the run-history UI and
    /// the outcome-feedback context without unbounded growth.
    static let scoutRunHistoryCap = 10

    /// Durable mirror of `JobScoutService.runHistory` (newest first). The
    /// service holds the observable copy the review UI watches; this is where
    /// it survives relaunches so an unattended run's pending picks aren't lost.
    /// A decode failure reads as empty history (logged, never a crash).
    var scoutRunHistory: [JobScoutService.ScoutRunReport] {
        get {
            guard let data = defaults.data(forKey: Self.scoutRunHistoryKey) else { return [] }
            do {
                return try JSONDecoder().decode([JobScoutService.ScoutRunReport].self, from: data)
            } catch {
                Logger.error("❌ [DiscoverySettings] Couldn't decode the scout run history: \(error.localizedDescription)", category: .data)
                return []
            }
        }
        set {
            let capped = Array(newValue.prefix(Self.scoutRunHistoryCap))
            do {
                let data = try JSONEncoder().encode(capped)
                defaults.set(data, forKey: Self.scoutRunHistoryKey)
            } catch {
                Logger.error("❌ [DiscoverySettings] Couldn't encode the scout run history: \(error.localizedDescription)", category: .data)
            }
        }
    }

    private static let scoutAutoImportStrongMatchesKey = "discoveryScoutAutoImportStrongMatches"

    /// Opt-in: when set, a run auto-imports recommendations whose overall
    /// verdict is `strong`, leaving the rest for review. Defaults to `false` —
    /// curation is the default; nothing enters the pipeline behind the user's
    /// back unless they ask for it.
    var scoutAutoImportStrongMatches: Bool {
        get { defaults.bool(forKey: Self.scoutAutoImportStrongMatchesKey) }
        set { defaults.set(newValue, forKey: Self.scoutAutoImportStrongMatchesKey) }
    }

    // MARK: - Job-Scout Learned Taste Profile

    private static let scoutTasteProfileKey = "discoveryScoutTasteProfile"
    private static let scoutTasteProfileUpdatedAtKey = "discoveryScoutTasteProfileUpdatedAt"
    private static let scoutDecisionsSinceSynthesisKey = "discoveryScoutDecisionsSinceSynthesis"

    /// A few plain sentences the scout distills from the user's accept/dismiss
    /// decisions over time and injects into every run to calibrate what it
    /// surfaces. Empty until enough decisions accrue (or the user writes one).
    /// User-editable in Settings — a manual edit is authoritative.
    var scoutTasteProfile: String {
        get { defaults.string(forKey: Self.scoutTasteProfileKey) ?? "" }
        set { defaults.set(newValue, forKey: Self.scoutTasteProfileKey) }
    }

    /// When the profile was last written (by synthesis or a manual edit).
    var scoutTasteProfileUpdatedAt: Date? {
        get { defaults.object(forKey: Self.scoutTasteProfileUpdatedAtKey) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Self.scoutTasteProfileUpdatedAtKey)
            } else {
                defaults.removeObject(forKey: Self.scoutTasteProfileUpdatedAtKey)
            }
        }
    }

    /// Accept/dismiss decisions recorded since the profile was last synthesized.
    /// The scout re-synthesizes when this crosses its threshold.
    var scoutDecisionsSinceSynthesis: Int {
        get { defaults.integer(forKey: Self.scoutDecisionsSinceSynthesisKey) }
        set { defaults.set(newValue, forKey: Self.scoutDecisionsSinceSynthesisKey) }
    }

    /// Count one review decision toward the next synthesis.
    func recordScoutDecision() {
        scoutDecisionsSinceSynthesis += 1
    }

    /// Install a taste profile (from synthesis or a manual edit): store the
    /// text, stamp the time, and reset the decision counter — both paths mean
    /// "the profile is current as of now."
    func applyTasteProfile(_ text: String, at date: Date = Date()) {
        scoutTasteProfile = text
        scoutTasteProfileUpdatedAt = date
        scoutDecisionsSinceSynthesis = 0
    }

    // MARK: - Job-Scout Dismissed Postings (cross-run memory)

    private static let scoutDismissedPostingsKey = "discoveryScoutDismissedPostings"

    /// Postings the user dismissed in a scout review stay dismissed for this
    /// long; older entries are pruned so a job the user passed on months ago
    /// can surface again if it's still open.
    static let scoutDismissedTTLDays = 60
    /// Hard ceiling on the dismissed set — the oldest are dropped beyond it so
    /// the blob never grows without bound.
    static let scoutDismissedCap = 500

    /// The postings the user dismissed in past scout reviews. Filtered out of
    /// future runs' search results (URL or title+company match) so a rejected
    /// posting stays gone. Pruned on every read and write: entries past the TTL
    /// are dropped and the set is capped oldest-first. A decode failure reads as
    /// an empty set (logged, never a crash).
    var scoutDismissedPostings: [JobScoutService.ScoutDismissedPosting] {
        get {
            guard let data = defaults.data(forKey: Self.scoutDismissedPostingsKey) else { return [] }
            do {
                let stored = try JSONDecoder().decode([JobScoutService.ScoutDismissedPosting].self, from: data)
                return Self.pruneDismissed(stored)
            } catch {
                Logger.error("❌ [DiscoverySettings] Couldn't decode dismissed scout postings: \(error.localizedDescription)", category: .data)
                return []
            }
        }
        set {
            let pruned = Self.pruneDismissed(newValue)
            do {
                let data = try JSONEncoder().encode(pruned)
                defaults.set(data, forKey: Self.scoutDismissedPostingsKey)
            } catch {
                Logger.error("❌ [DiscoverySettings] Couldn't encode dismissed scout postings: \(error.localizedDescription)", category: .data)
            }
        }
    }

    /// Append postings to the dismissed set, deduplicated by URL against what's
    /// already stored. Pruning happens as a side effect of the setter.
    func recordDismissedPostings(_ postings: [JobScoutService.ScoutDismissedPosting]) {
        guard !postings.isEmpty else { return }
        var current = scoutDismissedPostings
        let existingURLs = Set(current.map(\.url).filter { !$0.isEmpty })
        current.append(contentsOf: postings.filter { $0.url.isEmpty || !existingURLs.contains($0.url) })
        scoutDismissedPostings = current
    }

    /// Drop entries past the TTL, then cap the survivors oldest-first. Returns
    /// them in chronological (oldest-first) order for stable storage.
    static func pruneDismissed(
        _ postings: [JobScoutService.ScoutDismissedPosting],
        now: Date = Date()
    ) -> [JobScoutService.ScoutDismissedPosting] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -scoutDismissedTTLDays, to: now) ?? now
        let live = postings.filter { $0.dismissedAt >= cutoff }
        guard live.count > scoutDismissedCap else { return live }
        return live
            .sorted { $0.dismissedAt > $1.dismissedAt }
            .prefix(scoutDismissedCap)
            .sorted { $0.dismissedAt < $1.dismissedAt }
    }
}
