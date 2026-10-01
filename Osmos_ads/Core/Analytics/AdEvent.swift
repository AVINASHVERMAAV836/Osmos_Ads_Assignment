//
//  AdEvent.swift
//  Osmos_ads
//
//  Every ad lifecycle event the app records.
//

import Foundation

nonisolated enum AdEvent: Sendable {
    /// How a tracking event reached Osmos.
    enum Channel: String, Sendable {
        /// `RegisterEvent` SDK API (primary path).
        case sdk = "SDK"
        /// Direct ping of the `*_tracking_url` from the response (fallback when the SDK is unavailable).
        case trackingURL = "tracking URL"
        /// Direct call to the display ads endpoint (fallback when the SDK fetch hits a network error).
        case directAPI = "direct API"
    }

    enum Level: Sendable {
        case info
        case warning
        case error
    }

    case sdkInitialized
    case sdkInitFailed(reason: String)
    case adRequested(adUnit: String)
    case duplicateRequestIgnored
    case adRetryScheduled(attempt: Int, maxAttempts: Int, delaySeconds: Double, reason: String)
    case adLoaded(count: Int, channel: Channel)
    case adFailed(reason: String)
    case adRendered(adId: String, position: Int)
    case adRenderFailed(adId: String, reason: String)
    case impressionFired(adId: String, position: Int, channel: Channel)
    case impressionFailed(adId: String, reason: String)
    case clickFired(adId: String, channel: Channel)
    case clickFailed(adId: String, reason: String)
    case landingPageOpened(url: URL)
    case landingPageMissing(adId: String)

    /// Stable event name, suitable for an analytics backend.
    var name: String {
        switch self {
        case .sdkInitialized: return "sdk_initialized"
        case .sdkInitFailed: return "sdk_init_failed"
        case .adRequested: return "ad_requested"
        case .duplicateRequestIgnored: return "ad_request_duplicate_ignored"
        case .adRetryScheduled: return "ad_retry_scheduled"
        case .adLoaded: return "ad_loaded"
        case .adFailed: return "ad_failed"
        case .adRendered: return "ad_rendered"
        case .adRenderFailed: return "ad_render_failed"
        case .impressionFired: return "impression_fired"
        case .impressionFailed: return "impression_failed"
        case .clickFired: return "click_fired"
        case .clickFailed: return "click_failed"
        case .landingPageOpened: return "landing_page_opened"
        case .landingPageMissing: return "landing_page_missing"
        }
    }

    /// Human readable message for logs and the on-screen event log.
    var message: String {
        switch self {
        case .sdkInitialized:
            return "SDK initialised (client \(OsmosConfig.clientId))"
        case .sdkInitFailed(let reason):
            return "SDK initialisation failed: \(reason)"
        case .adRequested(let adUnit):
            return "Ad requested for AU \"\(adUnit)\""
        case .duplicateRequestIgnored:
            return "Request already in progress – duplicate ignored"
        case .adRetryScheduled(let attempt, let maxAttempts, let delay, let reason):
            return "Retry \(attempt)/\(maxAttempts) in \(String(format: "%.1f", delay))s (\(reason))"
        case .adLoaded(let count, let channel):
            return "Ad Loaded – \(count) creative(s) via \(channel.rawValue)"
        case .adFailed(let reason):
            return "Ad Failed – \(reason)"
        case .adRendered(let adId, let position):
            return "Ad rendered #\(position) [\(adId)]"
        case .adRenderFailed(let adId, let reason):
            return "Ad render failed [\(adId)]: \(reason)"
        case .impressionFired(let adId, let position, let channel):
            return "Impression Fired #\(position) via \(channel.rawValue) [\(adId)]"
        case .impressionFailed(let adId, let reason):
            return "Impression failed [\(adId)]: \(reason)"
        case .clickFired(let adId, let channel):
            return "Click Fired via \(channel.rawValue) [\(adId)]"
        case .clickFailed(let adId, let reason):
            return "Click failed [\(adId)]: \(reason)"
        case .landingPageOpened(let url):
            return "Opened landing page \(url.absoluteString)"
        case .landingPageMissing(let adId):
            return "No destination_url for [\(adId)] – nothing to open"
        }
    }

    var level: Level {
        switch self {
        case .sdkInitFailed, .adFailed, .adRenderFailed, .impressionFailed, .clickFailed:
            return .error
        case .duplicateRequestIgnored, .adRetryScheduled, .landingPageMissing:
            return .warning
        default:
            return .info
        }
    }
}
