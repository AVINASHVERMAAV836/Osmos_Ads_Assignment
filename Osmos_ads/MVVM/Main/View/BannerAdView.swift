//
//  BannerAdView.swift
//  Osmos_ads
//
//  Manually renders a single banner creative: image, "Sponsored" badge, loading and fallback states.
//

import UIKit

final class BannerAdView: UIView {

    enum RenderState {
        case loading
        case rendered
        case failed
    }

    let ad: BannerAd
    let position: Int

    /// Called when the user taps a rendered ad.
    var onTap: ((BannerAdView) -> Void)?
    /// Called once the image finished loading (or failed).
    var onRenderResult: ((BannerAdView, Result<Void, AdError>) -> Void)?

    private(set) var renderState: RenderState = .loading

    /// Largest height an ad may take, so small square creatives don't fill the whole screen.
    private static let maxImageHeight: CGFloat = 320
    /// Used until the image is downloaded when the response has no width/height.
    private static let fallbackAspectRatio: CGFloat = 9.0 / 16.0

    private let imageView = UIImageView()
    private let badgeLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let fallbackLabel = UILabel()
    private var aspectRatioConstraint: NSLayoutConstraint?
    private var loadTask: Task<Void, Never>?

    init(ad: BannerAd, position: Int) {
        self.ad = ad
        self.position = position
        super.init(frame: .zero)
        configureViews()
        configureAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    isolated deinit {
        loadTask?.cancel()
    }

    // MARK: - Loading

    func loadImage(using loader: ImageLoader = .shared) {
        guard loadTask == nil else { return }
        setRenderState(.loading)

        loadTask = Task { [weak self, url = ad.imageURL] in
            do {
                let image = try await loader.image(for: url)
                self?.show(image)
            } catch {
                self?.showFailure(AdError.from(error))
            }
        }
    }

    private func show(_ image: UIImage) {
        imageView.image = image
        // Prefer the size declared in the response; fall back to the real image size.
        if ad.aspectRatio == nil, image.size.width > 0 {
            setAspectRatio(image.size.height / image.size.width)
        }
        setRenderState(.rendered)
        onRenderResult?(self, .success(()))
    }

    private func showFailure(_ error: AdError) {
        guard error != .cancelled else { return }
        setRenderState(.failed)
        onRenderResult?(self, .failure(error))
    }

    private func setRenderState(_ state: RenderState) {
        renderState = state
        switch state {
        case .loading:
            spinner.startAnimating()
            fallbackLabel.isHidden = true
            badgeLabel.isHidden = true
        case .rendered:
            spinner.stopAnimating()
            fallbackLabel.isHidden = true
            badgeLabel.isHidden = false
        case .failed:
            spinner.stopAnimating()
            fallbackLabel.isHidden = false
            badgeLabel.isHidden = true
            imageView.image = nil
        }
        // Only a rendered ad is tappable.
        isUserInteractionEnabled = state == .rendered
        accessibilityTraits = state == .rendered ? [.button, .image] : [.image]
        accessibilityLabel = state == .failed ? "Ad not available" : "Sponsored banner ad"
    }

    // MARK: - Layout

    private func configureViews() {
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .tertiarySystemFill
        addSubview(imageView)

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.text = " Sponsored "
        badgeLabel.font = .preferredFont(forTextStyle: .caption2)
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.textColor = .white
        badgeLabel.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        badgeLabel.layer.cornerRadius = 4
        badgeLabel.clipsToBounds = true
        addSubview(badgeLabel)

        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.hidesWhenStopped = true
        addSubview(spinner)

        fallbackLabel.translatesAutoresizingMaskIntoConstraints = false
        fallbackLabel.text = "Ad not available"
        fallbackLabel.font = .preferredFont(forTextStyle: .subheadline)
        fallbackLabel.adjustsFontForContentSizeCategory = true
        fallbackLabel.textColor = .secondaryLabel
        fallbackLabel.textAlignment = .center
        addSubview(fallbackLabel)

        let padding: CGFloat = 8
        // The image fills the card width unless that would exceed the max height; then it is centered.
        let fillWidth = imageView.widthAnchor.constraint(equalTo: widthAnchor, constant: -padding * 2)
        fillWidth.priority = .defaultHigh

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: padding),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -padding * 2),
            imageView.heightAnchor.constraint(lessThanOrEqualToConstant: Self.maxImageHeight),
            fillWidth,

            badgeLabel.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 6),
            badgeLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 6),

            spinner.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),

            fallbackLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            fallbackLabel.leadingAnchor.constraint(equalTo: imageView.leadingAnchor, constant: 8),
            fallbackLabel.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -8),
        ])

        setAspectRatio(ad.aspectRatio.map { CGFloat($0) } ?? Self.fallbackAspectRatio)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    /// Keeps the image at the creative's aspect ratio (height = width * ratio) in every orientation.
    private func setAspectRatio(_ ratio: CGFloat) {
        aspectRatioConstraint?.isActive = false
        let constraint = imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor, multiplier: ratio)
        constraint.isActive = true
        aspectRatioConstraint = constraint
    }

    private func configureAccessibility() {
        isAccessibilityElement = true
        accessibilityHint = ad.destinationURL == nil ? nil : "Opens the advertiser's page"
    }

    @objc private func handleTap() {
        guard renderState == .rendered else { return }
        onTap?(self)
    }
}
