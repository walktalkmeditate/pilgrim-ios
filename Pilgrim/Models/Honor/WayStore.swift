import Foundation

struct WayLink: Codable, Equatable {
    let wayId: String
    /// The companion's timeline at arrival, recorded by the engine; nil when
    /// the walk ended before the end of the Way.
    let theirSeconds: Double?
    let yourSeconds: Double?
}

/// Application Support/Ways: one folder per Way, an index from walk UUID to
/// Way id, and the sharer's-promise sweep. The whole tree is excluded from
/// iCloud backup so a restore can never resurrect swept voices.
final class WayStore {

    static let shared: WayStore = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return WayStore(baseDirectory: appSupport.appendingPathComponent("Ways", isDirectory: true))
    }()

    private let fileManager = FileManager.default
    private let base: URL
    /// Injectable so tests can advance "now" deterministically instead of
    /// racing `iso8601`'s whole-second precision with real sleeps.
    private let now: () -> Date
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private struct Accepted: Codable { let acceptedAt: Date }

    init(baseDirectory: URL, now: @escaping () -> Date = Date.init) {
        base = baseDirectory
        self.now = now
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        var url = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: - Ways

    /// Ids are built by code (`share:` + a validated share id, `walk:` + a
    /// UUID). The store still refuses anything else so a stray folder name or
    /// a future caller can never turn an id into a path outside `Ways/`.
    static func isValidId(_ id: String) -> Bool {
        id.range(of: "^(share:[A-Za-z0-9_-]{10}|walk:[0-9A-Fa-f-]{36})$", options: .regularExpression) != nil
    }

    func save(_ way: Way) throws {
        guard Self.isValidId(way.id) else { throw CocoaError(.fileWriteInvalidFileName) }
        let dir = directory(for: way.id)
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoder.encode(way).write(to: dir.appendingPathComponent("way.json"), options: .atomic)
        let accepted = dir.appendingPathComponent("accepted.json")
        if !fileManager.fileExists(atPath: accepted.path) {
            try encoder.encode(Accepted(acceptedAt: now())).write(to: accepted, options: .atomic)
        }
    }

    func load(id: String) -> Way? {
        guard Self.isValidId(id) else { return nil }
        guard let data = try? Data(contentsOf: directory(for: id).appendingPathComponent("way.json")) else { return nil }
        return try? decoder.decode(Way.self, from: data)
    }

    func acceptedAt(id: String) -> Date? {
        guard Self.isValidId(id) else { return nil }
        guard let data = try? Data(contentsOf: directory(for: id).appendingPathComponent("accepted.json")),
              let accepted = try? decoder.decode(Accepted.self, from: data) else { return nil }
        return accepted.acceptedAt
    }

    func list() -> [Way] {
        let ids = (try? fileManager.contentsOfDirectory(atPath: base.path)) ?? []
        return ids.filter(Self.isValidId).compactMap { load(id: $0) }
            .sorted { (acceptedAt(id: $0.id) ?? .distantPast) > (acceptedAt(id: $1.id) ?? .distantPast) }
    }

    func delete(id: String) {
        guard Self.isValidId(id) else { return }
        try? fileManager.removeItem(at: directory(for: id))
        var index = loadIndex()
        index = index.filter { $0.value.wayId != id }
        saveIndex(index)
    }

    // MARK: - Media

    /// No `isValidId` guard here: only callers that already hold a Way id
    /// loaded from disk or a stored `WayLink` reach these, so `directory(for:)`'s
    /// precondition is the correct last line of defense against a bad id.
    func mediaDirectory(for id: String) -> URL {
        directory(for: id).appendingPathComponent("media", isDirectory: true)
    }

    func mediaURL(for id: String, relative: String) -> URL {
        mediaDirectory(for: id).appendingPathComponent(relative)
    }

    func hasMedia(id: String) -> Bool {
        guard Self.isValidId(id) else { return false }
        let contents = (try? fileManager.contentsOfDirectory(atPath: mediaDirectory(for: id).path)) ?? []
        return !contents.isEmpty
    }

    func deleteMedia(id: String) {
        guard Self.isValidId(id) else { return }
        try? fileManager.removeItem(at: mediaDirectory(for: id))
    }

    func diskUsage(id: String) -> Int {
        guard Self.isValidId(id) else { return 0 }
        return fileManager.sizeOfDirectory(at: directory(for: id)) ?? 0
    }

    func totalDiskUsage() -> Int {
        list().reduce(0) { $0 + diskUsage(id: $1.id) }
    }

    // MARK: - Replies and the walk index

    func replies(for id: String) -> [Int: String] {
        guard Self.isValidId(id) else { return [:] }
        guard let data = try? Data(contentsOf: directory(for: id).appendingPathComponent("replies.json")),
              let map = try? decoder.decode([String: String].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: map.compactMap { key, value in Int(key).map { ($0, value) } })
    }

    func setReply(wayId: String, originN: Int, relativePath: String) throws {
        guard Self.isValidId(wayId) else { throw CocoaError(.fileWriteInvalidFileName) }
        var map = replies(for: wayId)
        map[originN] = relativePath
        let encodable = Dictionary(uniqueKeysWithValues: map.map { (String($0.key), $0.value) })
        try encoder.encode(encodable).write(to: directory(for: wayId).appendingPathComponent("replies.json"), options: .atomic)
    }

    func link(walkUUID: UUID, to wayId: String, arrival: (theirSeconds: Double, yourSeconds: Double)?) throws {
        guard Self.isValidId(wayId) else { throw CocoaError(.fileWriteInvalidFileName) }
        var index = loadIndex()
        index[walkUUID.uuidString] = WayLink(wayId: wayId, theirSeconds: arrival?.theirSeconds, yourSeconds: arrival?.yourSeconds)
        saveIndex(index)
    }

    func wayLink(forWalk uuid: UUID) -> WayLink? { loadIndex()[uuid.uuidString] }

    func wayId(forWalk uuid: UUID) -> String? { wayLink(forWalk: uuid)?.wayId }

    func way(forWalk uuid: UUID) -> Way? { wayId(forWalk: uuid).flatMap(load(id:)) }

    private var walkedIds: Set<String> { Set(loadIndex().values.map(\.wayId)) }

    // MARK: - Sweep

    /// Share Ways past their expiry: unwalked → whole folder; walked → media
    /// only. Own-walk Ways never expire. Returns the ids touched.
    @discardableResult
    func sweepExpired(now: Date) -> [String] {
        let walked = walkedIds
        var touched: [String] = []
        for way in list() {
            guard let expires = way.expires, expires <= now else { continue }
            if walked.contains(way.id) {
                deleteMedia(id: way.id)
            } else {
                try? fileManager.removeItem(at: directory(for: way.id))
            }
            touched.append(way.id)
        }
        return touched
    }

    // MARK: - Private

    private func directory(for id: String) -> URL {
        precondition(Self.isValidId(id), "WayStore: invalid way id \(id)")
        return base.appendingPathComponent(id, isDirectory: true)
    }

    private var indexURL: URL { base.appendingPathComponent("index.json") }

    private func loadIndex() -> [String: WayLink] {
        guard let data = try? Data(contentsOf: indexURL) else { return [:] }
        return (try? decoder.decode([String: WayLink].self, from: data)) ?? [:]
    }

    private func saveIndex(_ index: [String: WayLink]) {
        try? encoder.encode(index).write(to: indexURL, options: .atomic)
    }
}
