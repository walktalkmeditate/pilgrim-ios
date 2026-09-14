import Foundation

/// The fixture package the iOS plan walks against, so section 2–7 work never
/// waits on the open-pilgrimages build. Read from the source tree through
/// `#filePath` rather than the test bundle: `scripts/xcode-add.rb` registers
/// sources, and adding a resources build phase for four JSON files would be
/// more plumbing than the fixtures are worth.
enum PilgrimageFixtures {

    static var directory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Pilgrimage", isDirectory: true)
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }
}
