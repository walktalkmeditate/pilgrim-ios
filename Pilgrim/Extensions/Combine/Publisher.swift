//
//  Publisher.swift
//
//  Pilgrim
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
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

import Foundation
import Combine

private let sharedBackgroundQueue = DispatchQueue(label: "BackgroundPublisher", qos: .userInitiated)

public extension Publisher {

    /// Delivers elements on a shared serial background queue.
    ///
    /// A serial queue (not the concurrent global pool) keeps element order
    /// intact. Two deliberate choices guard CombineExt relay teardown, which
    /// traps on `DemandBuffer.complete`'s double-completion precondition when
    /// a relay deinits while its subscription has zero outstanding demand:
    ///
    /// - `buffer(prefetch: .keepFull)` requests its demand synchronously at
    ///   subscription, where `receive(on:)` alone would schedule the request
    ///   onto the queue and leave the relay demand-less until it lands.
    /// - No `subscribe(on:)`: hopping cancellation to another queue lets an
    ///   async cancel race the relay's deinit-time forceFinish.
    func asBackgroundPublisher() -> AnyPublisher<Output, Failure> {
        return self
            .buffer(size: .max, prefetch: .keepFull, whenFull: .dropOldest)
            .receive(on: sharedBackgroundQueue)
            .eraseToAnyPublisher()
    }
    
    /**
     Publishes the current element together with its predecessor.
     
         let range = (1...3)
         cancellable = range.publisher
            .withPrevious()
            .sink {
                print ("(\($0.previous), \($0.current))", terminator: " ")
            }
         // Prints: "(nil, 1) (Optional(1), 2) (Optional(2), 3) ".
     
     - note: The first element will be accompanied by `nil` as the previous value.
     - returns: A publisher of a touple of the optional previous and the current element from the upstream publisher.
     */
    func withPrevious() -> AnyPublisher<(previous: Output?, current: Output), Failure> {
        scan(Optional<(Output?, Output)>.none) { ($0?.1, $1) }
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
}
