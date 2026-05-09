import SwiftUI

struct AppearanceView: View {

    @State private var mode: String = UserPreferences.appearanceMode.value
    @EnvironmentObject private var appearanceManager: AppearanceManager

    private struct ModeEntry: Identifiable {
        let value: String
        let label: String
        let glyph: String
        let description: String
        var id: String { value }
    }

    private let entries: [ModeEntry] = [
        ModeEntry(value: "system",        label: "Auto",          glyph: "circle.righthalf.filled", description: "Match the system setting"),
        ModeEntry(value: "light",         label: "Light",         glyph: "sun.max",                 description: "Parchment background, ink text"),
        ModeEntry(value: "dark",          label: "Dark",          glyph: "moon",                    description: "Easy on the eyes for evening walks"),
        ModeEntry(value: "constellation", label: "Constellation", glyph: "sparkles",                description: "A quiet night sky, with drifting stars")
    ]

    var body: some View {
        // Touch themeID so this view's body re-evaluates on mode change —
        // ensures the just-picked mode's bg + text update in place without
        // dismissing the picker.
        _ = appearanceManager.themeID
        return List(entries) { entry in
            Button {
                UserPreferences.appearanceMode.value = entry.value
                mode = entry.value
            } label: {
                HStack(spacing: Constants.UI.Padding.normal) {
                    Image(systemName: entry.glyph)
                        .font(.title3)
                        .foregroundColor(.fog)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.label)
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Text(entry.description)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                    Spacer()
                    if mode == entry.value {
                        Image(systemName: "checkmark")
                            .foregroundColor(.stone)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Appearance")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .onAppear {
            mode = UserPreferences.appearanceMode.value
        }
    }
}
