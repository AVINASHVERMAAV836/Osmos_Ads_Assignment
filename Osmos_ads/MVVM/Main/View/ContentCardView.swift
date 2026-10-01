//
//  ContentCardView.swift
//  Osmos_ads
//
//  Placeholder publisher content placed between ads so the feed scrolls and
//  ads start off-screen (exercising the 50% visibility rule).
//

import UIKit

final class ContentCardView: UIView {

    init(index: Int) {
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous

        let titleLabel = UILabel()
        titleLabel.text = "Article \(index)"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true

        let bodyLabel = UILabel()
        bodyLabel.text = "Sample publisher content. Scroll through the feed – each banner fires its impression only once, when at least half of it is on screen."
        bodyLabel.font = .preferredFont(forTextStyle: .subheadline)
        bodyLabel.adjustsFontForContentSizeCategory = true
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 0

        let stack = UIStackView(arrangedSubviews: [titleLabel, bodyLabel])
        stack.axis = .vertical
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
