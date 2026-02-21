//
//  AsyncLimiter.swift
//  BrainMesh
//
//  A tiny async semaphore used to throttle concurrent work (thumbnails, hydration, etc.).
//

import Foundation

/// A tiny async semaphore.
///
/// - `withPermit` suspends until a permit is available, runs the operation, then releases.
/// - FIFO fairness is "good enough" for UI-facing work.
actor AsyncLimiter {

    private let maxConcurrent: Int
    private var available: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
        self.available = max(1, maxConcurrent)
    }

    func withPermit<T>(_ operation: @Sendable () async -> T) async -> T {
        await acquire()
        defer { release() }
        return await operation()
    }

    private func acquire() async {
        if available > 0 {
            available -= 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    private func release() {
        if !waiters.isEmpty {
            let cont = waiters.removeFirst()
            cont.resume()
            return
        }
        available = min(maxConcurrent, available + 1)
    }
}
