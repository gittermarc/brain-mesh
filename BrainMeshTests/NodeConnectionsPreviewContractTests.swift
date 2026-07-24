//
//  NodeConnectionsPreviewContractTests.swift
//  BrainMeshTests
//

import Foundation
import Testing
@testable import BrainMesh

@Suite("Node connections preview DTO and UI contract")
struct NodeConnectionsPreviewContractTests {
    @Test
    func topLinkSelectionKeepsOutgoingBeforeIncomingAndHonorsLimit() {
        let firstOutgoing = makeRow(
            ordinal: 1,
            peerKind: .entity,
            label: "First outgoing"
        )
        let secondOutgoing = makeRow(
            ordinal: 2,
            peerKind: .attribute,
            label: "Second outgoing"
        )
        let incoming = makeRow(
            ordinal: 3,
            peerKind: .entity,
            label: "Incoming"
        )

        let selected = NodeTopLinks.compute(
            outgoing: [firstOutgoing, secondOutgoing],
            incoming: [incoming],
            max: 2
        )

        #expect(
            selected.map(\.id)
                == [firstOutgoing.peerID, secondOutgoing.peerID]
        )
        #expect(
            selected.map(\.kind)
                == [.entity, .attribute]
        )
        #expect(
            selected.map(\.label)
                == ["First outgoing", "Second outgoing"]
        )
    }

    @Test
    func invalidRowsAreSkippedWithoutChangingValidTopLinkOrder() {
        let invalid = LinkRowDTO(
            id: deterministicUUID(20),
            peerKindRaw: 999,
            peerID: deterministicUUID(21),
            peerLabel: "Invalid",
            note: nil,
            createdAt: .distantPast
        )
        let outgoing = makeRow(
            ordinal: 22,
            peerKind: .attribute,
            label: "Valid outgoing"
        )
        let incoming = makeRow(
            ordinal: 23,
            peerKind: .entity,
            label: "Valid incoming"
        )

        let selected = NodeTopLinks.compute(
            outgoing: [invalid, outgoing],
            incoming: [incoming],
            max: 2
        )

        #expect(
            selected.map(\.id)
                == [outgoing.peerID, incoming.peerID]
        )
    }

    @Test
    func cardRowDTOCarriesThePreviouslyDisplayedLabelAndNote() {
        let row = LinkRowDTO(
            id: deterministicUUID(30),
            peerKindRaw: NodeKind.attribute.rawValue,
            peerID: deterministicUUID(31),
            peerLabel: "Projects · Release",
            note: "Depends on",
            createdAt: Date(timeIntervalSince1970: 100)
        )

        #expect(row.peerLabel == "Projects · Release")
        #expect(row.note == "Depends on")
        #expect(row.createdAt == Date(timeIntervalSince1970: 100))
    }

    @Test
    func peerNavigationUsesKindAndIDFromTheDTO() {
        let row = makeRow(
            ordinal: 40,
            peerKind: .attribute,
            label: "Attribute"
        )

        #expect(
            row.navigationTarget
                == NodeRefKey(
                    kind: .attribute,
                    id: row.peerID
                )
        )
    }

    @Test
    func countsRemainIndependentFromBoundedPreviewRows() {
        let row = makeRow(
            ordinal: 50,
            peerKind: .entity,
            label: "Preview"
        )
        let snapshot = NodeConnectionsPreviewSnapshot(
            outgoingPreview: [row],
            incomingPreview: [],
            outgoingCount: 25,
            incomingCount: 7
        )

        #expect(snapshot.outgoingPreview.count == 1)
        #expect(snapshot.incomingPreview.isEmpty)
        #expect(snapshot.outgoingCount == 25)
        #expect(snapshot.incomingCount == 7)
        #expect(snapshot.totalCount == 32)
    }

    @Test
    func previewSnapshotAndRowsContainNoSwiftDataModels() {
        let row = makeRow(
            ordinal: 60,
            peerKind: .entity,
            label: "Value only"
        )
        let snapshot = NodeConnectionsPreviewSnapshot(
            outgoingPreview: [row],
            incomingPreview: [],
            outgoingCount: 1,
            incomingCount: 0
        )

        let rowValues = Mirror(reflecting: row).children.map(\.value)
        let snapshotValues = Mirror(
            reflecting: snapshot
        ).children.map(\.value)

        #expect(rowValues.contains { $0 is MetaLink } == false)
        #expect(snapshotValues.contains { $0 is MetaLink } == false)
    }
}

private func makeRow(
    ordinal: Int,
    peerKind: NodeKind,
    label: String
) -> LinkRowDTO {
    LinkRowDTO(
        id: deterministicUUID(ordinal),
        peerKindRaw: peerKind.rawValue,
        peerID: deterministicUUID(ordinal + 1_000),
        peerLabel: label,
        note: "Note \(ordinal)",
        createdAt: Date(timeIntervalSince1970: TimeInterval(ordinal))
    )
}

private func deterministicUUID(_ value: Int) -> UUID {
    let suffix = String(format: "%012X", value)
    return UUID(
        uuidString: "00000000-0000-0000-0000-\(suffix)"
    )!
}
