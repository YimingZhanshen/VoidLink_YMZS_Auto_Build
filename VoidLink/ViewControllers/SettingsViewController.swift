//
//  SettingsViewController.m -> SettingsViewController.swift
//  Moonlight
//
//  Created by Diego Waxemberg on 10/27/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.6.1
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.
//

import UIKit
import GameController

@objc protocol RearNavigationBarMenuDelegate: NSObjectProtocol {
    @objc optional func switchToFavoriteSettings()
    @objc optional func switchToAllSettings()
    @objc optional func getSettingsMenuMode() -> SettingsMenuMode
    @objc optional func enterRemoveSettingItemMode()
    @objc optional func doneRemoveSettingItem()
    @objc optional func layoutSettingsView()
}

// Preserve the unqualified class name stored in the existing storyboards.
@objc(SettingsViewController)
@objcMembers
final class SettingsViewController: UIViewController, RearNavigationBarMenuDelegate, UITextFieldDelegate, UIScrollViewDelegate {
#if !os(tvOS)
    @IBOutlet var navigationBar: UINavigationBar!
    var micHandler: MicHandler?
    weak var layoutOnScreenControlsVC: LayoutOnScreenControlsViewController?
#else
    // The layout controller is not built for tvOS; this legacy weak slot stays nil there.
    weak var layoutOnScreenControlsVC: UIViewController?
#endif
    @IBOutlet var scrollView: UIScrollView!
    var parentStack: UIStackView!
    weak var mainFrameViewController: MainFrameViewController?
    var controllerNavigationHighlightOverlayView: UIView?
    private(set) var currentSettingsMenuMode: SettingsMenuMode = .all

    private var tempSettings: TemporarySettings?
    private var dataMan: DataManager?
    private var oscProfileMan: OSCProfilesManager?
    private var oscProfile: OSCProfile?
    private var parentStackLeadingConstraint: NSLayoutConstraint?
    private var parentStackWidthConstraint: NSLayoutConstraint?
    private var parentStackCenterXConstraint: NSLayoutConstraint?
    private var bitrate = 0
    private var lastSelectedResolutionIndex = 0
    private var softKeyboardHeight: CGFloat = 0
    private var settingsViewJustLoaded = false
    private var settingsViewJustExpanded = false
    private var settingsViewAlreadyAppeared = false
    private var oswLayoutFingers: UInt16 = 0
#if !os(tvOS)
    private var slideToCloseSettingsViewRecognizer: CustomEdgeSlideGestureRecognizer?
#else
    private var didConsumeTvOSInitialSettingsSnapshot = false
#endif
    private var settingStackDict: NSMutableDictionary?
    private var favoriteSettingStackIdentifiers: NSMutableArray?
    private var settingStackWillBeRelocatedToLowestPosition = false
    private var snapshot: UIView?
    private var capturedStack: UIStackView?
    private var autoScrollDisplayLink: CADisplayLink?
    private var scrollSpeed: CGFloat = 0
    private var currentRefreshRate: CGFloat = 0
    private var touchControlSection: MenuSectionView?
    private var controllerSection: MenuSectionView?
    private var motionControlSection: MenuSectionView?
    private var videoSection: MenuSectionView?
    private var otherSection: MenuSectionView?
    private var experimentalSection: MenuSectionView?
    private var hiddenStacks: NSMutableSet?
    private var capturedController: GCController?

    override func viewDidLoad() {
        dataMan = DataManager()
#if os(tvOS)
        tempSettings = (UIApplication.shared.delegate as? AppDelegate)?.peekTvOSInitialSettingsSnapshot()
#endif
        if tempSettings == nil { tempSettings = dataMan?.getSettings() }
        currentSettingsMenuMode = SettingsMenuMode(rawValue: tempSettings?.settingsMenuMode.intValue ?? 0) ?? .all
        if #available(iOS 14.0, tvOS 14.0, *) {
#if !os(tvOS)
            let recognizer = CustomEdgeSlideGestureRecognizer(target: self, action: #selector(edgeSwiped))
            recognizer.edges = .left
            recognizer.normalizedThresholdDistance = 0
            recognizer.edgeTolerance = 10
            recognizer.immediateTriggering = true
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            view.addGestureRecognizer(recognizer)
            slideToCloseSettingsViewRecognizer = recognizer
#else
            restoresFocusAfterTransition = false
#endif
            installSwiftUISettingsIfNeeded()
            return
        }
    }

#if os(tvOS)
    func initialSettingsSnapshotForSwiftUI() -> TemporarySettings? { tempSettings }

