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
    /// Whether the walker's stated intention is handed to the voice as the
    /// lens to read the walk through — the "Let it be the lens through which
    /// you interpret everything below" paragraph in the context dossier, and
    /// the "Ground your response in the walker's stated intention… Help them
    /// see how their walk spoke to this purpose" rider on the instruction.
    ///
    /// True for the six voices the rider was written for, all of which
    /// produce a reading OF THIS WALK. False for `ObliqueVoice`, whose own
    /// constraints contradict it clause for clause: the rider asks for a
    /// resolution ("how their walk spoke to this purpose") where Oblique
    /// requires "End on the observation. Do not resolve it", and asks for a
    /// this-walk summary where Oblique reads the cross-walk invariants under
    /// `Unchanged:` and is told to "Be concrete about the shape, not about
    /// what it means for their life". It is not a rare collision either —
    /// deep-history walkers are exactly the walkers who set intentions, so
    /// the contradiction would have fired on the common case.
    let groundsInIntention: Bool

    static let full = PromptContextPolicy(
        includesMarkerLines: true,
        includesThreadAnalysis: true,
        hoistsUnchangedBlock: false,
        groundsInIntention: true
    )
}
