import Foundation

/// Where a link leads. `unrecognised` is an honor-host address this build
/// can't read, most likely a shape a newer Pilgrim knows, so the walker is
/// told instead of met with silence.
enum HonorLinkDestination: Equatable {
    case share(id: String)
    case stage(routeId: String, index: Int)
    case unrecognised
}

/// The one place a link becomes a destination, for both a universal link
/// the OS hands us and text the walker pasted.
enum HonorLink {

    static let hosts: Set<String> = ["honor.pilgrimapp.org", "walk.pilgrimapp.org"]
    /// Stage links live only where their fallback page does.
    static let stageHost = "honor.pilgrimapp.org"
    private static let idPattern = "\\A[A-Za-z0-9_-]{10}\\z"
    private static let stageNumberPattern = "\\A[1-9][0-9]{0,2}\\z"

    static func parse(_ url: URL) -> HonorLinkDestination? {
        guard let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard !parts.isEmpty else { return nil }
        if parts.count == 1, isID(parts[0]) { return .share(id: parts[0]) }
        guard host == stageHost else { return nil }
        if parts.count == 2, let index = stageIndex(routeId: parts[0], number: parts[1]) {
            return .stage(routeId: parts[0], index: index)
        }
        return .unrecognised
    }

    /// Pasted text that isn't a link Pilgrim can open is simply not a link:
    /// the paste field already has its own way of saying so.
    static func parse(text: String) -> HonorLinkDestination? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isID(trimmed) { return .share(id: trimmed) }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), let link = parse(url), link != .unrecognised else { return nil }
        return link
    }

    private static func isID(_ s: String) -> Bool {
        s.range(of: idPattern, options: .regularExpression) != nil
    }

    /// The link counts stages from 1, as the route screen shows them; the
    /// data counts from 0.
    private static func stageIndex(routeId: String, number: String) -> Int? {
        guard WayStore.isValidRouteId(routeId),
              number.range(of: stageNumberPattern, options: .regularExpression) != nil,
              let n = Int(number), n <= PilgrimageWayImporter.maxStageCount else { return nil }
        return n - 1
    }
}

extension Notification.Name {
    static let pilgrimOpenWay = Notification.Name("pilgrimOpenWay")
}
