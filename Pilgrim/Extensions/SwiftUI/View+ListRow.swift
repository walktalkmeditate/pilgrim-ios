import SwiftUI

extension View {
    /// Themed row background + separator tint for List rows in settings
    /// surfaces. Apply on each `Section` (or each row) inside a List that
    /// uses `.scrollContentBackground(.hidden)` + `.canvasBackground()`.
    /// The default `.insetGrouped` row background is iOS's translucent
    /// system gray, which clashes with constellation indigo and the
    /// Pilgrim parchment palette in light + dark.
    func pilgrimListRow() -> some View {
        self
            .listRowBackground(Color.parchmentSecondary)
            .listRowSeparatorTint(Color.fog.opacity(0.2))
    }
}
