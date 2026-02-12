//
//  NodeBulkLinkSheet.swift
//  BrainMesh
//
//  Created by Marc Fechner on 12.02.26.
//

import Foundation
import SwiftUI

struct NodeBulkLinkSheet: ViewModifier {
    @Binding var isPresented: Bool
    let source: NodeRef
    let graphID: UUID?

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            BulkLinkView(source: source, graphID: graphID)
        }
    }
}

extension View {
    func bulkLinkSheet(isPresented: Binding<Bool>, source: NodeRef, graphID: UUID?) -> some View {
        modifier(NodeBulkLinkSheet(isPresented: isPresented, source: source, graphID: graphID))
    }
}
