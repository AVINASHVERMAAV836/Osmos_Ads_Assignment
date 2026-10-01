//
//  AdRepository.swift
//  Osmos_ads
//
//  Fetches banner ads through an `AdServiceProtocol`, adding automatic retry with backoff.
//

import Foundation

final class AdRepository {
    let service: AdServiceProtocol
    let retryPolicy: RetryPolicy

    init(service: AdServiceProtocol = OsmosAdService(), retryPolicy: RetryPolicy = .default) {
        self.service = service
        self.retryPolicy = retryPolicy
    }

    /// Loads banner ads, retrying transient failures (network / unknown SDK errors).
    /// Non-retryable outcomes such as "no fill" or an invalid response are returned immediately.
    /// - Parameter onRetry: Called before each retry with the upcoming attempt number, the error and the delay.
    func loadBannerAds(
        adUnit: String = OsmosConfig.bannerAdUnit,
        count: Int = OsmosConfig.adsPerRequest,
        onRetry: (_ nextAttempt: Int, _ error: AdError, _ delaySeconds: Double) -> Void = { _, _, _ in }
    ) async throws -> AdFetchResult {
        var attempt = 1
        while true {
            do {
                return try await service.fetchBannerAds(adUnit: adUnit, count: count)
            } catch {
                let adError = AdError.from(error)
                guard adError.isRetryable, attempt < retryPolicy.maxAttempts, !Task.isCancelled else {
                    throw adError
                }

                let delay = retryPolicy.delay(afterAttempt: attempt)
                attempt += 1
                onRetry(attempt, adError, delay)
                // Throws `CancellationError` if the screen goes away while waiting.
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }
}
