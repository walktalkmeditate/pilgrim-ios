//
//  RootViewModel.swift
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
import Combine

class RootCoordinatorViewModel: ObservableObject {
    
    private var cancellables: [AnyCancellable] = []
    
    @Published private(set) var rootState: RootState
    
    init() {
        self.rootState = RootState(isAppSetUp: UserPreferences.isSetUp.value)
        // sink + [weak self] instead of assign(to:on:), which retains self
        // strongly inside its own cancellables — a retain cycle (AF61).
        UserPreferences.isSetUp.publisher
            .map { RootState(isAppSetUp: $0) }
            .sink { [weak self] in self?.rootState = $0 }
            .store(in: &cancellables)
    }
    
    enum RootState {
        case setup
        case main
        
        init(isAppSetUp: Bool) {
            self = isAppSetUp ? .main : .setup
        }
    }
}
