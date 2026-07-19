// Pilgrim/Models/Collective/CollectiveMilestone.swift
import Foundation

/// A sacred walk-count the collective has just crossed, and the sentence shown
/// when it does.
///
/// Which numbers count as sacred lives with the crossing logic in
/// `CollectiveCounterService.sacredNumbers`; this type only names them. A number
/// with no name still produces a message, so a caller can never be handed nil.
struct CollectiveMilestone {
    let number: Int
    let message: String

    static func forNumber(_ number: Int) -> CollectiveMilestone {
        let message: String
        switch number {
        case 108:
            message = "108 walks. One for each bead on the mala."
        case 1_080:
            message = "1,080 walks. The mala, turned ten times."
        case 2_160:
            message = "2,160 walks. One full age of the zodiac."
        case 10_000:
            message = "10,000 walks. 万 — all things."
        case 33_333:
            message = "33,333 walks. The Saigoku pilgrimage, a thousandfold."
        case 88_000:
            message = "88,000 walks. Shikoku's 88 temples, a thousand times over."
        case 108_000:
            message = "108,000 walks. The great mala, complete."
        default:
            message = "\(number.formatted()) walks. You were one of them."
        }
        return CollectiveMilestone(number: number, message: message)
    }
}
