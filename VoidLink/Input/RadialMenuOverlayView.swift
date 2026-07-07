//
//  RadialMenuOverlayView.swift
//  VoidLink
//
//  Created by Codex on 2026/7/1.
//  Copyright © 2026 True砖家 on Bilibili. All rights reserved.
//

import SwiftUI
import UIKit

@available(iOS 13.0, *)
final class RadialMenuOverlayView: UIView {
    private enum Metrics {
        static let diameter: CGFloat = 260
        static let bottomInset: CGFloat = 92
    }

    private let selectionState = RadialMenuSelectionState()
    private var hostingController: UIHostingController<RadialMenuView>?

    static var menuSectors: [RadialMenuSector] = []

    init() {
        super.init(frame: .zero)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    static func presentInKeyWindow() -> RadialMenuOverlayView? {
        guard let window = keyWindow() else { return nil }

        let overlayView = RadialMenuOverlayView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(overlayView)

        NSLayoutConstraint.activate([
            overlayView.widthAnchor.constraint(equalToConstant: Metrics.diameter),
            overlayView.heightAnchor.constraint(equalToConstant: Metrics.diameter),
            overlayView.centerXAnchor.constraint(equalTo: window.centerXAnchor),
            overlayView.bottomAnchor.constraint(equalTo: window.safeAreaLayoutGuide.bottomAnchor, constant: -Metrics.bottomInset)
        ])

        return overlayView
    }

    func updateSelection(xOffset: Float, yOffset: Float) -> RadialMenuItem? {
        let previousSelectedIndex = selectionState.selectedIndex
        selectionState.updateSelection(xOffset: xOffset, yOffset: yOffset)

        guard previousSelectedIndex != nil, selectionState.selectedIndex == nil else {
            return nil
        }

        guard let previousSelectedIndex,
              Self.menuSectors.indices.contains(previousSelectedIndex) else {
            return nil
        }

        return Self.menuSectors[previousSelectedIndex].item
    }

    func dismiss() {
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()
        hostingController = nil
        removeFromSuperview()
    }

    private func setupView() {
        backgroundColor = .clear
        isUserInteractionEnabled = false
        clipsToBounds = false

        let radialMenuView = RadialMenuView(
            sectors: Self.menuSectors,
            isTouchSelectionEnabled: false,
            selectionState: selectionState
        )

        let hostingController = UIHostingController(rootView: radialMenuView)
        hostingController.view.backgroundColor = .clear
        hostingController.view.isUserInteractionEnabled = false
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false

        self.hostingController = hostingController
        addSubview(hostingController.view)

        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: bottomAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.windows.first(where: { $0.isKeyWindow }) ?? UIApplication.shared.windows.first
    }
}
