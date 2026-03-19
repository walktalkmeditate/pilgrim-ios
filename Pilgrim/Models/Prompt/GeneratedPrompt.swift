import Foundation

struct GeneratedPrompt: Identifiable {
    let id = UUID()
    let style: PromptStyle?
    let customStyle: CustomPromptStyle?
    let text: String

    var title: String { customStyle?.title ?? style?.title ?? "" }
    var icon: String { customStyle?.icon ?? style?.icon ?? "questionmark" }
    var subtitle: String { customStyle?.instruction ?? style?.description ?? "" }
}
