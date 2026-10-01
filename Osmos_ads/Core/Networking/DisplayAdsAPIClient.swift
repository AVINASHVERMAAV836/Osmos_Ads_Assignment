//
//  DisplayAdsAPIClient.swift
//  Osmos_ads
//
//  Direct call to the Osmos display ads endpoint (`GET /v2/bsda`) – the same request the SDK makes.
//  Used only as a fallback when the SDK fetch fails with a network error, because the SDK's
//  internal request timeout (~5s) is not configurable and is easily exceeded on slow networks/simulators.
//

import Foundation

nonisolated struct DisplayAdsAPIClient: Sendable {
    private let session: URLSession
    private let timeout: TimeInterval

    init(session: URLSession = .shared, timeout: TimeInterval = 20) {
        self.session = session
        self.timeout = timeout
    }

    /// Returns the decoded JSON object (`{"ads": {"<adUnit>": [...]}}`).
    @concurrent
    func fetchDisplayAds(adUnit: String, count: Int) async throws -> Any {
        var components = URLComponents()
        components.scheme = "https"
        components.host = OsmosConfig.displayAdsHost
        components.path = "/v2/bsda"
        components.queryItems = [
            URLQueryItem(name: "client_id", value: OsmosConfig.clientId),
            URLQueryItem(name: "cli_ubid", value: OsmosConfig.cliUbid),
            URLQueryItem(name: "pt", value: OsmosConfig.pageType),
            URLQueryItem(name: "pcnt_au", value: String(count)),
            URLQueryItem(name: "au[]", value: adUnit),
            URLQueryItem(name: "f.sdk_device", value: "MOBILE"),
            URLQueryItem(name: "os_name", value: "iOS"),
        ]
        guard let url = components.url else {
            throw AdError.invalidResponse("Could not build display ads URL")
        }

        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AdError.network("Display ads request returned HTTP \(http.statusCode)")
        }
        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AdError.invalidResponse("Response is not valid JSON")
        }
    }
}
