//
//  BannerAdParser.swift
//  Osmos_ads
//
//  Converts the loosely typed SDK response into `[BannerAd]`, validating every field.
//
//  Expected shape:
//  {
//    "ads": {
//      "banner_ads": [
//        {
//          "uclid": "...",
//          "elements": { "value": "<image url>", "width": 742, "height": 355,
//                        "destination_url": "<landing url>", "type": "IMAGE" },
//          "impression_tracking_url": "...",
//          "click_tracking_url": "..."
//        }
//      ]
//    }
//  }
//

import Foundation

nonisolated enum BannerAdParser {

    /// Parses the response for `adUnit`.
    /// - Throws: `AdError.noFill` when the ad unit is empty, `AdError.invalidResponse` when the payload is malformed
    ///   or no creative has the required fields.
    static func parse(_ response: Any?, adUnit: String) throws -> [BannerAd] {
        guard let root = dictionary(from: response) else {
            throw AdError.invalidResponse("Response is not a JSON object")
        }
        // The SDK wraps the API payload (e.g. `{"status": true, "data": {"ads": {...}}}`), so the ad unit's
        // array is located wherever it is nested instead of assuming a fixed path.
        guard let rawAds = findAdArray(in: root, adUnit: adUnit, depth: 0) else {
            // An explicit `"status": false` or an empty object means the server had nothing to serve.
            if root.isEmpty || (root["status"] as? Bool) == false { throw AdError.noFill }
            throw AdError.invalidResponse("No \"\(adUnit)\" list found. Top-level keys: \(describeKeys(of: root))")
        }
        guard !rawAds.isEmpty else {
            throw AdError.noFill
        }

        let ads = rawAds.compactMap { parseAd($0, adUnit: adUnit) }
        guard !ads.isEmpty else {
            throw AdError.invalidResponse("All \(rawAds.count) creatives are missing required fields")
        }
        return ads
    }

    /// Returns `nil` for creatives that cannot be rendered (no uclid, no valid image URL, non-image media).
    static func parseAd(_ json: [String: Any], adUnit: String) -> BannerAd? {
        guard let uclid = string(json["uclid"]),
              let elements = json["elements"] as? [String: Any] else { return nil }

        // Only image creatives are rendered manually; skip video / HTML creatives.
        if let type = string(elements["type"]) ?? string(elements["media_type"]),
           type.uppercased() != "IMAGE" {
            return nil
        }

        // `value` is the documented key; the others are fallbacks seen in older response versions.
        let imageString = string(elements["value"])
            ?? string(elements["mobile_image"])
            ?? string(elements["image_url"])
        guard let imageURL = webURL(imageString) else { return nil }

        return BannerAd(
            uclid: uclid,
            adUnit: string(json["au"]) ?? adUnit,
            rank: number(json["rank"]).map { Int($0) },
            imageURL: imageURL,
            destinationURL: webURL(string(elements["destination_url"]) ?? string(elements["destination"])),
            width: number(elements["width"]),
            height: number(elements["height"]),
            impressionTrackingURL: webURL(string(json["impression_tracking_url"])),
            clickTrackingURL: webURL(string(json["click_tracking_url"]))
        )
    }

    // MARK: - Helpers

    /// Depth-first search for `ads.<adUnit>` (preferred) or `<adUnit>` holding an array of creatives.
    /// Nested values may be dictionaries, arrays, or JSON encoded as `String` / `Data`.
    private static func findAdArray(in value: Any, adUnit: String, depth: Int) -> [[String: Any]]? {
        guard depth < 6 else { return nil }

        if let object = dictionary(from: value) {
            if let ads = dictionary(from: object["ads"]), let list = ads[adUnit] as? [Any] {
                return list.compactMap { $0 as? [String: Any] }
            }
            if let list = object[adUnit] as? [Any] {
                return list.compactMap { $0 as? [String: Any] }
            }
            for child in object.values {
                if let found = findAdArray(in: child, adUnit: adUnit, depth: depth + 1) { return found }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = findAdArray(in: child, adUnit: adUnit, depth: depth + 1) { return found }
            }
        }
        return nil
    }

    /// e.g. `status, data{ads, ...}`, used to diagnose unexpected response shapes.
    private static func describeKeys(of dictionary: [String: Any]) -> String {
        dictionary.keys.sorted().map { key in
            if let nested = self.dictionary(from: dictionary[key]) {
                return "\(key){\(nested.keys.sorted().joined(separator: ", "))}"
            }
            return key
        }.joined(separator: ", ")
    }

    /// Accepts a dictionary, raw JSON `Data`, or a JSON `String`.
    private static func dictionary(from response: Any?) -> [String: Any]? {
        switch response {
        case let dictionary as [String: Any]:
            return dictionary
        case let data as Data:
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        case let string as String:
            return string.data(using: .utf8).flatMap { dictionary(from: $0) }
        default:
            return nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        // The API sometimes sends the literal string "null" for missing values.
        return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed
    }

    /// Numbers can arrive as `Int`, `Double` or numeric strings.
    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }

    /// Only absolute http(s) URLs are accepted.
    private static func webURL(_ string: String?) -> URL? {
        guard let string,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}
