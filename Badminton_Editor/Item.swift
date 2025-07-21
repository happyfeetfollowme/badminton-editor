//
//  Item.swift
//  Badminton_Editor
//
//  Created by khc on 7/20/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
