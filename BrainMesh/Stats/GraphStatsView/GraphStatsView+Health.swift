//
//  GraphStatsView+Health.swift
//  BrainMesh
//

import Foundation
import SwiftUI

extension GraphStatsView {

    // MARK: - Graph Health Center

    @ViewBuilder
    var graphHealthCenterSection: some View {
        if let activeHealth {
            GraphHealthCenterCard(
                snapshot: activeHealth,
                onIssueAction: handleHealthIssuePrimaryAction,
                onExplainIssue: explainHealthIssue
            )
        }
    }
}
