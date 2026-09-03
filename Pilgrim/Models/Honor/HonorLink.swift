import Foundation

/// The one place a share link becomes a share id, for both a universal link
/// the OS hands us and text the walker pasted.
enum HonorLink {

    static let hosts: Set<String> = ["honor.pilgrimapp.org", "walk.pilgrimapp.org"]
    private static let idPattern = "^[A-Za-z0-9_-]{10}$"

    static func parse(_ url: URL) -> String? {
        guard let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, isID(parts[0]) else { return nil }
        return parts[0]
    }

    static func parse(text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isID(trimmed) { return trimmed }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme) else { return nil }
        return parse(url)
    }

    private static func isID(_ s: String) -> Bool {
        s.range(of: idPattern, options: .regularExpression) != nil
    }
}

extension Notification.Name {
    static let pilgrimOpenWay = Notification.Name("pilgrimOpenWay")
}
