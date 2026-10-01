//
//  OsmosAdService.swift
//  Osmos_ads
//
//  `AdServiceProtocol` implementation backed by the Osmos iOS SDK.
//

import Foundation
import osmos

nonisolated struct OsmosAdService: AdServiceProtocol {
    private let pinger: TrackingURLPinger
    private let apiClient: DisplayAdsAPIClient

    init(pinger: TrackingURLPinger = TrackingURLPinger(), apiClient: DisplayAdsAPIClient = DisplayAdsAPIClient()) {
        self.pinger = pinger
        self.apiClient = apiClient
    }

    // MARK: - Fetching

    @concurrent
    func fetchBannerAds(adUnit: String, count: Int) async throws -> AdFetchResult {
        do {
            let ads = try await fetchWithSDK(adUnit: adUnit, count: count)
            return AdFetchResult(ads: ads, channel: .sdk)
        } catch {
            // `fetchWithSDK` uses typed throws, so `error` is already an `AdError`.
            // Some SDK releases surface an unavailable connection as `.unknown` rather than
            // `.network`. Both are retryable transport failures, so make a new direct request
            // instead of reusing the SDK's failed request.
            switch error {
            case .network, .unknown:
                break
            default:
                throw error
            }
            let response = try await apiClient.fetchDisplayAds(adUnit: adUnit, count: count)
            let ads = try BannerAdParser.parse(response, adUnit: adUnit)
            return AdFetchResult(ads: ads, channel: .directAPI)
        }
    }

    private func fetchWithSDK(adUnit: String, count: Int) async throws(AdError) -> [BannerAd] {
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
        if let error = capturedError.value { throw Self.map(error) }
        do {
            return try BannerAdParser.parse(response, adUnit: adUnit)
        } catch {
            throw AdError.from(error)
        }
    }

    /// Converts SDK errors into `AdError` so transport problems are recognised as retryable network errors.
    private static func map(_ error: any Error) -> AdError {
        guard let osmosError = error as? OsmosError else { return AdError.from(error) }
        switch osmosError {
        case .networkUnavailable, .connectionTimeout:
            return .network(osmosError.localizedDescription)
        // Wrapped URLSession errors (e.g. "The request timed out.") become `.network`.
        case .invalidRequest(let underlying?):
            return AdError.from(underlying)
        case .defaultError(let underlying):
            return AdError.from(underlying)
        case .badStatus(let code, _):
            return code >= 500 ? .network("HTTP \(code)") : .invalidResponse("HTTP \(code)")
        case .badResponse, .failedToDecode:
            return .invalidResponse(osmosError.localizedDescription)
        case .notInitialized, .missingClientId, .missingConfiguration, .missingDisplayAdConfig:
            return .sdkNotInitialized
        case .mediationNoFill:
            return .noFill
        default:
            return .unknown(osmosError.localizedDescription)
        }
    }

    // MARK: - Event tracking

    @concurrent
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

    @concurrent
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
/// `@unchecked Sendable` is safe: all access to `storage` is serialised by `lock`.
nonisolated private final class ErrorCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: (any Error)?

    var value: (any Error)? {
        lock.withLock { storage }
    }

    func store(_ error: any Error) {
        lock.withLock { storage = error }
    }
}
