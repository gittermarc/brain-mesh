//
//  EntityAttributesAllGrouping.swift
//  BrainMesh
//
//  P0.4: Extracted from EntityDetailView+AttributesSection.swift
//

import Foundation
import SwiftUI

enum EntityAttributesAllGrouping {

    struct AttributeGroup: Identifiable {
        let id: String
        let title: String
        let systemImage: String?
        let rows: [EntityAttributesAllListModel.Row]
    }

    static func makeGroups(
        rows: [EntityAttributesAllListModel.Row],
        settings: AttributesAllListDisplaySettings
    ) -> [AttributeGroup] {
        switch settings.grouping {
        case .none:
            return [AttributeGroup(id: "all", title: "Alle Attribute", systemImage: nil, rows: rows)]

        case .az:
            var buckets: [String: [EntityAttributesAllListModel.Row]] = [:]
            var order: [String] = []
            for row in rows {
                let trimmed = row.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let first = trimmed.first.map { String($0).uppercased() } ?? "#"
                let key = first.range(of: "[A-ZÄÖÜ]", options: .regularExpression) != nil ? first : "#"
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(row)
            }
            let sortedOrder = order.sorted { lhs, rhs in
                if lhs == "#" { return false }
                if rhs == "#" { return true }
                return lhs < rhs
            }
            return sortedOrder.map { key in
                AttributeGroup(id: "az:\(key)", title: key, systemImage: nil, rows: buckets[key] ?? [])
            }

        case .byIcon:
            var buckets: [String: [EntityAttributesAllListModel.Row]] = [:]
            var order: [String] = []
            for row in rows {
                let key = row.isIconSet ? row.iconSymbolName : "(none)"
                if buckets[key] == nil { order.append(key) }
                buckets[key, default: []].append(row)
            }
            return order.map { key in
                if key == "(none)" {
                    return AttributeGroup(id: "icon:none", title: "Ohne Icon", systemImage: "tag", rows: buckets[key] ?? [])
                }
                return AttributeGroup(id: "icon:\(key)", title: key, systemImage: key, rows: buckets[key] ?? [])
            }

        case .hasDetails:
            let withDetails = rows.filter { $0.hasDetails }
            let withoutDetails = rows.filter { !$0.hasDetails }
            var out: [AttributeGroup] = []
            if !withDetails.isEmpty {
                out.append(AttributeGroup(id: "details:yes", title: "Hat Details", systemImage: "square.text.square", rows: withDetails))
            }
            if !withoutDetails.isEmpty {
                out.append(AttributeGroup(id: "details:no", title: "Ohne Details", systemImage: "square", rows: withoutDetails))
            }
            return out

        case .hasMedia:
            let withMedia = rows.filter { $0.hasMedia }
            let withoutMedia = rows.filter { !$0.hasMedia }
            var out: [AttributeGroup] = []
            if !withMedia.isEmpty {
                out.append(AttributeGroup(id: "media:yes", title: "Hat Medien", systemImage: "photo.on.rectangle", rows: withMedia))
            }
            if !withoutMedia.isEmpty {
                out.append(AttributeGroup(id: "media:no", title: "Ohne Medien", systemImage: "rectangle", rows: withoutMedia))
            }
            return out
        }
    }

    @ViewBuilder
    static func groupHeader(title: String, systemImage: String?) -> some View {
        if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }

    @ViewBuilder
    static func inlineHeaderRow(title: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        .listRowBackground(Color.clear)
        .accessibilityAddTraits(.isHeader)
    }
}
