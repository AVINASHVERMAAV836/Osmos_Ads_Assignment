//
//  ImageLoader.swift
//  Osmos_ads
//
//  Async image downloader with an in-memory cache.
//

import UIKit

nonisolated final class ImageLoader: @unchecked Sendable {
    // `@unchecked` is safe: `NSCache` and `URLSession` are thread safe and both are immutable references.

    static let shared = ImageLoader()

    private let cache = NSCache<NSURL, UIImage>()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 50
    }

    func image(for url: URL) async throws -> UIImage {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }

        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AdError.network("Image request returned HTTP \(http.statusCode)")
        }
        guard let image = UIImage(data: data) else {
            throw AdError.invalidResponse("Image data could not be decoded")
        }

        // Decode off the main thread so scrolling stays smooth.
        let prepared = await image.byPreparingForDisplay() ?? image
        cache.setObject(prepared, forKey: url as NSURL)
        return prepared
    }
}
