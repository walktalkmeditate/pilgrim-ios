import XCTest
@testable import Pilgrim

final class SeekSeedTests: XCTestCase {

    private let moment = Date(timeIntervalSince1970: 1_790_000_000)

    private func seed(
        intention: String? = "let go",
        moment: Date? = nil,
        entropy: UInt64 = 7
    ) -> UInt64 {
        SeekSeed.make(
            intention: intention,
            moment: moment ?? self.moment,
            fix: nil,
            entropy: entropy
        )
    }

    // MARK: - Determinism and mixing

    func testSameQuestionSameMomentSameEntropy_sameSeed() {
        XCTAssertEqual(seed(), seed())
    }

    func testTheIntentionIsAVoiceInTheSeed() {
        XCTAssertNotEqual(
            seed(intention: "let go"), seed(intention: "find courage"),
            "a different question must be sent a different way"
        )
        XCTAssertNotEqual(
            seed(intention: "let go"), seed(intention: "Let go"),
            "the question exactly as asked - case and all"
        )
        XCTAssertNotEqual(seed(intention: "let go"), seed(intention: nil))
    }

    func testTheMomentIsAVoiceInTheSeed() {
        XCTAssertNotEqual(
            seed(), seed(moment: moment.addingTimeInterval(1)),
            "the same question a second later never repeats the way"
        )
    }

    func testEntropyIsAVoiceInTheSeed() {
        XCTAssertNotEqual(seed(entropy: 7), seed(entropy: 8))
    }

    func testEmptyAndNilIntention_readAsUnasked() {
        XCTAssertEqual(seed(intention: nil), seed(intention: ""))
    }

    // MARK: - Seeded generator

    func testSeededGenerator_isDeterministicPerSeed() {
        var first = SeekSeededGenerator(seed: 42)
        var second = SeekSeededGenerator(seed: 42)
        var other = SeekSeededGenerator(seed: 43)
        let a = (0..<4).map { _ in first.next() }
        let b = (0..<4).map { _ in second.next() }
        let c = (0..<4).map { _ in other.next() }
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testSeededChainGeneration_isReproducible() {
        let start = SeekPoint(latitude: 42.8782, longitude: -8.5448)
        var first = SeekSeededGenerator(seed: 99)
        var second = SeekSeededGenerator(seed: 99)
        var other = SeekSeededGenerator(seed: 100)
        let one = SeekChainGenerator.generate(durationMinutes: 60, start: start, using: &first)
        let two = SeekChainGenerator.generate(durationMinutes: 60, start: start, using: &second)
        let three = SeekChainGenerator.generate(durationMinutes: 60, start: start, using: &other)
        XCTAssertEqual(one, two, "one seed is one seek")
        XCTAssertNotEqual(one, three, "a different seed must be sent a different way")
    }
}
