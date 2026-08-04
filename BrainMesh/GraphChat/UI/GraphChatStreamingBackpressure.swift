//
//  GraphChatStreamingBackpressure.swift
//  BrainMesh
//
//  Turn-local aggregation between safe provider events and visible UI state.
//

import Foundation

nonisolated struct GraphChatStreamingClock: Sendable {
    typealias Instant = UInt64

    let now: @Sendable () async -> Instant
    let sleepUntil: @Sendable (_ deadline: Instant) async throws -> Void

    static let continuous = GraphChatStreamingClock(
        now: {
            DispatchTime.now().uptimeNanoseconds
        },
        sleepUntil: { deadline in
            let now = DispatchTime.now().uptimeNanoseconds
            guard deadline > now else {
                return
            }
            let nanoseconds = min(
                deadline - now,
                UInt64(Int64.max)
            )
            try await Task.sleep(
                for: .nanoseconds(Int64(nanoseconds))
            )
        }
    )
}

nonisolated struct GraphChatStreamingBackpressureConfiguration:
    Hashable,
    Sendable
{
    static let standard = GraphChatStreamingBackpressureConfiguration(
        maximumPublicationsPerSecond: 20
    )

    let maximumPublicationsPerSecond: Int
    let publicationIntervalNanoseconds: UInt64

    init(maximumPublicationsPerSecond: Int) {
        precondition(
            (1...20).contains(maximumPublicationsPerSecond),
            "Graph chat UI publication rate must stay within 1...20 Hz."
        )
        self.maximumPublicationsPerSecond = maximumPublicationsPerSecond
        self.publicationIntervalNanoseconds =
            1_000_000_000 / UInt64(maximumPublicationsPerSecond)
    }
}

nonisolated enum GraphChatStreamingUIPublicationReason:
    String,
    Hashable,
    Sendable
{
    case progress
    case partial
    case terminal
}

nonisolated struct GraphChatStreamingUIPublication: Hashable, Sendable {
    let events: [GraphChatStreamEvent]
    let reason: GraphChatStreamingUIPublicationReason
    let firstSourceSequence: UInt64
    let lastSourceSequence: UInt64

    var terminalEvent: GraphChatStreamEvent? {
        events.first(where: GraphChatGenerationEventClassifier.isTerminal)
    }
}

nonisolated struct GraphChatStreamingBackpressureStatistics:
    Hashable,
    Sendable
{
    let sourceEventCount: Int
    let partialEventCount: Int
    let safeUIPublicationCount: Int
    let partialPublicationCount: Int
    let rateLimitedPublicationCount: Int
    let toolCount: Int
    let toolKinds: Set<GraphChatToolKind>
    let terminalEvent: GraphChatStreamEvent?
    let unpublishedEvents: [GraphChatStreamEvent]
    let firstUnpublishedSourceSequence: UInt64?
    let lastUnpublishedSourceSequence: UInt64?
}

