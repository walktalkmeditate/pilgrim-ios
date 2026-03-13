import Foundation

struct CustomPromptStyle: Codable, Identifiable {
    let id: UUID
    var title: String
    var icon: String
    var instruction: String
}
