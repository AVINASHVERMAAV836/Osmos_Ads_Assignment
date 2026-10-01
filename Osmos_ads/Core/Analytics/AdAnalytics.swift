//
//  AdAnalytics.swift
//  Osmos_ads
//
//  Small analytics / logging layer. Events are fanned out to any number of sinks:
//  the unified logging system (Xcode console / Console.app) and the on-screen event log.
//

import Foundation
import os

/// A destination for analytics events (console, UI, remote backend, ...).
protocol AnalyticsSink: AnyObject {
    func record(_ event: AdEvent, at date: Date)
}

final class AdAnalytics {
    static let shared = AdAnalytics(sinks: [OSLogAnalyticsSink()])

    private var sinks: [AnalyticsSink]
    /// Most recent events, replayed to sinks added later (e.g. SDK init logged before the UI exists).
    private var recentEvents: [(event: AdEvent, date: Date)] = []
    private let maxRecentEvents = 50

    init(sinks: [AnalyticsSink]) {
        self.sinks = sinks
    }

    /// Adds a sink and replays recent events to it.
    func addSink(_ sink: AnalyticsSink) {
        guard !sinks.contains(where: { $0 === sink }) else { return }
        sinks.append(sink)
        recentEvents.forEach { sink.record($0.event, at: $0.date) }
    }

    func removeSink(_ sink: AnalyticsSink) {
        sinks.removeAll { $0 === sink }
    }

    func track(_ event: AdEvent) {
        let now = Date()
        recentEvents.append((event, now))
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst(recentEvents.count - maxRecentEvents)
        }
        sinks.forEach { $0.record(event, at: now) }
    }
}

/// Writes events to `os.Logger` (iOS equivalent of Android's Logcat). Filter on category "OsmosAds".
final class OSLogAnalyticsSink: AnalyticsSink {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Osmos_ads", category: "OsmosAds")

    func record(_ event: AdEvent, at date: Date) {
        switch event.level {
        case .info:
            logger.info("[\(event.name, privacy: .public)] \(event.message, privacy: .public)")
        case .warning:
            logger.warning("[\(event.name, privacy: .public)] \(event.message, privacy: .public)")
        case .error:
            logger.error("[\(event.name, privacy: .public)] \(event.message, privacy: .public)")
        }
    }
}

/// Forwards events to a closure; used to drive the on-screen event log.
final class BlockAnalyticsSink: AnalyticsSink {
    private let handler: (AdEvent, Date) -> Void

    init(handler: @escaping (AdEvent, Date) -> Void) {
        self.handler = handler
    }

    func record(_ event: AdEvent, at date: Date) {
        handler(event, date)
    }
}
