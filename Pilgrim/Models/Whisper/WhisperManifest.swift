// Pilgrim/Models/Whisper/WhisperManifest.swift
import Foundation

struct WhisperManifest: Codable {

    let version: Int
    let whispers: [WhisperDefinition]

    static let empty = WhisperManifest(version: 0, whispers: [])
}
