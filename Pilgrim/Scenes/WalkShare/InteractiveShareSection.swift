import SwiftUI

/// The Interactive toggle and its disclosure: recordings with per-item
/// include/kind controls, totals, trim. Lives in its own file to keep
/// WalkShareView under the type-body-length ceiling.
struct InteractiveShareSection: View {

    @ObservedObject var viewModel: WalkShareViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            ShareSectionLabel(text: "Walk with me")

            Toggle(isOn: $viewModel.interactiveEnabled.animation()) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interactive")
                        .font(Constants.Typography.body)
                        .foregroundColor(.ink)
                    Text("Viewers walk your route on a living map — your recordings play where you made them, photos appear where you took them. Recordings and full-size photos upload over your connection.")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .tint(.moss)
            .onChange(of: viewModel.interactiveEnabled) { _, on in
                if on { viewModel.prepareInteractive() }
            }

            if viewModel.interactiveEnabled {
                // A non-interactive share carries no tour.json — the
                // "walk it there" promise only applies once Interactive is on.
                Text("Anyone with the link can walk it there.")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)

                if viewModel.hasRecordings {
                    recordingsList

                    Text(viewModel.tourTotalsLabel)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)

                    if viewModel.tourCandidates.contains(where: { $0.includeInShare && $0.unavailableReason == nil }) {
                        Text("Voices will be audible to anyone with the link.")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                            .padding(.horizontal, Constants.UI.Padding.normal)
                            .transition(.opacity)
                    }
                } else {
                    Text("No recordings on this walk — the page will carry your route, photos, and moments.")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }

                if let error = viewModel.tourValidationError {
                    Text(error)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.rust)
                }

                Toggle(isOn: Binding(
                    get: { viewModel.trimEnabled && viewModel.canTrimRoute },
                    set: { viewModel.trimEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trim start & end")
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Text(viewModel.canTrimRoute
                            ? "Keeps the first and last 150 m off the shared map — including photos and waymarkers there."
                            : "This walk is too short to trim.")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                }
                .tint(.moss)
                .disabled(!viewModel.canTrimRoute)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.interactiveEnabled)
    }

    private var recordingsList: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
            ForEach(viewModel.tourCandidates) { candidate in
                TourRecordingRow(
                    candidate: candidate,
                    onToggleInclude: { viewModel.toggleInclude(candidateID: candidate.id) },
                    onFlipKind: { viewModel.flipKind(candidateID: candidate.id) }
                )
            }
        }
    }
}

// MARK: - Share Section Label

/// The uppercased, tracked micro-label used above every WalkShare section
/// ("Walk with me", "Share these details", "Reflection", "This walk lives
/// for"). Single source for that exact chain — `WalkShareView.sectionLabel`
/// forwards to this too, so the two files can't drift apart style-wise.
struct ShareSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Constants.Typography.micro)
            .foregroundColor(.fog)
            .tracking(1.5)
    }
}

// MARK: - Tour Recording Row

private struct TourRecordingRow: View {

    let candidate: TourRecordingCandidate
    let onToggleInclude: () -> Void
    let onFlipKind: () -> Void

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private var durationLabel: String {
        let seconds = Int(candidate.duration)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var startLabel: String {
        Self.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(candidate.startTs)))
    }

    private var sizeLabel: String {
        String(format: "%.1f MB", Double(candidate.sizeBytes) / 1_048_576)
    }

    private var kindLabel: String {
        candidate.effectiveKind == .spoken ? "voice" : "ambience"
    }

    var body: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            if candidate.unavailableReason == nil {
                includeButton
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Recording \(candidate.id + 1) · \(durationLabel) · \(startLabel)")
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)

                if let reason = candidate.unavailableReason {
                    Text(reason)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                } else {
                    if let preview = candidate.transcription?.trimmingCharacters(in: .whitespacesAndNewlines), !preview.isEmpty {
                        Text(preview)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                            .lineLimit(1)
                    }
                    Text(sizeLabel)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer()

            if candidate.unavailableReason == nil {
                kindChip
            }
        }
        .opacity(candidate.unavailableReason != nil ? 0.45 : (candidate.includeInShare ? 1 : 0.6))
    }

    private var includeButton: some View {
        Button(action: onToggleInclude) {
            Image(systemName: candidate.includeInShare ? "checkmark.circle.fill" : "circle")
                .foregroundColor(candidate.includeInShare ? .moss : .fog)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Include recording \(candidate.id + 1)")
        .accessibilityValue(candidate.includeInShare ? "included" : "excluded")
        .accessibilityHint("Double tap to toggle")
    }

    private var kindChip: some View {
        Button(action: onFlipKind) {
            Text(kindLabel)
                .font(Constants.Typography.caption)
                .foregroundColor(.stone)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.stone.opacity(0.12))
                .cornerRadius(4)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recording \(candidate.id + 1) kind, \(kindLabel)")
        .accessibilityValue(candidate.effectiveKind == .spoken ? "voice" : "ambience")
        .accessibilityHint("Double tap to switch")
        .opacity(candidate.includeInShare ? 1 : 0.35)
    }
}
