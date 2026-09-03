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
                for index in offsets { WayStore.shared.delete(id: ways[index].id) }
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
                ways.forEach { WayStore.shared.delete(id: $0.id) }
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Their voices and photos leave this phone. Your own walks are untouched.")
        }
    }

    private func reload() {
        WayStore.shared.sweepExpired(now: Date())
        ways = WayStore.shared.list()
        details = Dictionary(uniqueKeysWithValues: ways.map { ($0.id, detail(for: $0)) })
    }

    private func detail(for way: Way) -> String {
        let date = DateFormatter.localizedString(from: way.departedAt, dateStyle: .medium, timeStyle: .none)
        if way.voiceCount + way.photoCount > 0, !WayStore.shared.hasMedia(id: way.id) {
            return "\(date) · voices returned to the trail"
        }
        let mb = String(format: "%.1f MB", Double(WayStore.shared.diskUsage(id: way.id)) / 1_000_000)
        return "\(date) · \(mb)"
    }
}
