//
//  ImportProgressState.swift
//  BrainMesh
//
//  Lightweight, reusable progress state for media/attachment imports.
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class ImportProgressState: ObservableObject {

    @Published private(set) var isPresented: Bool = false
    @Published private(set) var title: String = ""
    @Published private(set) var subtitle: String? = nil

    @Published private(set) var completedUnitCount: Int = 0
    @Published private(set) var totalUnitCount: Int = 0

    @Published private(set) var isIndeterminate: Bool = true
    @Published private(set) var failureCount: Int = 0

    private var hideTask: Task<Void, Never>? = nil

    var fractionCompleted: Double {
        guard !isIndeterminate else { return 0 }
        let total = max(1, totalUnitCount)
        return min(1.0, max(0.0, Double(completedUnitCount) / Double(total)))
    }

    func begin(
        title: String,
        subtitle: String? = nil,
        totalUnitCount: Int,
        indeterminate: Bool = false
    ) {
        hideTask?.cancel()
        hideTask = nil

        self.title = title
        self.subtitle = subtitle
        self.totalUnitCount = max(0, totalUnitCount)
        self.completedUnitCount = 0
        self.failureCount = 0
        self.isIndeterminate = indeterminate || totalUnitCount <= 0
        self.isPresented = true
    }

    func updateSubtitle(_ subtitle: String?) {
        self.subtitle = subtitle
    }

    func advance(didFail: Bool = false) {
        if didFail {
            failureCount += 1
        }

        if !isIndeterminate {
            completedUnitCount = min(totalUnitCount, completedUnitCount + 1)
        }
    }

    func setCompleted(_ completed: Int) {
        isIndeterminate = false
        completedUnitCount = min(totalUnitCount, max(0, completed))
    }

    func finish(
        finalSubtitle: String? = nil,
        autoHideAfterNanoseconds: UInt64 = 650_000_000
    ) {
        if let finalSubtitle {
            subtitle = finalSubtitle
        }

        if !isIndeterminate {
            completedUnitCount = totalUnitCount
        }

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            // Keep the finished state visible briefly, so it doesn't feel like a flicker.
            try? await Task.sleep(nanoseconds: autoHideAfterNanoseconds)
            isPresented = false
        }
    }

    func cancel() {
        hideTask?.cancel()
        hideTask = nil
        isPresented = false
        title = ""
        subtitle = nil
        completedUnitCount = 0
        totalUnitCount = 0
        isIndeterminate = true
        failureCount = 0
    }
}