    func consumeTvOSInitialSettingsSnapshotForMenuPresentation() {
        guard !didConsumeTvOSInitialSettingsSnapshot else { return }
        didConsumeTvOSInitialSettingsSnapshot = true
        _ = (UIApplication.shared.delegate as? AppDelegate)?.consumeTvOSInitialSettingsSnapshot()
    }
#endif

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(false)
        if #available(iOS 14.0, *), usesSwiftUISettings {
            NotificationCenter.default.addObserver(self, selector: #selector(updateTheme), name: Notification.Name(ThemeManager.ThemeDidChangeNotification), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(reloadSwiftUISettings), name: Notification.Name("GameProfileSelectorCloseNotification"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(reloadSwiftUISettings), name: Notification.Name("GameProfileSelectedNotification"), object: nil)
            reloadSwiftUISettings()
            return
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(false)
        if #available(iOS 14.0, *), usesSwiftUISettings {
            refreshSectionHitTesting()
            if ControllerNavigator.radialMenuView?.superview != nil { ControllerNavigator.updateRadialMenu() }
            return
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(false)
        NotificationCenter.default.post(name: Notification.Name("SettingsViewClosedNotification"), object: self)
        if #available(iOS 14.0, *), usesSwiftUISettings {
            applySwiftUIClosingEffects()
            return
        }
    }

    func getSettingsMenuMode() -> SettingsMenuMode {
        if #available(iOS 14.0, *), usesSwiftUISettings {
            return SettingsMenuMode(rawValue: swiftUISettingsMenuModeRawValue()) ?? .all
        }
        return currentSettingsMenuMode
    }

    func initParentStack() {
        scrollView?.contentInsetAdjustmentBehavior = .automatic
        scrollView?.delegate = self
        scrollView?.alwaysBounceVertical = true
        scrollView?.showsVerticalScrollIndicator = false
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        parentStack = stack
        if stack.superview == nil, let scrollView {
            scrollView.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: currentSettingsMenuMode == .all ? GenericUtils.settingsMenuNavigationBarHeight : GenericUtils.settingsMenuNavigationBarHeight + 10),
                stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20)
            ])
        }
    }

    func switchToFavoriteSettings() {
        if #available(iOS 14.0, *), usesSwiftUISettings {
            currentSettingsMenuMode = .favorite
            setSwiftUISettingsMenuMode(SettingsMenuMode.favorite.rawValue)
            DispatchQueue.main.async {
                if ControllerNavigator.radialMenuView?.superview != nil { ControllerNavigator.updateRadialMenu() }
                GamepadNavigationIllustrationHud.updateHud(forceDisplay: false)
                if ControllerUtil.primaryGCController != nil { ControllerNavigator.restoreSettingsModeSwitchHighlight() }
            }
            return
        }
    }

    func switchToAllSettings() {
        if #available(iOS 14.0, tvOS 14.0, *), usesSwiftUISettings {
            currentSettingsMenuMode = .all
            setSwiftUISettingsMenuMode(SettingsMenuMode.all.rawValue)
            DispatchQueue.main.async {
                if ControllerNavigator.radialMenuView?.superview != nil { ControllerNavigator.updateRadialMenu() }
                GamepadNavigationIllustrationHud.updateHud(forceDisplay: false)
                if ControllerUtil.primaryGCController != nil { ControllerNavigator.restoreSettingsModeSwitchHighlight() }
            }
            return
        }
    }

    func expandGamepadSection() {
        if currentSettingsMenuMode == .favorite { switchToAllSettings() }
        if #available(iOS 14.0, *), usesSwiftUISettings { expandSection(identifier: "SettingsSectionController") }
    }

    func enterRemoveSettingItemMode() {
        if #available(iOS 14.0, *), usesSwiftUISettings {
            currentSettingsMenuMode = .removeSettingItem
            setSwiftUISettingsMenuMode(SettingsMenuMode.removeSettingItem.rawValue)
            return
        }
    }

    func doneRemoveSettingItem() {
        if #available(iOS 14.0, *), usesSwiftUISettings {
            currentSettingsMenuMode = .favorite
            setSwiftUISettingsMenuMode(SettingsMenuMode.favorite.rawValue)
            return
        }
    }

    func mainFrameGameProfileButtonTapped(_ animated: Bool) {
        definesPresentationContext = false
        if #available(iOS 14.0, *), usesSwiftUISettings { persistSwiftUIGameProfileSettings() }
#if !os(tvOS)
        guard let layout = instantiateOscLayoutViewController() else { return }
        layoutOnScreenControlsVC = layout
        layout.view.backgroundColor = .clear
        layout.modalPresentationStyle = .overCurrentContext
        layout.profileSelectorLoadingMode = .selectProfileFromMainFrame
        present(layout, animated: false) {
            self.layoutOnScreenControlsVC?.presentProfileSelector(with: .selectProfileFromMainFrame, animated: animated)
        }
        layout.toolbarStackView.isHidden = true
        layout.toolbarRootView.isHidden = true
#else
        let selector = ProfileSelectorViewController()
        selector.loadingMode = .selectProfileFromMainFrame
        selector.modalPresentationStyle = .overCurrentContext
        present(selector, animated: animated)
#endif
    }

