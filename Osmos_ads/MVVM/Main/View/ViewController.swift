//
//  ViewController.swift
//  Osmos_ads
//
//  Created by Bizionic Technologies Pvt Ltd on 01/10/26.
//

import SafariServices
import UIKit

/// Demo screen: "Load Ad" button, a scrollable feed rendering every banner creative, and an on-screen event log.
final class ViewController: UIViewController {

    // MARK: - Outlets

    @IBOutlet private weak var loadAdButton: UIButton!
    @IBOutlet private weak var statusLabel: UILabel!
    @IBOutlet private weak var scrollView: UIScrollView!
    /// Banner render area. Ads and content cards are added as arranged subviews.
    @IBOutlet private weak var adContainerStackView: UIStackView!
    @IBOutlet private weak var placeholderLabel: UILabel!
    @IBOutlet private weak var eventLogTextView: UITextView!
    @IBOutlet private weak var eventLogHeightConstraint: NSLayoutConstraint!

    // MARK: - Dependencies

    private let viewModel = BannerAdsViewModel()
    private let analytics = AdAnalytics.shared
    private lazy var visibilityTracker = ViewVisibilityTracker(scrollView: scrollView)
    private lazy var eventLogSink = BlockAnalyticsSink { [weak self] event, date in
        self?.appendToEventLog(event, at: date)
    }

    private var eventLogLineCount = 0
    private static let maxEventLogLines = 200
    private static let contentCardsBetweenAds = 2

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        configureEventLog()
        analytics.addSink(eventLogSink)

        viewModel.onStateChange = { [weak self] state in
            self?.render(state)
        }
        render(viewModel.state)

        registerForTraitChanges([UITraitVerticalSizeClass.self]) { (self: Self, _) in
            self.updateEventLogHeight()
        }
        updateEventLogHeight()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Ads can become visible because of layout alone (first render, image loaded, rotation).
        visibilityTracker.evaluate()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        // Re-check once the rotation settled; ad geometry follows its aspect-ratio constraints.
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.visibilityTracker.evaluate()
        }
    }

    isolated deinit {
        analytics.removeSink(eventLogSink)
    }

    // MARK: - Actions

    @IBAction private func loadAdTapped(_ sender: UIButton) {
        viewModel.loadAds()
    }

    // MARK: - Rendering

    private func render(_ state: BannerAdsViewModel.State) {
        var configuration = loadAdButton.configuration ?? .filled()

        switch state {
        case .idle:
            configuration.title = "Load Ad"
            configuration.showsActivityIndicator = false
            loadAdButton.isEnabled = true
            statusLabel.text = "Tap “Load Ad” to fetch banner ads."
            showPlaceholder("Banner ads will appear here.")

        case .loading(let attempt, let maxAttempts):
            configuration.title = attempt > 1 ? "Retrying…" : "Loading…"
            configuration.showsActivityIndicator = true
            loadAdButton.isEnabled = false
            statusLabel.text = attempt > 1
                ? "Retrying… (attempt \(attempt) of \(maxAttempts))"
                : "Fetching ads for “\(OsmosConfig.bannerAdUnit)”…"
            showPlaceholder("Loading ads…")

        case .loaded(let ads):
            configuration.title = "Reload Ads"
            configuration.showsActivityIndicator = false
            loadAdButton.isEnabled = true
            statusLabel.text = "\(ads.count) ad(s) loaded. Scroll to trigger impressions."
            renderFeed(with: ads)

        case .failed(let error):
            configuration.title = "Retry"
            configuration.showsActivityIndicator = false
            loadAdButton.isEnabled = true
            statusLabel.text = error.userMessage
            showPlaceholder("Ad not available")
        }

        loadAdButton.configuration = configuration
    }

    private func showPlaceholder(_ text: String) {
        clearFeed()
        placeholderLabel.text = text
        placeholderLabel.isHidden = false
    }

    private func clearFeed() {
        visibilityTracker.untrackAll()
        adContainerStackView.arrangedSubviews
            .filter { $0 !== placeholderLabel }
            .forEach { $0.removeFromSuperview() }
    }

    /// Builds the feed: content cards interleaved with every ad returned for the ad unit.
    private func renderFeed(with ads: [BannerAd]) {
        clearFeed()
        placeholderLabel.isHidden = true
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)

        var contentIndex = 1
        func addContentCards() {
            for _ in 0..<Self.contentCardsBetweenAds {
                adContainerStackView.addArrangedSubview(ContentCardView(index: contentIndex))
                contentIndex += 1
            }
        }

        for (index, ad) in ads.enumerated() {
            addContentCards()
            let adView = BannerAdView(ad: ad, position: index + 1)
            adView.onTap = { [weak self] view in
                self?.handleTap(on: view)
            }
            adView.onRenderResult = { [weak self] view, result in
                self?.handleRenderResult(result, for: view)
            }
            adContainerStackView.addArrangedSubview(adView)
            adView.loadImage()
        }
        addContentCards()
    }

    private func handleRenderResult(_ result: Result<Void, AdError>, for adView: BannerAdView) {
        switch result {
        case .success:
            viewModel.adDidRender(adView.ad, position: adView.position)
            // Only start measuring visibility once the creative is actually on screen.
            visibilityTracker.track(adView, threshold: 0.5) { [weak self, weak adView] in
                guard let self, let adView else { return }
                self.viewModel.adDidBecomeVisible(adView.ad, position: adView.position)
            }
        case .failure(let error):
            viewModel.adDidFailToRender(adView.ad, error: error)
        }
    }

    private func handleTap(on adView: BannerAdView) {
        guard let url = viewModel.adWasTapped(adView.ad) else { return }
        let safari = SFSafariViewController(url: url)
        safari.dismissButtonStyle = .close
        present(safari, animated: true)
    }

    // MARK: - Event log

    private func configureEventLog() {
        eventLogTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        eventLogTextView.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        eventLogTextView.text = ""
        eventLogTextView.layer.cornerRadius = 8
    }

    private func appendToEventLog(_ event: AdEvent, at date: Date) {
        let marker: String
        switch event.level {
        case .info: marker = "✅"
        case .warning: marker = "⚠️"
        case .error: marker = "❌"
        }
        guard isViewLoaded else { return }
        let line = "\(Self.timeFormatter.string(from: date)) \(marker) \(event.message)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: eventLogTextView.font ?? UIFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: UIColor.label,
        ]

        // Append incrementally instead of resetting the whole text, so an impression logged
        // mid-scroll doesn't trigger a full text re-layout (which caused visible hitches).
        let storage = eventLogTextView.textStorage
        storage.beginEditing()
        storage.append(NSAttributedString(string: storage.length == 0 ? line : "\n" + line, attributes: attributes))
        eventLogLineCount += 1
        if eventLogLineCount > Self.maxEventLogLines {
            let firstLineEnd = (storage.string as NSString).range(of: "\n")
            if firstLineEnd.location != NSNotFound {
                storage.deleteCharacters(in: NSRange(location: 0, length: firstLineEnd.location + 1))
                eventLogLineCount -= 1
            }
        }
        storage.endEditing()

        eventLogTextView.scrollRangeToVisible(NSRange(location: storage.length, length: 0))
    }

    /// Gives the feed more room in landscape on iPhone.
    private func updateEventLogHeight() {
        eventLogHeightConstraint.constant = traitCollection.verticalSizeClass == .compact ? 70 : 150
    }
}
