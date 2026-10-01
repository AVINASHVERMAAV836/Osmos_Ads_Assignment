//
//  OsmosSDKManager.swift
//  Osmos_ads
//
//  Owns the one-time initialisation of the Osmos global instance.
//

import Foundation
import osmos

final class OsmosSDKManager {
    static let shared = OsmosSDKManager()

    private let analytics: AdAnalytics
    /// `buildGlobalInstance()` must be called only once per app session (a second call is a fatal error).
    private var didBuildGlobalInstance = false

    private(set) var isInitialized = false

    init(analytics: AdAnalytics = .shared) {
        self.analytics = analytics
    }

    /// Initialises the SDK if needed. Safe to call any number of times.
    /// - Returns: `true` when the global instance is available.
    @discardableResult
    func initializeIfNeeded() -> Bool {
        if isInitialized { return true }

        if !didBuildGlobalInstance {
            didBuildGlobalInstance = true
            OSMOS.Builder()
                .clientId(OsmosConfig.clientId)
                .productAdsHost(OsmosConfig.productAdsHost)
                .displayAdsHost(OsmosConfig.displayAdsHost)
                .debug(Self.isDebugBuild)
                .buildGlobalInstance()
        }

        // Verify the instance is actually usable.
        do {
            _ = try OSMOS.shared()
            isInitialized = true
            analytics.track(.sdkInitialized)
        } catch {
            isInitialized = false
            analytics.track(.sdkInitFailed(reason: error.localizedDescription))
        }
        return isInitialized
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
}
