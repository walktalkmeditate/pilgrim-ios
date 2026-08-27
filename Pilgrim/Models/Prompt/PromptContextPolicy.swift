import Foundation

/// Which already-computed context blocks a voice receives. A FILTER at
/// assembly time, never a per-voice build — `PromptGenerator.generateAll`
/// fans one `ActivityContext` across every style, and computing per voice
/// would undo PR #65's single-pass work.
///
/// Each voice is a frame, and the right frame is the one that makes the
/// search space small enough to work in. A poem prompt holding a sentiment
/// score is a covering-problem framing of a parity problem.
struct PromptContextPolicy {
    let includesMarkerLines: Bool
    let includesThreadAnalysis: Bool
    /// Whether the `Unchanged:` invariance block is hoisted to the top of
    /// the prompt. True only for `ObliqueVoice`, which is built to read it;
    /// every other voice — including `CustomPromptStyle` via the protocol
    /// default — leaves it false.
    let hoistsUnchangedBlock: Bool

    static let full = PromptContextPolicy(
        includesMarkerLines: true,
        includesThreadAnalysis: true,
        hoistsUnchangedBlock: false
    )
}
