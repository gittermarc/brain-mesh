//
//  AttachmentsSection+Presentation.swift
//  BrainMesh
//
//  Created by Marc Fechner on 10.02.26.
//

import SwiftUI

extension AttachmentsSection {

    // MARK: - Presentation gating

    func requestVideoPick() {
        Task { @MainActor in
            if isPickingVideo { return }
            await waitForPresentationSlot()
            isPickingVideo = true
        }
    }

    func requestFileImport() {
        Task { @MainActor in
            if isImportingFile { return }
            await waitForPresentationSlot()
            isImportingFile = true
        }
    }

    func requestPresent(_ sheet: ActiveSheet) {
        Task { @MainActor in
            if activeSheet?.id == sheet.id { return }
            if pendingSheet?.id == sheet.id { return }
            // If something is already up, queue the next one.
            if activeSheet != nil {
                pendingSheet = sheet
                return
            }

            requestGeneration += 1
            let gen = requestGeneration

            // Give SwiftUI/UIKit a moment to finish the originating interaction (Menu/List tap/dismiss).
            await waitForPresentationSlot()

            // If a new request came in while we were waiting, drop this one.
            guard requestGeneration == gen else { return }

            // If another presentation started in the meantime, queue instead of fighting UIKit.
            if activeSheet == nil {
                activeSheet = sheet
            } else {
                pendingSheet = sheet
                return
            }

            // Watchdog: UIKit/SwiftUI can occasionally drop the first attempt (classic "sheet shows then instantly disappears")
            // when a Menu/List interaction is still transitioning. Re-assert once after things settle.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard requestGeneration == gen else { return }
                if activeSheet == nil {
                    await waitForPresentationSlot()
                    guard requestGeneration == gen else { return }
                    activeSheet = sheet
                }
            }
        }
    }

    @MainActor
    func handleSheetDismiss() {
        guard let next = pendingSheet else { return }
        pendingSheet = nil
        requestPresent(next)
    }

    @MainActor
    func waitForPresentationSlot() async {
        // 1) Next runloop tick (kills the classic "Menu closes -> sheet instantly dismisses" issue)
        await Task.yield()
        // 2) Short extra delay to avoid "while a presentation is in progress" during dismiss animations.
        //    This is intentionally tiny, but makes UIKit calm down.
        try? await Task.sleep(nanoseconds: 300_000_000)
    }
}
