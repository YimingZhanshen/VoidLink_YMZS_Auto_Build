//
//  PencilTipOffsetCalibrationViewController.swift
//  VoidLink
//
//  Created by True砖家 on 2026/7/30.
//  Copyright © 2026 True砖家 on Bilibili. All rights reserved.
//

import UIKit

private enum PencilTipOffsetCalibrationLayout {
    static let containerWidth: CGFloat = 430
    static let containerHeight: CGFloat = 430
    static let navBarHeight: CGFloat = 50
    static let canvasTop: CGFloat = 66
    static let canvasWidth: CGFloat = 320
    static let canvasHeight: CGFloat = 260
    static let sliderTopSpacing: CGFloat = 18
    static let horizontalInset: CGFloat = 30
}

private final class PencilTipOffsetCanvasView: UIView {
    var offset: CGPoint = .zero {
        didSet { setNeedsDisplay() }
    }

    private var rawTouchPoint: CGPoint? {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = false
        backgroundColor = UIColor(white: 0.97, alpha: 1)
        layer.borderColor = UIColor.black.withAlphaComponent(0.12).cgColor
        layer.borderWidth = 0.5
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        context.setLineWidth(1)
        context.setStrokeColor(UIColor.black.withAlphaComponent(0.14).cgColor)
        context.move(to: CGPoint(x: 0, y: center.y))
        context.addLine(to: CGPoint(x: bounds.maxX, y: center.y))
        context.move(to: CGPoint(x: center.x, y: 0))
        context.addLine(to: CGPoint(x: center.x, y: bounds.maxY))
        context.strokePath()

        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(2)
        context.move(to: center)
        context.addLine(to: CGPoint(x: center.x + offset.x, y: center.y + offset.y))
        context.strokePath()

        if let rawTouchPoint {
            drawLandingPreview(in: context, rawPoint: rawTouchPoint)
        }

        context.setFillColor(UIColor.black.withAlphaComponent(0.22).cgColor)
        context.fillEllipse(in: CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10))

