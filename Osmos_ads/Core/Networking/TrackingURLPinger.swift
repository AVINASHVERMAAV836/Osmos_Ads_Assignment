//
//  TrackingURLPinger.swift
//  Osmos_ads
//
//  Fires `impression_tracking_url` / `click_tracking_url` directly.
//  Used only as a fallback when the SDK's RegisterEvent API is unavailable.
//

import Foundation

nonisolated struct TrackingURLPinger: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    @concurrent
    func ping(_ url: URL) async throws {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "GET"

        let (_, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<400).contains(http.statusCode) {
            throw AdError.network("Tracking URL returned HTTP \(http.statusCode)")
        }
    }
}
