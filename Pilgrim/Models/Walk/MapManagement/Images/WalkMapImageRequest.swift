//
//  WalkMapImageRequest.swift
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

import UIKit

class WalkMapImageRequest: Equatable {
    
    let walkUUID: UUID?
    let size: WalkMapImageSize
    let highPriority: Bool
    var completion: (Bool, UIImage?) -> Void
    
    func cacheIdentifier(forDarkAppearance usesDarkAppearance: Bool = Config.isDarkModeEnabled) -> String? {
        guard let uuid = walkUUID else {
            return nil
        }
        let id = String(describing: uuid)
        let size = self.size.identifier
        let appearance = usesDarkAppearance ? "dark" : "light"
        return id + "_" + size + "_" + appearance
    }
    
    init(walkUUID: UUID?, size: WalkMapImageSize, highPriority: Bool = false, completion: @escaping (Bool, UIImage?) -> Void) {
        self.walkUUID = walkUUID
        self.size = size
        self.highPriority = highPriority
        self.completion = completion
    }
    
    static func == (lhs: WalkMapImageRequest, rhs: WalkMapImageRequest) -> Bool {
        return lhs.walkUUID == rhs.walkUUID && lhs.size == rhs.size
    }
}
