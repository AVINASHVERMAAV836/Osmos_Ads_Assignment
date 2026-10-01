//
//  BannerAdsViewModel.swift
//  Osmos_ads
//
//  Screen state + business rules: single in-flight request, retry, once-per-ad impressions and click handling.
//

import Foundation

final class BannerAdsViewModel {

    enum State: Equatable {
        case idle
        case loading(attempt: Int, maxAttempts: Int)
        case loaded([BannerAd])
        case failed(AdError)
    }

    /// Called on the main actor whenever `state` changes.
    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    var isLoading: Bool {
        if case .loading = state { return true }
        return false
    }

    private let repository: AdRepository
    private let sdkManager: OsmosSDKManager
    private let analytics: AdAnalytics

    private var loadTask: Task<Void, Never>?
    /// uclids whose impression has already been fired. Guarantees one impression per ad.
    private var firedImpressions = Set<String>()

    init(
        repository: AdRepository = AdRepository(),
        sdkManager: OsmosSDKManager = .shared,
        analytics: AdAnalytics = .shared
    ) {
        self.repository = repository
        self.sdkManager = sdkManager
        self.analytics = analytics
    }

    isolated deinit {
        loadTask?.cancel()
    }

    // MARK: - Loading

    /// Starts a fetch. Ignored while another request is in flight (prevents duplicate requests).
    func loadAds() {
        guard loadTask == nil else {
            analytics.track(.duplicateRequestIgnored)
            return
        }

        // Covers an SDK that failed to initialise at launch: try again before giving up.
        guard sdkManager.initializeIfNeeded() else {
            fail(with: .sdkNotInitialized)
            return
        }

        let maxAttempts = repository.retryPolicy.maxAttempts
        state = .loading(attempt: 1, maxAttempts: maxAttempts)
        analytics.track(.adRequested(adUnit: OsmosConfig.bannerAdUnit))

        loadTask = Task { [weak self, repository] in
            do {
                let ads = try await repository.loadBannerAds { [weak self] nextAttempt, error, delay in
                    self?.handleRetry(nextAttempt: nextAttempt, maxAttempts: maxAttempts, error: error, delay: delay)
                }
                self?.finishLoading(with: .success(ads))
            } catch {
                self?.finishLoading(with: .failure(AdError.from(error)))
            }
        }
    }

    func cancelLoading() {
        loadTask?.cancel()
    }

    private func handleRetry(nextAttempt: Int, maxAttempts: Int, error: AdError, delay: Double) {
        analytics.track(.adRetryScheduled(
            attempt: nextAttempt,
            maxAttempts: maxAttempts,
            delaySeconds: delay,
            reason: error.debugDescription
        ))
        state = .loading(attempt: nextAttempt, maxAttempts: maxAttempts)
    }

    private func finishLoading(with result: Result<[BannerAd], AdError>) {
        loadTask = nil
        switch result {
        case .success(let ads):
            analytics.track(.adLoaded(count: ads.count))
            state = .loaded(ads)
        case .failure(.cancelled):
            state = .idle
        case .failure(let error):
            fail(with: error)
        }
    }

    private func fail(with error: AdError) {
        analytics.track(.adFailed(reason: error.debugDescription))
        state = .failed(error)
    }

    // MARK: - Rendering

    func adDidRender(_ ad: BannerAd, position: Int) {
        analytics.track(.adRendered(adId: ad.shortId, position: position))
    }

    func adDidFailToRender(_ ad: BannerAd, error: AdError) {
        analytics.track(.adRenderFailed(adId: ad.shortId, reason: error.debugDescription))
    }

    // MARK: - Impressions

    /// Called by the view when the ad is at least 50% visible. Fires at most once per ad (per uclid).
    func adDidBecomeVisible(_ ad: BannerAd, position: Int) {
        guard firedImpressions.insert(ad.uclid).inserted else { return }

        let service = repository.service
        Task { [analytics] in
            do {
                let channel = try await service.registerImpression(for: ad, position: position)
                analytics.track(.impressionFired(adId: ad.shortId, position: position, channel: channel))
            } catch {
                analytics.track(.impressionFailed(adId: ad.shortId, reason: AdError.from(error).debugDescription))
            }
        }
    }

    // MARK: - Clicks

    /// Fires the click event (fire-and-forget) and returns the landing page to open, if the ad has one.
    func adWasTapped(_ ad: BannerAd) -> URL? {
        let service = repository.service
        Task { [analytics] in
            do {
                let channel = try await service.registerClick(for: ad)
                analytics.track(.clickFired(adId: ad.shortId, channel: channel))
            } catch {
                analytics.track(.clickFailed(adId: ad.shortId, reason: AdError.from(error).debugDescription))
            }
        }

        guard let destination = ad.destinationURL else {
            analytics.track(.landingPageMissing(adId: ad.shortId))
            return nil
        }
        analytics.track(.landingPageOpened(url: destination))
        return destination
    }
}
