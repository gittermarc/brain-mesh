//
//  Item.swift
//  BrainMesh
//
//  Created by Marc Fechner on 13.12.25.
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
