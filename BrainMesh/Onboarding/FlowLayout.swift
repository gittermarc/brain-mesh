//
//  FlowLayout.swift
//  BrainMesh
//

import SwiftUI

/// Wrap-/Flow-Layout for chips.
///
/// Why not the old AlignmentGuide-ZStack approach?
/// That one can report a too small height inside ScrollViews, causing visual overlaps.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = (proposal.width ?? .greatestFiniteMagnitude)

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > 0, x + size.width > maxWidth {
                measuredWidth = max(measuredWidth, x - spacing)
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        measuredWidth = max(measuredWidth, x > 0 ? (x - spacing) : 0)
        let height = y + rowHeight

        return CGSize(width: proposal.width ?? measuredWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width > 0 ? bounds.width : .greatestFiniteMagnitude

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
