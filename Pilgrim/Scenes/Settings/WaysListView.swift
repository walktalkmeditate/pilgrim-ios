import SwiftUI

struct WaysListView: View {
    @State private var ways: [Way] = []
    /// Computed alongside `ways` in `reload()`, not read live from `WayStore`
    /// in the row: `body` re-runs on every list mutation, and `diskUsage`/
    /// `hasMedia` are filesystem stats per call.
    @State private var details: [String: String] = [:]
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            if ways.isEmpty {
                Text("no ways yet").font(Constants.Typography.caption).foregroundColor(.fog)
            }
            ForEach(ways, id: \.id) { way in
                VStack(alignment: .leading, spacing: 2) {
                    Text(way.title).font(Constants.Typography.body).foregroundColor(.ink)
                    Text(details[way.id] ?? "").font(Constants.Typography.caption).foregroundColor(.fog)
                }
            }
            .onDelete { offsets in
                // A walk that already followed this Way keeps its own route and
                // moments; only the shareable Way folder goes away, so the
                // walk's summary falls back to "a way that has been removed".
                for index in offsets { delete(id: ways[index].id) }
                reload()
            }
            if !ways.isEmpty {
                Button("Delete all Ways", role: .destructive) { confirmDeleteAll = true }
                    .font(Constants.Typography.button)
            }
        }
        .navigationTitle("Ways")
        .onAppear(perform: reload)
        .alert("Delete all Ways?", isPresented: $confirmDeleteAll) {
            Button("Delete", role: .destructive) {
                ways.forEach { delete(id: $0.id) }
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their voices and photos leave this phone. Your own walks are untouched.")
        }
    }

    /// The store stays UI-free, so cancelling the transfers that would
    /// otherwise land in a folder nothing can see or remove belongs here, at
    /// the delete site.
    private func delete(id: String) {
        WayMediaDownloader.shared.cancel(wayId: id)
        WayStore.shared.delete(id: id)
    }

    /// A stage's Way is one file of an installed package: taking it here would
    /// leave `route.json` and `release.txt` behind, and the route screen would
    /// still say the route is on your phone with no stages under it. The route
    /// screen removes a package whole, so this list never offers one — and
    /// "Delete all Ways", which walks this same array, cannot reach one either.
    static func listable(_ ways: [Way]) -> [Way] {
        ways.filter { if case .pilgrimage = $0.source { return false } else { return true } }
    }

    private func reload() {
        for id in WayStore.shared.sweepExpired(now: Date()) { WayMediaDownloader.shared.cancel(wayId: id) }
        ways = Self.listable(WayStore.shared.list())
        details = Dictionary(uniqueKeysWithValues: ways.map { ($0.id, detail(for: $0)) })
    }

    private func detail(for way: Way) -> String {
        let lead = WayStageLine.line(for: way)
            ?? DateFormatter.localizedString(from: way.departedAt, dateStyle: .medium, timeStyle: .none)
        if way.voiceCount + way.photoCount > 0, !WayStore.shared.hasMedia(id: way.id) {
            return "\(lead) · voices returned to the trail"
        }
        let mb = String(format: "%.1f MB", Double(WayStore.shared.diskUsage(id: way.id)) / 1_000_000)
        return "\(lead) · \(mb)"
    }
}
