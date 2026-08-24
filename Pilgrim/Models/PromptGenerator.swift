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

    /// The single resolution point for the derivations a prompt-list build
    /// needs: one language detection feeds both the display name and the
    /// echo detector (which then skips its own pass), and one directives
    /// pass serves every style. PromptListView caches this result so the
    /// custom-prompt path never re-derives.
    static func resolvedDerivations(context: ActivityContext) -> (directives: [String], languageName: String?) {
        let languageCode = PromptAssembler.detectedLanguageCode(context: context)
        return (
            directives: AttentionDirectives.detect(context: context, detectedLanguageCode: languageCode),
            languageName: PromptAssembler.languageName(forCode: languageCode)
        )
    }

    static func generateAll(
        context: ActivityContext,
        directives: [String]? = nil,
        detectedLanguageName: String? = nil
    ) -> [GeneratedPrompt] {
        let resolved: (directives: [String], languageName: String?)
        if let directives {
            resolved = (directives, detectedLanguageName)
        } else {
            resolved = resolvedDerivations(context: context)
        }
        return PromptStyle.allCases.map {
            generate(
                style: $0,
                context: context,
                directives: resolved.directives,
                detectedLanguageName: resolved.languageName
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
