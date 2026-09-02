import SwiftUI

/// "Choose a way": accepted shares, one of your own walks again, or a pasted link.
struct HonorWaysSheet: View {

    let ownWalks: [Walk]
    let onChoose: (Way) -> Void
    let onPaste: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""
    @State private var showOwnWalks = false
    @State private var acceptedWays: [Way] = []
    /// Computed alongside `acceptedWays` in `onAppear`, not read live from
    /// `WayStore` in `wayRow`: the `TextField` above re-evaluates this body
    /// on every keystroke, and `hasMedia` is a filesystem stat per call.
    @State private var withMedia: Set<String> = []
    @State private var unwalkableAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if acceptedWays.isEmpty {
                        Text("no ways yet. Accept a shared walk, or walk one of yours again.")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                    ForEach(acceptedWays, id: \.id) { way in
                        Button { onChoose(way) } label: { wayRow(way) }
                    }
                } header: {
                    Text("Shared with you").font(Constants.Typography.caption)
                }

                Section {
                    Button { showOwnWalks = true } label: {
                        settingNavRow(label: "Walk one of yours again")
                    }
                } header: {
                    Text("Your own walks").font(Constants.Typography.caption)
                }

                Section {
                    TextField("paste a walk link", text: $pasted)
                        .font(Constants.Typography.body)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Open") { onPaste(pasted) }
                        .font(Constants.Typography.button)
                        .disabled(HonorLinkPreview.shareId(in: pasted) == nil)
                } header: {
                    Text("From a shared walk").font(Constants.Typography.caption)
                } footer: {
                    Text("Any Walk with me page has a \"walk it there\" button.")
                        .font(Constants.Typography.caption)
                }
            }
            .navigationTitle("Choose a way")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .font(Constants.Typography.button)
                        .foregroundColor(.stone)
                }
            }
            .sheet(isPresented: $showOwnWalks) {
                OwnWalkPicker(walks: ownWalks) { walk in
                    guard let way = OwnWalkWayBuilder.make(from: walk) else {
                        unwalkableAlert = true
                        return
                    }
                    onChoose(way)   // dismisses the parent sheet, which takes this nested one with it
                }
                .alert("Can't walk this one again", isPresented: $unwalkableAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("This walk doesn't have enough of a route to follow. Try another.")
                }
            }
            .onAppear {
                WayStore.shared.sweepExpired(now: Date())
                acceptedWays = WayStore.shared.list().filter { if case .share = $0.source { return true } else { return false } }
                withMedia = Set(acceptedWays.filter { WayStore.shared.hasMedia(id: $0.id) }.map(\.id))
            }
        }
    }

    @ViewBuilder
    private func wayRow(_ way: Way) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(way.title)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
            HStack {
                Text(DateFormatter.localizedString(from: way.departedAt, dateStyle: .medium, timeStyle: .none))
                Text("·")
                Text(withMedia.contains(way.id) || way.voiceCount + way.photoCount == 0
                     ? HonorOverviewModel.countsLine(way: way) : "voices returned to the trail")
            }
            .font(Constants.Typography.caption)
            .foregroundColor(.fog)
        }
    }
}

struct OwnWalkPicker: View {
    let onPick: (Walk) -> Void

    /// Computed in `init` from the passed array's stored `distance`
    /// attribute, not in `onAppear`: faulting every walk's `routeData` per
    /// body pass is the O(walks) main-thread cost `HomeViewModel` already
    /// avoids with bulk queries, and `onAppear` ran a frame late, flashing
    /// the empty state before the filter landed.
    private let eligible: [Walk]

    init(walks: [Walk], onPick: @escaping (Walk) -> Void) {
        eligible = walks.filter { $0.distance > 0 }
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            List {
                if eligible.isEmpty {
                    Text("walk somewhere first. Any walk with a route can be walked again.")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                ForEach(eligible, id: \.id) { walk in
                    Button { onPick(walk) } label: { walkRow(walk) }
                }
            }
            .navigationTitle("Walk again")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func walkRow(_ walk: Walk) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title(for: walk))
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
            Text(StatsHelper.string(for: walk.distance, unit: UnitLength.meters, type: .distance))
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }

    private func title(for walk: Walk) -> String {
        if let comment = walk.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            return comment
        }
        return DateFormatter.localizedString(from: walk.startDate, dateStyle: .medium, timeStyle: .none)
    }
}

/// Phase B replaces this with `HonorLink.parse`; until then the paste field
/// only recognizes a bare ten-character id or a walk.pilgrimapp.org URL.
enum HonorLinkPreview {
    static func shareId(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        let pattern = "^[A-Za-z0-9_-]{10}$"
        return candidate.range(of: pattern, options: .regularExpression) != nil ? candidate : nil
    }
}
