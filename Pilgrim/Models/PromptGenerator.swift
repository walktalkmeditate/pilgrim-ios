import Foundation

struct PromptGenerator {

    typealias RecordingContext = Pilgrim.RecordingContext
    typealias MeditationContext = Pilgrim.MeditationContext
    typealias PlaceRole = Pilgrim.PlaceRole
    typealias PlaceContext = Pilgrim.PlaceContext
    typealias WalkSnippet = Pilgrim.WalkSnippet
    typealias WaypointContext = Pilgrim.WaypointContext

    // MARK: - ActivityContext API

    static func generate(
        style: PromptStyle,
        context: ActivityContext,
        directives: [String]? = nil,
        detectedLanguageName: String? = nil
    ) -> GeneratedPrompt {
        let text = PromptAssembler.assemble(
            context: context,
            voice: style.voice,
            directives: directives,
            detectedLanguageName: detectedLanguageName
        )
        return GeneratedPrompt(style: style, customStyle: nil, text: text)
    }

    static func generateCustom(
        customStyle: CustomPromptStyle,
        context: ActivityContext,
        directives: [String]? = nil,
        detectedLanguageName: String? = nil
    ) -> GeneratedPrompt {
        let text = PromptAssembler.assemble(
            context: context,
            voice: customStyle,
            directives: directives,
            detectedLanguageName: detectedLanguageName
        )
        return GeneratedPrompt(style: nil, customStyle: customStyle, text: text)
    }

    static func generateAll(
        context: ActivityContext,
        directives: [String]? = nil,
        detectedLanguageName: String? = nil
    ) -> [GeneratedPrompt] {
        let directives = directives ?? AttentionDirectives.detect(context: context)
        let detectedLanguageName = detectedLanguageName ?? PromptAssembler.detectedLanguageName(context: context)
        return PromptStyle.allCases.map {
            generate(
                style: $0,
                context: context,
                directives: directives,
                detectedLanguageName: detectedLanguageName
            )
        }
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
