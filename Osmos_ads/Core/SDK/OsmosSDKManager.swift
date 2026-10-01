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

        do {
            if !didBuildGlobalInstance {
                try OSMOS.Builder()
                    .clientId(OsmosConfig.clientId)
                    .productAdsHost(OsmosConfig.productAdsHost)
                    .displayAdsHost(OsmosConfig.displayAdsHost)
                    .debug(Self.isSDKDebugLoggingEnabled)
                    .buildGlobalInstance()
                // Only mark as built on success, so a failed build can be retried from "Load Ad".
                didBuildGlobalInstance = true
            }
            // Verify the instance is actually usable.
            _ = try OSMOS.shared()
            isInitialized = true
            analytics.track(.sdkInitialized)
        } catch {
            isInitialized = false
            analytics.track(.sdkInitFailed(reason: error.localizedDescription))
        }
        return isInitialized
    }

    /// The SDK's debug mode prints every request step several times to stdout, which noticeably slows
    /// the app (and scrolling) while attached to Xcode. Opt in with the `OSMOS_SDK_DEBUG=1` environment
    /// variable (Scheme ▸ Run ▸ Arguments) in Debug builds.
    private static var isSDKDebugLoggingEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["OSMOS_SDK_DEBUG"] == "1"
        #else
        return false
        #endif
    }
}
