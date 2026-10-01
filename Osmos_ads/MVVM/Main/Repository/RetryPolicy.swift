//
//  RetryPolicy.swift
//  Osmos_ads
//
//  Exponential backoff configuration for ad fetching.
//

import Foundation

nonisolated struct RetryPolicy: Sendable {
    /// Total attempts including the first one.
    let maxAttempts: Int
    /// Delay before the first retry.
    let initialDelay: Double
    /// Multiplier applied to the delay after each retry.
    let multiplier: Double

    static let `default` = RetryPolicy(maxAttempts: 3, initialDelay: 1, multiplier: 2)

    /// Delay (in seconds) to wait after `failedAttempt` (1-based) failed. 1s, 2s, 4s, ...
    func delay(afterAttempt failedAttempt: Int) -> Double {
        initialDelay * pow(multiplier, Double(max(failedAttempt - 1, 0)))
    }
}
