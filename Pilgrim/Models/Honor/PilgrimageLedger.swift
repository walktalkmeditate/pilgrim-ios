import Foundation

/// What the engine had to say about a stage when the walk ended. Captured
/// before teardown, because the engine is gone by the time the walk is saved.
struct HonorStageOutcome: Equatable {
    let progressFrac: Double
    let arrived: Bool
}

/// The per-route record of stages walked. It outlives the package: Replace
/// and Remove take the stages, never this file, so a route that comes back
/// finds its record.
struct PilgrimageLedger: Codable, Equatable {

    struct Entry: Codable, Equatable {
        /// The stage's identity across an update, with `distanceKm`.
        let name: String
        let distanceKm: Double
        var walkedAt: Date
        var kmWalked: Double
        var completed: Bool
        var stoppedAtFrac: Double?
    }

    struct Next: Equatable {
        let index: Int
        /// Where a partial stage stopped, so the overview opens with the
        /// camera there. Nil for a stage never begun.
        let resumeFrac: Double?
    }

    let routeId: String
    /// Keyed by stage index as a string, the shape the file on disk carries.
    var stages: [String: Entry]
    /// Kilometres from entries a redraw dropped, so the total never shrinks
    /// under the walker.
    var carriedKm: Double?
    /// Set by `reconciled(against:)`; the route view says so once.
    var redrawNoticePending: Bool?

    init(routeId: String, stages: [String: Entry] = [:], carriedKm: Double? = nil, redrawNoticePending: Bool? = nil) {
        self.routeId = routeId
        self.stages = stages
        self.carriedKm = carriedKm
        self.redrawNoticePending = redrawNoticePending
    }

    /// Non-finite values would reach a formatter and, through `Int(_:)`, a
    /// trap; a ledger read off disk is as untrusted as any other file.
    var totalKmWalked: Double {
        let walked = stages.values.map(\.kmWalked).filter(\.isFinite).reduce(0, +)
        return walked + ((carriedKm?.isFinite ?? false) ? carriedKm! : 0)
    }

    var completedCount: Int { stages.values.filter(\.completed).count }

    // MARK: - Writing

    mutating func record(stageIndex: Int, name: String, distanceKm: Double, outcome: HonorStageOutcome, at date: Date) {
        let frac = min(max(outcome.progressFrac.isFinite ? outcome.progressFrac : 0, 0), 1)
        let km = distanceKm.isFinite ? max(0, distanceKm) : 0
        let key = String(stageIndex)
        let existing = stages[key]
        // A second, shorter walk of the same stage never un-walks it: the
        // ledger keeps the best the pilgrim has done.
        let completed = outcome.arrived || (existing?.completed ?? false)
        let walkedKm = max(completed ? km : km * frac, existing?.kmWalked ?? 0)
        stages[key] = Entry(
            name: name, distanceKm: km, walkedAt: date, kmWalked: walkedKm,
            completed: completed, stoppedAtFrac: completed ? nil : frac)
    }

    // MARK: - Reading

    /// The first stage without a completed entry, resumed where it stopped.
    /// Nil when every stage is walked — the row then reads
    /// "you have walked the whole way" and offers the first stage again.
    func next(stageCount: Int) -> Next? {
        guard stageCount > 0 else { return nil }
        for index in 0..<stageCount where stages[String(index)]?.completed != true {
            return Next(index: index, resumeFrac: stages[String(index)]?.stoppedAtFrac)
        }
        return nil
    }

    /// "stage 5 of 33 · 112 km walked", in the walker's own distance unit.
    static func progressLine(ledger: PilgrimageLedger?, stageCount: Int) -> String {
        guard let ledger, !ledger.stages.isEmpty || (ledger.carriedKm ?? 0) > 0 else {
            return stageCount == 1 ? "1 stage" : "\(stageCount) stages"
        }
        let walked = StatsHelper.string(for: ledger.totalKmWalked * 1000, unit: UnitLength.meters, type: .distance)
        guard let next = ledger.next(stageCount: stageCount) else {
            return "you have walked the whole way · \(walked)"
        }
        return "stage \(next.index + 1) of \(stageCount) · \(walked) walked"
    }

    // MARK: - Across an update

    static let identityToleranceRatio = 0.05

    /// An entry survives an update only if the new package's stage at that
    /// index has the same name and a `distanceKm` within 5%. What is dropped
    /// leaves its kilometres behind in `carriedKm`.
    func reconciled(against newStages: [PilgrimageRouteStage]) -> PilgrimageLedger {
        let byIndex = Dictionary(newStages.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        var kept: [String: Entry] = [:]
        var dropped = 0.0
        for (key, entry) in stages {
            guard let index = Int(key), let fresh = byIndex[index], fresh.name == entry.name,
                  entry.distanceKm > 0, fresh.distanceKm.isFinite,
                  abs(fresh.distanceKm - entry.distanceKm) / entry.distanceKm <= Self.identityToleranceRatio else {
                dropped += entry.kmWalked.isFinite ? entry.kmWalked : 0
                continue
            }
            kept[key] = entry
        }
        guard dropped > 0 else {
            return PilgrimageLedger(routeId: routeId, stages: kept,
                                    carriedKm: carriedKm, redrawNoticePending: redrawNoticePending)
        }
        return PilgrimageLedger(routeId: routeId, stages: kept,
                                carriedKm: (carriedKm ?? 0) + dropped, redrawNoticePending: true)
    }
}

/// The one place that decides whether a walk earned a ledger entry.
enum PilgrimageLedgerWriter {

    /// Nil when the engine never anchored on the Way — Begin's frac-0
    /// fallback means the walker was still approaching, and an approach is
    /// not a stage walked.
    static func entry(stage: WayStage, outcome: HonorStageOutcome?)
        -> (index: Int, name: String, distanceKm: Double, outcome: HonorStageOutcome)? {
        guard let outcome else { return nil }
        return (stage.index, stage.name, stage.distanceKm, outcome)
    }
}

/// `Ways/pilgrimage/<route-id>/ledger.json`.
final class PilgrimageLedgerStore {

    private let store: WayStore
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(store: WayStore = .shared) {
        self.store = store
    }

    func load(routeId: String) -> PilgrimageLedger? {
        guard let url = store.pilgrimageDirectory(for: routeId)?.appendingPathComponent("ledger.json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(PilgrimageLedger.self, from: data)
    }

    func save(_ ledger: PilgrimageLedger) {
        guard let dir = store.pilgrimageDirectory(for: ledger.routeId) else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? encoder.encode(ledger).write(to: dir.appendingPathComponent("ledger.json"), options: .atomic)
    }

    /// The one place a stage walk reaches its route's ledger, reached from the
    /// walk's own save and from a crash recovery alike. Silent for a walk whose
    /// engine never anchored on the Way — an approach is not a stage walked.
    func record(stage: WayStage, outcome: HonorStageOutcome?, at date: Date) {
        guard let written = PilgrimageLedgerWriter.entry(stage: stage, outcome: outcome) else { return }
        var ledger = load(routeId: stage.routeId) ?? PilgrimageLedger(routeId: stage.routeId)
        ledger.record(stageIndex: written.index, name: written.name,
                      distanceKm: written.distanceKm, outcome: written.outcome, at: date)
        save(ledger)
    }

    func clearRedrawNotice(routeId: String) {
        guard var ledger = load(routeId: routeId), ledger.redrawNoticePending == true else { return }
        ledger.redrawNoticePending = nil
        save(ledger)
    }
}
