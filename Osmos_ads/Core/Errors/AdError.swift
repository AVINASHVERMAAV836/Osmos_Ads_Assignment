//
//  AdError.swift
//  Osmos_ads
//
//  Unified error type for everything that can go wrong while fetching, rendering or tracking ads.
//

import Foundation

nonisolated enum AdError: Error, Equatable, Sendable {
    /// `OSMOS.shared()` is unavailable or the SDK failed to initialise.
    case sdkNotInitialized
    /// Transport level failure (offline, timeout, DNS, non-2xx status, ...).
    case network(String)
    /// The request succeeded but the ad unit returned no creatives.
    case noFill
    /// The response could not be parsed or every creative was missing required fields.
    case invalidResponse(String)
    /// The request was cancelled (e.g. the screen was dismissed).
    case cancelled
    /// Any other SDK error.
    case unknown(String)

    /// Only transient failures are worth retrying automatically.
    var isRetryable: Bool {
        switch self {
        case .network, .unknown: return true
        case .sdkNotInitialized, .noFill, .invalidResponse, .cancelled: return false
        }
    }

    /// Short, user facing description used in the status label.
    var userMessage: String {
        switch self {
        case .sdkNotInitialized: return "Ads SDK is not initialised."
        case .network: return "Network error. Check your connection."
        case .noFill: return "No ads available for this placement."
        case .invalidResponse: return "Received an invalid ad response."
        case .cancelled: return "Request cancelled."
        case .unknown: return "Something went wrong while loading ads."
        }
    }

    /// Detailed description used by the analytics / logging layer.
    var debugDescription: String {
        switch self {
        case .sdkNotInitialized: return "SDK not initialised"
        case .network(let reason): return "Network error: \(reason)"
        case .noFill: return "No ads in response"
        case .invalidResponse(let reason): return "Invalid response: \(reason)"
        case .cancelled: return "Cancelled"
        case .unknown(let reason): return "Unknown error: \(reason)"
        }
    }

    /// Maps any error (SDK, URLSession, Swift concurrency) into an `AdError`.
    static func from(_ error: Error) -> AdError {
        if let adError = error as? AdError { return adError }
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled ? .cancelled : .network(urlError.localizedDescription)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.code == NSURLErrorCancelled ? .cancelled : .network(nsError.localizedDescription)
        }
        return .unknown(error.localizedDescription)
    }
}
