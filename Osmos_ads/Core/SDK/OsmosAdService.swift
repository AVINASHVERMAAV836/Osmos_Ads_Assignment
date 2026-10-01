//
//  OsmosAdService.swift
//  Osmos_ads
//
//  `AdServiceProtocol` implementation backed by the Osmos iOS SDK.
//

import Foundation
import Synchronization
import osmos

nonisolated struct OsmosAdService: AdServiceProtocol {
    private let pinger: TrackingURLPinger

    init(pinger: TrackingURLPinger = TrackingURLPinger()) {
        self.pinger = pinger
    }

    // MARK: - Fetching

    func fetchBannerAds(adUnit: String, count: Int) async throws -> [BannerAd] {
        guard let adFetcher = try? OSMOS.shared().adFetcher() else {
            throw AdError.sdkNotInitialized
        }

        let capturedError = ErrorCapture()
        let response: Any? = await adFetcher.fetchDisplayAdsWithAu(
            cliUbid: OsmosConfig.cliUbid,
            pageType: OsmosConfig.pageType,
            productCount: count,
            adUnits: [adUnit],
            targetingParams: [],
            onError: { @Sendable error in
                capturedError.store(error)
            }
        )

        if Task.isCancelled { throw AdError.cancelled }
        if let error = capturedError.value { throw AdError.from(error) }
        return try BannerAdParser.parse(response, adUnit: adUnit)
    }

    // MARK: - Event tracking

    func registerImpression(for ad: BannerAd, position: Int) async throws -> AdEvent.Channel {
        if let registerEvent = try? OSMOS.shared().registerEvent() {
            let capturedError = ErrorCapture()
            _ = await registerEvent.registerAdImpressionEvent(
                cliUbid: OsmosConfig.cliUbid,
                uclid: ad.uclid,
                position: position,
                onError: { @Sendable error in
                    capturedError.store(error)
                }
            )
            if let error = capturedError.value { throw AdError.from(error) }
            return .sdk
        }

        // Fallback: SDK unavailable, ping the impression URL from the response.
        guard let url = ad.impressionTrackingURL else { throw AdError.sdkNotInitialized }
        try await pinger.ping(url)
        return .trackingURL
    }

    func registerClick(for ad: BannerAd) async throws -> AdEvent.Channel {
        if let registerEvent = try? OSMOS.shared().registerEvent() {
            let capturedError = ErrorCapture()
            _ = await registerEvent.registerAdClickEvent(
                cliUbid: OsmosConfig.cliUbid,
                uclid: ad.uclid,
                trackingParams: TrackingParams(),
                onError: { @Sendable error in
                    capturedError.store(error)
                }
            )
            if let error = capturedError.value { throw AdError.from(error) }
            return .sdk
        }

        // Fallback: SDK unavailable, ping the click URL from the response.
        guard let url = ad.clickTrackingURL else { throw AdError.sdkNotInitialized }
        try await pinger.ping(url)
        return .trackingURL
    }
}

/// Thread-safe holder for the error the SDK reports through its `onError` callback,
/// which may be invoked on any thread.
nonisolated private final class ErrorCapture: Sendable {
    private let storage = Mutex<(any Error)?>(nil)

    var value: (any Error)? {
        storage.withLock { $0 }
    }

    func store(_ error: any Error) {
        storage.withLock { $0 = error }
    }
}
