//
//  BannerAd.swift
//  Osmos_ads
//
//  Domain model for a single banner creative from `ads.<adUnit>[n]`.
//

import Foundation

nonisolated struct BannerAd: Hashable, Identifiable, Sendable {
    /// Unique id for this ad in this response. Every event for the ad must carry it.
    let uclid: String
    let adUnit: String
    let rank: Int?

    /// `elements.value`
    let imageURL: URL
    /// `elements.destination_url`. Optional: some demo creatives do not have a landing page.
    let destinationURL: URL?
    /// `elements.width` / `elements.height` (creative's native size, used for aspect ratio).
    let width: Double?
    let height: Double?

    let impressionTrackingURL: URL?
    let clickTrackingURL: URL?

    var id: String { uclid }

    /// Height / width ratio, or `nil` when the response has no usable size.
    var aspectRatio: Double? {
        guard let width, let height, width > 0, height > 0 else { return nil }
        return height / width
    }

    /// Shortened uclid for readable logs (real uclids are ~300 characters long).
    var shortId: String {
        uclid.count > 12 ? "\(uclid.prefix(12))…" : uclid
    }
}
