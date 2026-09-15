import SwiftUI

enum PilgrimageMapsRowModel {

    static func megabytes(_ bytes: Int) -> String {
        "\(max(1, Int((Double(bytes) / 1_000_000).rounded()))) MB"
    }

    static func label(status: PilgrimageTilesManager.Status, estimateBytes: Int) -> String {
        switch status {
        case .partial(let saved, let of): return "Save maps for the way · \(saved) of \(of) saved"
        case .none, .saved: return "Save maps for the way · ~\(megabytes(estimateBytes))"
        }
    }

    static func savedLine(bytes: Int) -> String { "maps saved · \(megabytes(bytes))" }

    /// `done` and `total` both count the style packs ahead of the stages;
    /// the walker only cares about stages, so both sides drop them.
    static func savingLine(done: Int, total: Int) -> String {
        let packs = StylePackRequest.allCases.count
        return "maps · stage \(max(done - packs, 0)) of \(max(total - packs, 0))"
    }
}

/// Under the route page's download button: one row, driven by the tiles
/// manager's status while idle and by its phase while saving.
struct PilgrimageMapsRow: View {

    let routeId: String
    let stages: [Way]
    /// Computed by the route page when its stages load. The estimate walks
    /// every stage's corridor tile by tile, which is far too much work for a
    /// view body that re-runs on every published change.
    let estimateBytes: Int
    /// Also the route page's: reading it hashes every stage's corridor and
    /// starts a tile-store round trip, so it is refreshed on the store's
    /// own signal rather than on every body pass.
    let status: PilgrimageTilesManager.Status
    @ObservedObject var tiles: PilgrimageTilesManager

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
            switch tiles.phase {
            case .saving(let done, let total):
                HStack(spacing: Constants.UI.Padding.small) {
                    Text(PilgrimageMapsRowModel.savingLine(done: done, total: total))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                    Button("cancel") { tiles.cancel() }
                        .font(Constants.Typography.caption)
                        .foregroundColor(.stone)
                }
            case .idle, .failed:
                idleRow
                if case .failed(let error) = tiles.phase {
                    Text(PilgrimageCopy.line(for: error))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.rust)
                }
            }
        }
    }

    @ViewBuilder
    private var idleRow: some View {
        if case .saved(let bytes) = status {
            Button { Task { await save() } } label: {
                HStack(spacing: Constants.UI.Padding.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.moss)
                        .accessibilityHidden(true)
                    Text(PilgrimageMapsRowModel.savedLine(bytes: bytes))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .accessibilityLabel("maps saved, \(PilgrimageMapsRowModel.megabytes(bytes)). Tap to save again")
        } else {
            Button { Task { await save() } } label: {
                Text(PilgrimageMapsRowModel.label(status: status, estimateBytes: estimateBytes))
                    .font(Constants.Typography.button)
                    .foregroundColor(.stone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.stone.opacity(0.12))
                    .cornerRadius(Constants.UI.CornerRadius.normal)
            }
        }
    }

    private func save() async {
        do {
            try await tiles.save(routeId: routeId, stages: stages)
        } catch {
            // The manager's phase carries the failure; nothing else to keep.
        }
    }
}
