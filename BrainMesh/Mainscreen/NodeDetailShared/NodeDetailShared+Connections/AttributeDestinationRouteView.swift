//
//  AttributeDestinationRouteView.swift
//  BrainMesh
//
//  Query-based route view used for link destinations.
//  (Avoids SwiftData fetches inside SwiftUI body.)
//

import SwiftUI
import SwiftData

struct AttributeDestinationRouteView: View {
    @Query private var attributes: [MetaAttribute]

    init(attributeID: UUID) {
        _attributes = Query(
            filter: #Predicate<MetaAttribute> { a in
                a.id == attributeID
            }
        )
    }

    var body: some View {
        if let attribute = attributes.first {
            AttributeDetailView(attribute: attribute)
        } else {
            NodeMissingView(title: "Attribut nicht gefunden")
        }
    }
}
