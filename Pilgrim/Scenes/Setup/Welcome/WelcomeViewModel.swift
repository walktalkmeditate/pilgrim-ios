//
//  WelcomeViewModel.swift
//
//  Pilgrim
//  Copyright (C) 2022 Tim Fraedrich <timfraedrich@icloud.com>
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

class WelcomeViewModel: ObservableObject {

    static let quotePool = [
        "Every journey begins\nwith a single step",
        "The path is made\nby walking",
        "Not all who wander\nare lost",
        "Solvitur ambulando —\nit is solved by walking",
        "Walk as if you are kissing\nthe earth with your feet",
        "The journey of a thousand miles\nbegins beneath your feet"
    ]

    let currentQuote: String
    private let onBegin: () -> Void

    init(beginAction: @escaping () -> Void) {
        self.currentQuote = Self.quotePool.randomElement() ?? Self.quotePool[0]
        self.onBegin = beginAction
    }

    func beginAction() {
        onBegin()
    }
}
