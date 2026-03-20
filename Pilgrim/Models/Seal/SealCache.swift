//
//  SealCache.swift
//
//  Pilgrim
//  Copyright (C) 2025-2026 Walk Talk Meditate contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import UIKit
import Cache

final class SealCache {

    static let shared = SealCache()

    private let hybridStorage: HybridStorage<String, UIImage>?
    private let queue = DispatchQueue(label: "org.walktalkmeditate.pilgrim.sealcache")

    private init() {
        let diskConfig = DiskConfig(
            name: "SealCache",
            expiry: .never,
            maxSize: 10_000_000
        )

        let memoryConfig = MemoryConfig(
            expiry: .seconds(900),
            countLimit: 50,
            totalCostLimit: 0
        )

        do {
            let disk = try DiskStorage<String, UIImage>(config: diskConfig, transformer: TransformerFactory.forImage())
            let memory = MemoryStorage<String, UIImage>(config: memoryConfig)
            self.hybridStorage = HybridStorage(memoryStorage: memory, diskStorage: disk)
        } catch {
            print("[SealCache] failed to initialise seal cache")
            self.hybridStorage = nil
        }
    }

    func seal(for walkUUID: String) -> UIImage? {
        queue.sync {
            guard let storage = hybridStorage else { return nil }
            return try? storage.object(forKey: sealKey(walkUUID))
        }
    }

    func thumbnail(for walkUUID: String) -> UIImage? {
        queue.sync {
            guard let storage = hybridStorage else { return nil }
            return try? storage.object(forKey: thumbnailKey(walkUUID))
        }
    }

    func store(seal: UIImage, for walkUUID: String) {
        queue.async { [self] in
            guard let storage = hybridStorage else { return }
            try? storage.setObject(seal, forKey: sealKey(walkUUID))
            let thumb = seal.preparingThumbnail(of: CGSize(width: 128, height: 128)) ?? seal
            try? storage.setObject(thumb, forKey: thumbnailKey(walkUUID))
        }
    }

    func clear() {
        queue.sync { [self] in
            try? hybridStorage?.removeAll()
        }
    }

    private func sealKey(_ uuid: String) -> String { "seal-\(uuid)" }
    private func thumbnailKey(_ uuid: String) -> String { "seal-thumb-\(uuid)" }
}
