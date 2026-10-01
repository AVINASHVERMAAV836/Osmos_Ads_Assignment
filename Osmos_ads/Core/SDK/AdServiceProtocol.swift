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

/// Requirements are `@concurrent` so network work, JSON parsing and SDK calls never run on the
/// main actor (with approachable concurrency, plain `nonisolated async` would run on the caller's actor).
nonisolated protocol AdServiceProtocol: Sendable {
    /// Fetches and parses the banner creatives for `adUnit`.
    @concurrent
    func fetchBannerAds(adUnit: String, count: Int) async throws -> AdFetchResult

    /// Registers an impression for `ad` at its 1-based `position` on the page.
    @concurrent
    func registerImpression(for ad: BannerAd, position: Int) async throws -> AdEvent.Channel

    /// Registers a click for `ad`.
    @concurrent
    func registerClick(for ad: BannerAd) async throws -> AdEvent.Channel
}
