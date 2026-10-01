//
//  AdServiceProtocol.swift
//  Osmos_ads
//
//  Abstraction over the ad SDK so the rest of the app (repository, view model, UI)
//  never imports `osmos` directly and can be tested with a mock.
//

import Foundation

/// Parsed creatives plus the path that delivered them (SDK or direct API fallback).
nonisolated struct AdFetchResult: Sendable {
    let ads: [BannerAd]
    let channel: AdEvent.Channel
}

nonisolated protocol AdServiceProtocol: Sendable {
    /// Fetches and parses the banner creatives for `adUnit`.
    func fetchBannerAds(adUnit: String, count: Int) async throws -> AdFetchResult

    /// Registers an impression for `ad` at its 1-based `position` on the page.
    func registerImpression(for ad: BannerAd, position: Int) async throws -> AdEvent.Channel

    /// Registers a click for `ad`.
    func registerClick(for ad: BannerAd) async throws -> AdEvent.Channel
}
