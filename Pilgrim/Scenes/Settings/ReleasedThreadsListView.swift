import SwiftUI

/// Released threads, newest first — tapping an entry welcomes the cohort
/// back. The row that leads here is hidden when this list would be empty.
struct ReleasedThreadsListView: View {

    @State private var entries: [ReleasedThread] = ReleasedThreadsStore.shared.all
    @State private var entryToRestore: ReleasedThread?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    var body: some View {
        List {
            ForEach(entries, id: \.displayTerm) { entry in
                Button {
                    entryToRestore = entry
                } label: {
                    HStack {
                        Text(entry.displayTerm)
                            .font(Constants.Typography.body)
                            .foregroundColor(.ink)
                        Spacer()
                        Text(Self.dateFormatter.string(from: entry.releasedAt))
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
                    .frame(minHeight: 44)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Double tap to welcome this thread back")
                .listRowBackground(Color.parchmentSecondary)
            }
        }
        .scrollContentBackground(.hidden)
        .canvasBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Released threads")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .alert(
            entryToRestore.map { ReleasedThreadsCopy.welcomeBackTitle($0.displayTerm) } ?? "",
            isPresented: Binding(
                get: { entryToRestore != nil },
                set: { if !$0 { entryToRestore = nil } }
            ),
            presenting: entryToRestore
        ) { entry in
            Button(ReleasedThreadsCopy.welcomeBackConfirm) {
                ReleasedThreadsStore.shared.welcomeBack(displayTerm: entry.displayTerm)
                entries = ReleasedThreadsStore.shared.all
                entryToRestore = nil
            }
            Button(ReleasedThreadsCopy.welcomeBackCancel, role: .cancel) {
                entryToRestore = nil
            }
        } message: { _ in
            Text(ReleasedThreadsCopy.welcomeBackMessage)
        }
    }
}