        let tipCenter = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
        context.setFillColor(UIColor.systemBlue.cgColor)
        context.fillEllipse(in: CGRect(x: tipCenter.x - 5, y: tipCenter.y - 5, width: 10, height: 10))
    }

    private func drawLandingPreview(in context: CGContext, rawPoint: CGPoint) {
        let correctedPoint = CGPoint(x: rawPoint.x + offset.x, y: rawPoint.y + offset.y)

        context.setFillColor(UIColor.black.withAlphaComponent(0.28).cgColor)
        context.fillEllipse(in: CGRect(x: rawPoint.x - 5, y: rawPoint.y - 5, width: 10, height: 10))

        context.setFillColor(UIColor.systemBlue.cgColor)
        context.fillEllipse(in: CGRect(x: correctedPoint.x - 5, y: correctedPoint.y - 5, width: 10, height: 10))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateTouchPoint(from: touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateTouchPoint(from: touches)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        updateTouchPoint(from: touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        rawTouchPoint = nil
    }

    private func updateTouchPoint(from touches: Set<UITouch>) {
        guard let touch = touches.first(where: { $0.type == .pencil }) else { return }
        rawTouchPoint = touch.preciseLocation(in: self)
    }
}

@objc class PencilTipOffsetCalibrationViewController: UIViewController, UIGestureRecognizerDelegate {
    private let container = UIView()
    private let canvasView = PencilTipOffsetCanvasView()
    private let xSlider = UISlider()
    private let ySlider = UISlider()
    private let xLabel = UILabel()
    private let yLabel = UILabel()
    private var saveButton = UIBarButtonItem()
    private var persistedOffset: CGPoint = .zero
    private var currentOffset: CGPoint = .zero

    override func viewDidLoad() {
        super.viewDidLoad()

        view.isOpaque = false
        view.backgroundColor = UIColor.clear
        if #available(iOS 13.0, *) {
            overrideUserInterfaceStyle = .light
        }

        loadPersistedOffset()
        setupContainer()
        setupNavigationBar()
        setupCanvas()
        setupSliders()
        applyOffset(currentOffset)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pencilProPurchaseAborted(_:)),
            name: AddOnProduct.PencilProPack.purchaseAbortedNotification(),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(persistOffset),
            name: AddOnProduct.PencilProPack.purchaseSucceededNotification(),
            object: nil
        )

        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissSelf))
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    private func loadPersistedOffset() {
        let dataMan = DataManager()
        let settings = dataMan.retrieveSettings()
        persistedOffset = CGPoint(
            x: CGFloat(settings?.pencilTipOffsetX?.floatValue ?? 0),
            y: CGFloat(settings?.pencilTipOffsetY?.floatValue ?? 0)
        )
        currentOffset = persistedOffset
    }

    private func setupContainer() {
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = .white
        container.layer.cornerRadius = 12
        container.layer.masksToBounds = true
        container.layer.borderWidth = 0.5
        container.layer.borderColor = UIColor.black.withAlphaComponent(0.15).cgColor
        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalToConstant: PencilTipOffsetCalibrationLayout.containerWidth),
            container.heightAnchor.constraint(equalToConstant: PencilTipOffsetCalibrationLayout.containerHeight)
        ])
    }

    private func setupNavigationBar() {
        let navBar = UINavigationBar()
        navBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(navBar)

        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.shadowColor = nil
            appearance.backgroundColor = .white
            navBar.standardAppearance = appearance
            navBar.scrollEdgeAppearance = appearance
        } else {
            navBar.setBackgroundImage(UIImage(), for: .default)
            navBar.shadowImage = UIImage()
            navBar.isTranslucent = true
            navBar.backgroundColor = .clear
        }

        saveButton = UIBarButtonItem(title: LocalizationHelper.localizedString(forKey: "Save"), style: .plain, target: self, action: #selector(saveTapped))
        let resetButton = UIBarButtonItem(title: LocalizationHelper.localizedString(forKey: "Reset"), style: .plain, target: self, action: #selector(resetTapped))
        let navItem = UINavigationItem(title: LocalizationHelper.localizedString(forKey: "Pencil Tip Offset"))
        navItem.leftBarButtonItems = [resetButton]
        navItem.rightBarButtonItems = [saveButton]

        if #available(iOS 26.0, *) {
            resetButton.hidesSharedBackground = true
            saveButton.hidesSharedBackground = true
            resetButton.tintColor = .tintColor
            saveButton.tintColor = .tintColor
        }

        navBar.items = [navItem]

        NSLayoutConstraint.activate([
            navBar.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor),
            navBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            navBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            navBar.heightAnchor.constraint(equalToConstant: PencilTipOffsetCalibrationLayout.navBarHeight)
        ])
    }

    private func setupCanvas() {
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(canvasView)

        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: container.topAnchor, constant: PencilTipOffsetCalibrationLayout.canvasTop),
            canvasView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            canvasView.widthAnchor.constraint(equalToConstant: PencilTipOffsetCalibrationLayout.canvasWidth),
            canvasView.heightAnchor.constraint(equalToConstant: PencilTipOffsetCalibrationLayout.canvasHeight)
        ])
    }

    private func setupSliders() {
        let sliderStack = UIStackView()
        sliderStack.axis = .vertical
        sliderStack.spacing = 10
        sliderStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(sliderStack)

        configureSlider(xSlider, action: #selector(sliderMoved(_:)))
        configureSlider(ySlider, action: #selector(sliderMoved(_:)))
        configureLabel(xLabel)
        configureLabel(yLabel)

        sliderStack.addArrangedSubview(makeSliderRow(label: xLabel, slider: xSlider))
        sliderStack.addArrangedSubview(makeSliderRow(label: yLabel, slider: ySlider))

        NSLayoutConstraint.activate([
            sliderStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: PencilTipOffsetCalibrationLayout.horizontalInset),
            sliderStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -PencilTipOffsetCalibrationLayout.horizontalInset),
            sliderStack.topAnchor.constraint(equalTo: canvasView.bottomAnchor, constant: PencilTipOffsetCalibrationLayout.sliderTopSpacing)
        ])

        xSlider.value = Float(currentOffset.x)
        ySlider.value = Float(currentOffset.y)
        updateLabels()
    }

    private func configureSlider(_ slider: UISlider, action: Selector) {
        slider.minimumValue = -15
        slider.maximumValue = 15
        slider.addTarget(self, action: action, for: .valueChanged)
        if PublicUtils.liquidGlassEnabled, #available(iOS 13.0, *) {
            slider.maximumTrackTintColor = .tertiarySystemFill
        }
    }

    private func configureLabel(_ label: UILabel) {
        label.font = UIFont.systemFont(ofSize: 14)
        label.textColor = .black
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
    }

    private func makeSliderRow(label: UILabel, slider: UISlider) -> UIStackView {
        let row = UIStackView(arrangedSubviews: [label, slider])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        return row
    }

    @objc private func sliderMoved(_ sender: UISlider) {
        currentOffset = CGPoint(x: CGFloat(xSlider.value), y: CGFloat(ySlider.value))
        applyOffset(currentOffset)
    }

    private func applyOffset(_ offset: CGPoint) {
        canvasView.offset = offset
        updateLabels()
    }

    private func updateLabels() {
        xLabel.text = "\(LocalizationHelper.localizedString(forKey: "X Offset")): \(String(format: "%.1f", currentOffset.x))"
        yLabel.text = "\(LocalizationHelper.localizedString(forKey: "Y Offset")): \(String(format: "%.1f", currentOffset.y))"
    }

    @objc private func resetTapped() {
        xSlider.value = 0
        ySlider.value = 0
        currentOffset = .zero
        applyOffset(currentOffset)
    }

    @objc private func persistOffset() {
        let dataMan = DataManager()
        guard let settings = dataMan.retrieveSettings() else { return }
        settings.pencilTipOffsetX = NSNumber(value: Float(currentOffset.x))
        settings.pencilTipOffsetY = NSNumber(value: Float(currentOffset.y))
        dataMan.saveData()
        persistedOffset = currentOffset
        PencilHandler.shared?.updatePencilTipOffset(x: currentOffset.x, y: currentOffset.y)

        DispatchQueue.main.async {
            AlertControllerUtil.autoCompletion = true
            AlertControllerUtil.showAlert(
                in: self,
                title: "",
                message: LocalizationHelper.localizedString(forKey: "Pencil tip offset saved"),
                withCancel: false,
                buttonTitle: "",
                countdown: 1
            )
        }
    }

    @objc private func saveTapped() {
        saveButton.isEnabled = false
        IAPManager.checkPurchaseInfo(.PencilProPack) { info in
            self.saveButton.isEnabled = true
            if info.valid {
                self.persistOffset()
            } else {
                IAPManager.inAppPurchaseAction(viewController: self, product: .PencilProPack)
            }
        }
    }

    @objc private func pencilProPurchaseAborted(_ notification: Notification) {
        guard let interruption = notification.object as? PurchaseInterruption else { return }
        if interruption == .lowOSVersion {
            AlertControllerUtil.showAlert(
                in: self,
                title: "",
                message: LocalizationHelper.localizedString(forKey:"PencilProPackLowOSVersionTip"),
                withCancel: false,
                buttonTitle: LocalizationHelper.localizedString(forKey: "OK"),
                countdown: 0
            )
        }
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        return touch.view == view
    }
}
