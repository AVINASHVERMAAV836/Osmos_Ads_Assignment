//
//  ViewVisibilityTracker.swift
//  Osmos_ads
//
//  Reusable helper that notifies once when a view becomes at least N% visible on screen.
//

import UIKit

/// Tracks a set of views and calls each view's handler **once**, the first time at least
/// `threshold` (default 50%) of its area is visible on screen.
///
/// A view counts as visible only when:
/// - it is in a window whose scene is in the foreground and active,
/// - neither it nor any ancestor is hidden or transparent,
/// - the part left after clipping by every `clipsToBounds` ancestor (e.g. the scroll view) and the
///   window covers at least `threshold` of the view's area.
///
/// Visibility is re-evaluated automatically when the attached scroll view scrolls or resizes
/// (rotation) and when the scene becomes active again. Call `evaluate()` after layout changes.
final class ViewVisibilityTracker: NSObject {

    private struct Registration {
        weak var view: UIView?
        let threshold: CGFloat
        let onVisible: () -> Void
    }

    private var registrations: [ObjectIdentifier: Registration] = [:]
    private var observations: [NSKeyValueObservation] = []

    /// - Parameter scrollView: Optional scroll view whose scrolling / resizing should trigger a re-check.
    init(scrollView: UIScrollView? = nil) {
        super.init()
        if let scrollView {
            observe(scrollView)
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sceneDidActivate),
            name: UIScene.didActivateNotification,
            object: nil
        )
    }

    deinit {
        observations.forEach { $0.invalidate() }
    }

    // MARK: - Public API

    /// Starts tracking `view`. `onVisible` is called at most once; the view is untracked afterwards.
    func track(_ view: UIView, threshold: CGFloat = 0.5, onVisible: @escaping () -> Void) {
        registrations[ObjectIdentifier(view)] = Registration(
            view: view,
            threshold: min(max(threshold, 0.01), 1),
            onVisible: onVisible
        )
        evaluate()
    }

    func untrack(_ view: UIView) {
        registrations[ObjectIdentifier(view)] = nil
    }

    func untrackAll() {
        registrations.removeAll()
    }

    /// Re-checks every tracked view and fires handlers for those that crossed their threshold.
    func evaluate() {
        guard !registrations.isEmpty else { return }

        for (key, registration) in registrations {
            guard let view = registration.view else {
                // The view was deallocated; drop it.
                registrations[key] = nil
                continue
            }
            guard Self.visibleFraction(of: view) >= registration.threshold else { continue }

            // Remove before calling out so the handler can never fire twice, even if it triggers layout.
            registrations[key] = nil
            registration.onVisible()
        }
    }

    // MARK: - Geometry

    /// Fraction (0...1) of `view`'s area currently visible on screen.
    static func visibleFraction(of view: UIView) -> CGFloat {
        guard let window = view.window,
              window.windowScene?.activationState == .foregroundActive,
              !view.isHidden, view.alpha > 0.01,
              view.bounds.width > 0, view.bounds.height > 0 else { return 0 }

        let frameInWindow = view.convert(view.bounds, to: window)
        let totalArea = frameInWindow.width * frameInWindow.height
        guard totalArea > 0 else { return 0 }

        // Walk up the hierarchy, clipping to every ancestor that clips its content.
        var visibleRect = frameInWindow
        var ancestor = view.superview
        while let current = ancestor, current !== window {
            if current.isHidden || current.alpha <= 0.01 { return 0 }
            if current.clipsToBounds {
                visibleRect = visibleRect.intersection(current.convert(current.bounds, to: window))
                if visibleRect.isNull || visibleRect.isEmpty { return 0 }
            }
            ancestor = current.superview
        }
        visibleRect = visibleRect.intersection(window.bounds)
        guard !visibleRect.isNull else { return 0 }

        return (visibleRect.width * visibleRect.height) / totalArea
    }

    // MARK: - Triggers

    private func observe(_ scrollView: UIScrollView) {
        // KVO fires on the main thread for UIKit property changes.
        let offset = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        let bounds = scrollView.observe(\.bounds, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        observations = [offset, bounds]
    }

    @objc private func sceneDidActivate() {
        evaluate()
    }
}
