//
//  OsmosConfig.swift
//  Osmos_ads
//
//  Static configuration for the Osmos SDK and the demo ad request.
//

import Foundation

/// All values required to initialise the SDK and request display ads.
/// Kept in one place so they can be swapped (e.g. per build configuration) without touching SDK logic.
nonisolated enum OsmosConfig {
    // MARK: SDK initialisation
    static let clientId = "10088010"
    static let productAdsHost = "demo.o-s.io"
    static let displayAdsHost = "demo-ba.o-s.io"

    // MARK: Display ad request (AU based)
    static let cliUbid = "Any"
    static let pageType = "demo_page"
    static let bannerAdUnit = "banner_ads"

    /// Maximum number of creatives requested for the ad unit. The feed renders every creative returned.
    static let adsPerRequest = 5
}
