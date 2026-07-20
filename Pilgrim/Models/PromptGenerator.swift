import Foundation

struct PromptGenerator {

    typealias RecordingContext = Pilgrim.RecordingContext
    typealias MeditationContext = Pilgrim.MeditationContext
    typealias PlaceRole = Pilgrim.PlaceRole
    typealias PlaceContext = Pilgrim.PlaceContext
    typealias WalkSnippet = Pilgrim.WalkSnippet
    typealias WaypointContext = Pilgrim.WaypointContext

    // MARK: - ActivityContext API

    static func generate(style: PromptStyle, context: ActivityContext) -> GeneratedPrompt {
        let text = PromptAssembler.assemble(context: context, voice: style.voice)
        return GeneratedPrompt(style: style, customStyle: nil, text: text)
    }

    static func generateCustom(customStyle: CustomPromptStyle, context: ActivityContext) -> GeneratedPrompt {
        let text = PromptAssembler.assemble(context: context, voice: customStyle)
        return GeneratedPrompt(style: nil, customStyle: customStyle, text: text)
    }

    static func generateAll(context: ActivityContext) -> [GeneratedPrompt] {
        PromptStyle.allCases.map { generate(style: $0, context: context) }
    }

    static func formatWeather(_ walk: WalkInterface) -> String? {
        ContextFormatter.formatWeather(walk)
    }
}

extension String {
    func truncatedAtWordBoundary(maxLength: Int = 200) -> String {
        guard count > maxLength else { return self }
        let truncated = prefix(maxLength)
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "..."
        }
        return String(truncated) + "..."
    }
}