actor GraphChatStreamingBackpressureCoordinator {
    typealias PublicationHandler = @MainActor @Sendable (
        _ publication: GraphChatStreamingUIPublication
    ) async -> Bool

    private struct SequencedEvent: Sendable {
        let sequence: UInt64
        let event: GraphChatStreamEvent
    }

    private let configuration: GraphChatStreamingBackpressureConfiguration
    private let clock: GraphChatStreamingClock

    private var handler: PublicationHandler?
    private var scheduledFlush: Task<Void, Never>?
    private var pendingEvents: [SequencedEvent] = []
    private var pendingPartial: SequencedEvent?
    private var lastPublicationInstant: GraphChatStreamingClock.Instant?
    private var nextSourceSequence: UInt64 = 0
    private var sourceEventCount = 0
    private var partialEventCount = 0
    private var safeUIPublicationCount = 0
    private var partialPublicationCount = 0
    private var rateLimitedPublicationCount = 0
    private var toolCount = 0
    private var toolKinds: Set<GraphChatToolKind> = []
    private var terminalEvent: GraphChatStreamEvent?
    private var unpublishedEvents: [GraphChatStreamEvent] = []
    private var firstUnpublishedSourceSequence: UInt64?
    private var lastUnpublishedSourceSequence: UInt64?
    private var stopped = false

    init(
        configuration: GraphChatStreamingBackpressureConfiguration = .standard,
        clock: GraphChatStreamingClock = .continuous
    ) {
        self.configuration = configuration
        self.clock = clock
    }

    func consume(
        _ source: GraphChatEventStream,
        publish: @escaping PublicationHandler
    ) async -> GraphChatStreamingBackpressureStatistics {
        precondition(handler == nil, "A streaming coordinator owns exactly one turn.")
        handler = publish

        for await event in source {
            guard Task.isCancelled == false, stopped == false else {
                break
            }
            let shouldContinue = await accept(event)
            guard shouldContinue else {
                break
            }
        }

        if Task.isCancelled {
            cancel()
        } else if stopped == false {
            let remainingEvents = takePendingEvents()
            unpublishedEvents = remainingEvents.map(\.event)
            firstUnpublishedSourceSequence = remainingEvents.first?.sequence
            lastUnpublishedSourceSequence = remainingEvents.last?.sequence
            stopped = true
        }
        scheduledFlush?.cancel()
        scheduledFlush = nil
        handler = nil
        return statistics()
    }

    func cancel() {
        stopped = true
        scheduledFlush?.cancel()
        scheduledFlush = nil
        pendingEvents.removeAll(keepingCapacity: false)
        pendingPartial = nil
        handler = nil
    }

    private func accept(_ event: GraphChatStreamEvent) async -> Bool {
        sourceEventCount += 1
        nextSourceSequence &+= 1
        let sequenced = SequencedEvent(
            sequence: nextSourceSequence,
            event: event
        )

        if case .toolActivity(let activity) = event,
           activity.state == .started {
            toolCount += 1
            toolKinds.insert(activity.tool)
        }

        if case .partialAnswer = event {
            partialEventCount += 1
            pendingPartial = sequenced
            if lastPublicationInstant == nil {
                return await flushPending(force: true)
            }
            await scheduleFlushIfNeeded()
            return true
        }

        pendingEvents.append(sequenced)
        guard GraphChatGenerationEventClassifier.isTerminal(event) else {
            if case .toolActivity = event,
               lastPublicationInstant == nil {
                return await flushPending(force: true)
            }
            // The start marker is lifecycle control, not a visible answer
            // snapshot. Publish it immediately without consuming the first
            // rate-limited content slot.
            if case .started = event,
               safeUIPublicationCount == 0 {
                return await flushPending(force: true)
            }
            await scheduleFlushIfNeeded()
            return true
        }

        scheduledFlush?.cancel()
        scheduledFlush = nil
        let accepted = await flushPending(force: true)
        if accepted {
            terminalEvent = event
        }
        stopped = true
        return accepted
    }

    private func scheduleFlushIfNeeded() async {
        guard scheduledFlush == nil,
              stopped == false,
              hasPendingEvents else {
            return
        }
        let now = await clock.now()
        let deadline: UInt64
        if let lastPublicationInstant {
            deadline = publicationDeadline(after: lastPublicationInstant)
        } else {
            deadline = publicationDeadline(after: now)
        }
        guard deadline > now else {
            _ = await flushPending(force: false)
            return
        }
        let clock = self.clock
        scheduledFlush = Task { [weak self] in
            do {
                try await clock.sleepUntil(deadline)
            } catch {
                return
            }
            guard Task.isCancelled == false else {
                return
            }
            await self?.scheduledFlushDidFire()
        }
    }

    private func scheduledFlushDidFire() async {
        scheduledFlush = nil
        _ = await flushPending(force: false)
    }

    private var hasPendingEvents: Bool {
        pendingEvents.isEmpty == false || pendingPartial != nil
    }

    private func flushPending(force: Bool) async -> Bool {
        guard stopped == false,
              hasPendingEvents,
              let handler else {
            return stopped == false
        }

        let now = await clock.now()
        if force == false,
           let lastPublicationInstant,
           now < publicationDeadline(after: lastPublicationInstant) {
            await scheduleFlushIfNeeded()
            return true
        }

        scheduledFlush?.cancel()
        scheduledFlush = nil
        let sequencedEvents = takePendingEvents()

        guard let first = sequencedEvents.first,
              let last = sequencedEvents.last else {
            return true
        }
        let events = sequencedEvents.map(\.event)
        let containsTerminal = events.contains(
            where: GraphChatGenerationEventClassifier.isTerminal
        )
        let containsPartial = events.contains { event in
            if case .partialAnswer = event {
                return true
            }
            return false
        }
        let publication = GraphChatStreamingUIPublication(
            events: events,
            reason: containsTerminal
                ? .terminal
                : (containsPartial ? .partial : .progress),
            firstSourceSequence: first.sequence,
            lastSourceSequence: last.sequence
        )
        let accepted = await handler(publication)
        guard accepted, stopped == false else {
            cancel()
            return false
        }
        safeUIPublicationCount += 1
        if containsPartial {
            partialPublicationCount += 1
        }
        let containsRateLimitedProgress = events.contains { event in
            switch event {
            case .partialAnswer, .toolActivity:
                return true
            case .started, .completed, .cancelled, .failure:
                return false
            }
        }
        if containsRateLimitedProgress, containsTerminal == false {
            rateLimitedPublicationCount += 1
            lastPublicationInstant = await clock.now()
        }
        return true
    }

    private func statistics() -> GraphChatStreamingBackpressureStatistics {
        GraphChatStreamingBackpressureStatistics(
            sourceEventCount: sourceEventCount,
            partialEventCount: partialEventCount,
            safeUIPublicationCount: safeUIPublicationCount,
            partialPublicationCount: partialPublicationCount,
            rateLimitedPublicationCount: rateLimitedPublicationCount,
            toolCount: toolCount,
            toolKinds: toolKinds,
            terminalEvent: terminalEvent,
            unpublishedEvents: unpublishedEvents,
            firstUnpublishedSourceSequence: firstUnpublishedSourceSequence,
            lastUnpublishedSourceSequence: lastUnpublishedSourceSequence
        )
    }

    private func takePendingEvents() -> [SequencedEvent] {
        var sequencedEvents = pendingEvents
        if let pendingPartial {
            sequencedEvents.append(pendingPartial)
        }
        sequencedEvents.sort { lhs, rhs in
            lhs.sequence < rhs.sequence
        }
        pendingEvents.removeAll(keepingCapacity: true)
        pendingPartial = nil
        return sequencedEvents
    }

    private func publicationDeadline(after instant: UInt64) -> UInt64 {
        let addition = instant.addingReportingOverflow(
            configuration.publicationIntervalNanoseconds
        )
        return addition.overflow ? .max : addition.partialValue
    }
}
