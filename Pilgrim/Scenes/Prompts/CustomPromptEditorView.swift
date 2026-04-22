import SwiftUI

struct CustomPromptEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CustomPromptStyleStore

    var editingStyle: CustomPromptStyle?

    @State private var title: String = ""
    @State private var selectedIcon: String = "pencil.line"
    @State private var instruction: String = ""

    private let iconOptions = [
        "pencil.line", "text.quote", "envelope.fill", "lightbulb.fill",
        "flame.fill", "leaf.fill", "wind", "drop.fill",
        "sun.max.fill", "moon.fill", "star.fill", "sparkles",
        "figure.walk", "mountain.2.fill", "water.waves", "bird.fill",
        "hands.clap.fill", "brain.head.profile", "book.fill", "music.note"
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.big) {
                    titleSection
                    iconSection
                    instructionSection
                }
                .padding(Constants.UI.Padding.normal)
            }
            .background(Color.parchment)
            .navigationTitle(editingStyle == nil ? "New Prompt Style" : "Edit Prompt Style")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.stone)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { saveAndDismiss() }
                        .foregroundColor(.stone)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty ||
                                  instruction.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear {
            if let editing = editingStyle {
                title = editing.title
                selectedIcon = editing.icon
                instruction = editing.instruction
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("Title")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
            TextField("e.g., Letter to Future Self", text: $title)
                .font(Constants.Typography.body)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("Icon")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(iconOptions, id: \.self) { icon in
                    Button {
                        selectedIcon = icon
                    } label: {
                        Image(systemName: icon)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .foregroundColor(selectedIcon == icon ? .parchment : .stone)
                            .background(selectedIcon == icon ? Color.stone : Color.parchmentSecondary)
                            .cornerRadius(Constants.UI.CornerRadius.small)
                    }
                }
            }
        }
    }

    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Text("Instruction")
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
            TextEditor(text: $instruction)
                .font(Constants.Typography.body)
                .frame(minHeight: 120)
                .scrollContentBackground(.hidden)
                .padding(Constants.UI.Padding.small)
                .background(Color.parchmentSecondary)
                .cornerRadius(Constants.UI.CornerRadius.small)
                .overlay(
                    Group {
                        if instruction.isEmpty {
                            Text("Tell the AI what to do with your walking thoughts...")
                                .font(Constants.Typography.body)
                                .foregroundColor(.fog)
                                .padding(Constants.UI.Padding.small + 4)
                        }
                    },
                    alignment: .topLeading
                )

            Text("\(store.styles.count + (editingStyle == nil ? 1 : 0)) of \(CustomPromptStyleStore.maxStyles)")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func saveAndDismiss() {
        let style = CustomPromptStyle(
            id: editingStyle?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            icon: selectedIcon,
            instruction: instruction.trimmingCharacters(in: .whitespaces)
        )
        store.save(style)
        dismiss()
    }
}
