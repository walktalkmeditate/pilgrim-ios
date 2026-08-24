import Foundation

/// A walker's decision to stop noticing a thread. Cohort-scoped: releasing a
/// display term releases every lemma that shared it at release time, and
/// welcome-back restores the cohort atomically. Releasing is wabi-sabi, not
/// deletion — the words remain in their transcripts; the app simply stops
/// noticing.
struct ReleasedThread: Codable, Equatable {
    let displayTerm: String
    let lemmas: [String]
    let releasedAt: Date
}

/// A welcome-back is a decision too, recorded with its date so import merge
/// can honor whichever decision came last. Without the record, a stale
/// backup's release would silently override the walker's later reversal —
/// the spec's reversibility promise has to survive backups.
struct WelcomedBackThread: Codable, Equatable {
    let displayTerm: String
    let welcomedBackAt: Date
}

/// UserDefaults-persisted released set. Releases and welcome-backs are
/// walker decisions, not derived analysis — they survive relaunch, ride in
/// the `.pilgrim` preferences block (the sanctioned carve-out), and Delete
/// All Data clears them with everything else. Analysis and stored contexts
/// are untouched by release, so it is fully reversible.
final class ReleasedThreadsStore {

    static let shared = ReleasedThreadsStore(defaults: .standard)

    static let defaultsKey = "releasedThreads"
    static let welcomedBackKey = "welcomedBackThreads"

    private let defaults: UserDefaults
    private let lock = NSLock()
    private var _changeCount = 0

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Session-scoped memo token, bumped on every mutation — folded into the
    /// dossier-builder and suggestions memo keys so a release is visible on
    /// the very next prompt or sheet open.
    var changeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _changeCount
    }

    /// Newest release first, ties broken by term — the settings list order.
    var all: [ReleasedThread] {
        lock.lock()
        defer { lock.unlock() }
        return loadReleased()
    }

    /// Welcome-back records, term-ascending — exported beside the released
    /// list so import merge can compare decisions by date.
    var welcomedBack: [WelcomedBackThread] {
        lock.lock()
        defer { lock.unlock() }
        return loadWelcomedBack()
    }

    var releasedLemmas: Set<String> {
        Set(all.flatMap(\.lemmas))
    }

    var isEmpty: Bool { all.isEmpty }

    func release(displayTerm: String, lemmas: [String], releasedAt: Date = Date()) {
        mutate { entries, welcomes in
            welcomes.removeAll { $0.displayTerm == displayTerm }
            if let index = entries.firstIndex(where: { $0.displayTerm == displayTerm }) {
                entries[index] = ReleasedThread(
                    displayTerm: displayTerm,
                    lemmas: Set(entries[index].lemmas).union(lemmas).sorted(),
                    releasedAt: entries[index].releasedAt
                )
            } else {
                entries.append(ReleasedThread(
                    displayTerm: displayTerm, lemmas: lemmas.sorted(), releasedAt: releasedAt
                ))
            }
        }
    }

    func welcomeBack(displayTerm: String, at date: Date = Date()) {
        mutate { entries, welcomes in
            entries.removeAll { $0.displayTerm == displayTerm }
            welcomes.removeAll { $0.displayTerm == displayTerm }
            welcomes.append(WelcomedBackThread(displayTerm: displayTerm, welcomedBackAt: date))
        }
    }

    /// Import merge: latest decision wins, per cohort. Two releases union
    /// their lemmas and keep the earlier date so repeated imports stay
    /// stable; a release and a welcome-back for the same term are compared
    /// by date and the older decision yields. On a tie the local state
    /// stands — re-importing the same package is a no-op.
    func merge(released importedReleased: [ReleasedThread],
               welcomedBack importedWelcomedBack: [WelcomedBackThread]) {
        guard !importedReleased.isEmpty || !importedWelcomedBack.isEmpty else { return }
        mutate { entries, welcomes in
            for thread in importedReleased {
                if let welcome = welcomes.first(where: { $0.displayTerm == thread.displayTerm }),
                   welcome.welcomedBackAt >= thread.releasedAt {
                    continue // the walker's welcome-back is the later decision — never silently re-release
                }
                welcomes.removeAll { $0.displayTerm == thread.displayTerm }
                if let index = entries.firstIndex(where: { $0.displayTerm == thread.displayTerm }) {
                    entries[index] = ReleasedThread(
                        displayTerm: thread.displayTerm,
                        lemmas: Set(entries[index].lemmas).union(thread.lemmas).sorted(),
                        releasedAt: min(entries[index].releasedAt, thread.releasedAt)
                    )
                } else {
                    entries.append(thread)
                }
            }
            for welcome in importedWelcomedBack {
                if let entry = entries.first(where: { $0.displayTerm == welcome.displayTerm }),
                   entry.releasedAt >= welcome.welcomedBackAt {
                    continue // released again after that welcome-back — the newer release stands
                }
                entries.removeAll { $0.displayTerm == welcome.displayTerm }
                if let index = welcomes.firstIndex(where: { $0.displayTerm == welcome.displayTerm }) {
                    welcomes[index] = WelcomedBackThread(
                        displayTerm: welcome.displayTerm,
                        welcomedBackAt: max(welcomes[index].welcomedBackAt, welcome.welcomedBackAt)
                    )
                } else {
                    welcomes.append(welcome)
                }
            }
        }
    }

    /// Delete All Data hook — walker decisions clear with everything else.
    func clear() {
        mutate { entries, welcomes in
            entries.removeAll()
            welcomes.removeAll()
        }
    }

    private func mutate(_ body: (inout [ReleasedThread], inout [WelcomedBackThread]) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var entries = loadReleased()
        var welcomes = loadWelcomedBack()
        body(&entries, &welcomes)
        entries.sort { ($0.releasedAt, $1.displayTerm) > ($1.releasedAt, $0.displayTerm) }
        welcomes.sort { $0.displayTerm < $1.displayTerm }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
        if let data = try? JSONEncoder().encode(welcomes) {
            defaults.set(data, forKey: Self.welcomedBackKey)
        }
        _changeCount += 1
    }

    private func loadReleased() -> [ReleasedThread] {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([ReleasedThread].self, from: data) else { return [] }
        return entries
    }

    private func loadWelcomedBack() -> [WelcomedBackThread] {
        guard let data = defaults.data(forKey: Self.welcomedBackKey),
              let entries = try? JSONDecoder().decode([WelcomedBackThread].self, from: data) else { return [] }
        return entries
    }
}