#if !os(tvOS)
    func edgeSwiped() { mainFrameViewController?.closeSettingView(animated: true) }

    func deviceOrientationDidChange(_ notification: Notification) {
        if #available(iOS 14.0, *), usesSwiftUISettings { return }
        updateParentStackHorizontalConstraints()
    }

    func instantiateOscLayoutViewController() -> LayoutOnScreenControlsViewController? {
        let isIPhone = UIDevice.current.userInterfaceIdiom == .phone
        let storyboardName = isIPhone ? "iPhone" : "iPad"
        let controller = UIStoryboard(name: storyboardName, bundle: nil).instantiateViewController(withIdentifier: "LayoutOnScreenControlsViewController")
        NSLog("[OSC] storyboard=%@ instantiated class=%@", storyboardName, NSStringFromClass(type(of: controller)))
        guard let layout = controller as? LayoutOnScreenControlsViewController else {
            assertionFailure("Expected LayoutOnScreenControlsViewController, got \(type(of: controller))")
            return nil
        }
        // Storyboard outlets are connected only after the controller's view loads.
        layout.loadViewIfNeeded()
        layout.toolbarStackView.isHidden = false
        layout.toolbarRootView.isHidden = false
        return layout
    }

    func updateParentStackHorizontalConstraints() {
        guard let parentStack else { return }
        if !PublicUtils.isIPhone {
            if let center = parentStackCenterXConstraint, let width = parentStackWidthConstraint { NSLayoutConstraint.deactivate([center, width]) }
            let center = parentStack.centerXAnchor.constraint(equalTo: view.centerXAnchor)
            let width = parentStack.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -20)
            parentStackCenterXConstraint = center
            parentStackWidthConstraint = width
            NSLayoutConstraint.activate([center, width])
            return
        }
        let keyWindow = UIApplication.shared.windows.first
        if #available(iOS 13.0, *) {
            if let leading = parentStackLeadingConstraint, let width = parentStackWidthConstraint { NSLayoutConstraint.deactivate([leading, width]) }
            let activeScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            let orientation = activeScene?.activationState == .foregroundActive ? activeScene?.interfaceOrientation : keyWindow?.windowScene?.interfaceOrientation
            if let leading = parentStackLeadingConstraint, let width = parentStackWidthConstraint { NSLayoutConstraint.deactivate([leading, width]) }
            let leading: NSLayoutConstraint
            let width: NSLayoutConstraint
            if orientation == .landscapeRight {
                leading = parentStack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor)
                width = parentStack.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, constant: -10)
            } else {
                leading = parentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10)
                width = parentStack.widthAnchor.constraint(equalTo: view.widthAnchor, constant: -20)
            }
            parentStackLeadingConstraint = leading
            parentStackWidthConstraint = width
            NSLayoutConstraint.activate([leading, width])
        }
    }
