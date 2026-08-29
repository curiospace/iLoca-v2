//
//  Item.swift
//  iLoca
//
//  Created by Afrah Khan on 29/8/2026.
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
