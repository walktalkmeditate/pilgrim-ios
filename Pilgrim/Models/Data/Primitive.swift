//
//  Primitive.swift
//
//  Pilgrim
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
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

/// A structure used to represent any database object just by it's uuid; accessing any different variable will result in a fatal error.
class Primitive<Reference>: DataInterface, SampleInterface {
    
    var uuid: UUID? { _uuid }
    
    let _uuid: UUID
    
    init(uuid: UUID) {
        self._uuid = uuid
    }
    
}

extension Primitive: WalkInterface where Reference == Walk {}
extension Primitive: WalkPauseInterface where Reference == WalkPause {
    // this somehow needs to be declared here again (SampleInterface inheritance somehow broke it)
    var workout: WalkInterface? { throwOnAccess() }
}
extension Primitive: WalkEventInterface where Reference == WalkEvent {}
extension Primitive: RouteDataSampleInterface where Reference == RouteDataSample {}
extension Primitive: HeartRateDataSampleInterface where Reference == HeartRateDataSample {}
extension Primitive: EventInterface where Reference == Event {}