#endif

    override func viewDidLayoutSubviews() {
        if #available(iOS 14.0, *), usesSwiftUISettings {
            refreshSwiftUISettings()
            return
        }
        var highestViewY: CGFloat = 0
        for child in scrollView?.subviews ?? [] {
#if os(tvOS)
            let isSlider = NSClassFromString("UISlider").map { child.isKind(of: $0) } ?? false
#else
            let isSlider = child is UISlider
#endif
            guard child is UILabel || child is UISegmentedControl || isSlider else { continue }
            highestViewY = max(highestViewY, child.frame.maxY)
        }
        if let scrollView {
            scrollView.contentSize = CGSize(width: scrollView.contentSize.width, height: (parentStack?.frame.height ?? 0) + GenericUtils.settingsMenuNavigationBarHeight + 20)
        }
    }

    override func viewSafeAreaInsetsDidChange() { super.viewSafeAreaInsetsDidChange() }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        if #available(iOS 14.0, *), usesSwiftUISettings {
            stopSwiftUISettingsScrollViewImmediately()
            coordinator.animate(alongsideTransition: nil) { _ in self.refreshSwiftUISettingsGeometry() }
            return
        }
    }

#if !os(tvOS)
    func invokeOscLayout() {
        guard let layout = instantiateOscLayoutViewController() else { return }
        layoutOnScreenControlsVC = layout
        layout.view.backgroundColor = UIColor(white: 0.55, alpha: 1)
        layout.modalPresentationStyle = .fullScreen
        present(layout, animated: true)
    }
#else
    var canBecomeFocused: Bool { false }
    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        VoidLinkTvOSShouldUpdateFocus(context, view.window)
    }
#endif

    func layoutSettingsView() {
        if #available(iOS 14.0, *), usesSwiftUISettings {
            view.setNeedsLayout()
            view.layoutIfNeeded()
            refreshSectionHitTesting()
            return
        }
#if !os(tvOS)
        scrollView?.layoutSubviews()
        for case let stack as UIStackView in hiddenStacks ?? NSSet() { stack.isHidden = true }
        if currentSettingsMenuMode == .all {
            for case let section as MenuSectionView in parentStack?.arrangedSubviews ?? [] { section.updateViewForFoldState() }
        }
#endif
    }

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if GenericUtils.autoPopSoftKeyboard { return true }
        GenericUtils.autoPopSoftKeyboard = true
        return false
    }

    func updateTheme() {
        if #available(iOS 14.0, *), usesSwiftUISettings {
            view.backgroundColor = ThemeManager.menuBackgroundColor
            refreshSwiftUISettingsTheme()
            return
        }
    }

    func saveSettings() {
        if #available(iOS 14.0, *), usesSwiftUISettings {
            persistSwiftUISettings()
            return
        }
    }

    override func didReceiveMemoryWarning() { super.didReceiveMemoryWarning() }
}

#if !os(tvOS)
@available(iOS 13.0, *)
extension SettingsViewController: WidgetPickerViewControllerDelegate {
    func widgetPickerViewController(_ controller: WidgetPickerViewController, didCreateWidget payload: NSDictionary) {
        let profileManager = OSCProfilesManager.sharedManager(.zero)
        let profile = profileManager.getSelectedProfile()
        guard let command = payload["cmdString"] as? String else { return }

        switch payload["shortcutIdentifier"] as? String {
        case "eraser":
            profile.eraserShortcut = command
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                PencilHandler.enterBrushShortcut(in: self)
            }
        case "brush":
            profile.brushShortcut = command
        case "squeezePress":
            profile.squeezeStartShortcut = command
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                PencilHandler.enterSqueezeEndShortcut(in: self)
            }
        case "squeezeRelease":
            profile.squeezeEndShortcut = command
        default:
            break
        }

        profileManager.replaceSelectedProfile(with: profile, overwriteDefault: true)
    }
}
#endif
