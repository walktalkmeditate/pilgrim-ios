import Foundation

struct GeneratedPrompt: Identifiable {
    let id = UUID()
    let style: PromptStyle?
    let customStyle: CustomPromptStyle?
    let text: String

    var title: String { customStyle?.title ?? style?.title ?? "" }
    var icon: String { customStyle?.icon ?? style?.icon ?? "questionmark" }
    var subtitle: String { customStyle?.instruction ?? style?.description ?? "" }

    /// `text` is the empty string whenever `PromptAssembler.assemble` refused
    /// to build — a voice that hoists the `Unchanged:` block with no block to
    /// hoist. `text` is non-optional, so the sentinel is invisible at the type
    /// level and every consumer that copies, shares or renders it has to ask
    /// first. `PromptListView`'s picker gate is one view; this is the property
    /// any other surface can check.
    var hasText: Bool { !text.isEmpty }

    /// Shown in place of the body when there is no prompt to show. Reached
    /// only if some surface bypasses the picker gate — a fallback, not a
    /// designed state.
    static let emptyBodyCopy = "There's nothing to show for this walk yet."
}
