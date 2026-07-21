//
//  CommandCenterDestinationSheet.swift
//  BrainMesh
//
//  Central sheet host for destinations opened from the command center.
//

import SwiftUI

struct CommandCenterDestinationSheet: View {
    let destination: CommandCenterDestination

    var body: some View {
        switch destination {
        case .addEntity:
            AddEntityView()

        case .graphTransfer:
            NavigationStack {
                GraphTransferView()
            }

        case .guide:
            NavigationStack {
                BrainMeshGuideView()
            }

        case .nodeDetail(let kind, let id):
            NavigationStack {
                NodeDestinationView(kind: kind, id: id)
            }

        case .graphChatSource(let destination):
            NavigationStack {
                GraphChatSourceDestinationView(destination: destination)
            }
        }
    }
}
