//
//  ControllerNavigator.swift
//  VoidLink
//
//  Created by True砖家 on 2026/7/1.
//  Copyright © 2026 True砖家 on Bilibili. All rights reserved.
//

import Foundation
import GameController
import ObjectiveC
import UIKit

final class ControllerNavigationElement: NSObject {
    var control:ControllerElement
    var action:String
    var isInAction:Bool = false
    init(control: ControllerElement, action: String){
        self.control = control
        self.action = action
    }
}

private var controllerNavigationSelectedIndexPathKey: UInt8 = 0
private var controllerNavigationPersistTokenKey: UInt8 = 0
private let settingsControllerNavigationHighlightedIdentifierKey = "SettingsControllerNavigationHighlightedIdentifier"
private let hostControllerNavigationHighlightedUUIDKey = "HostControllerNavigationHighlightedUUID"

@available(iOS 13.0, *)
private final class ControllerMouseDisplayLinkTarget: NSObject {
    @objc func displayLinkDidFire() {
        ControllerNavigator.controllerMouseDisplayLinkDidFire()
    }
}

@available(iOS 13.0, *)
@objc protocol ControllerNavigatorRadialMenuDelegate: AnyObject {
    func controllerNavigatorDidSelect(item: RadialMenuItem)
}

@available(iOS 13.0, *)
@objc protocol ControllerUINavigationDelegate: AnyObject {
    func getNavigationElements() -> [ControllerNavigationElement]
    func navigateByController(forward: Bool)
    func navigateByController(downward: Bool)
    func uiWidgetActionForControllerNavigator(forward: Bool, from navigation:ControllerNavigationElement)
    func uiButtonActionForControllerNavigator(pressed: Bool, from navigation:ControllerNavigationElement)
    func persistControllerNavigationHighlight()
    func restoreControllerNavigationHighlight()
    func restoreControllerNavigationHighlightAfterSettingsModeSwitch()
}

@available(iOS 13.0, *)
final class ControllerNavigator: NSObject {
    typealias Handler = (_ buttonDict: NSDictionary, _ gamepad: GCExtendedGamepad, _ element: GCControllerElement) -> Void

    private static weak var listeningController: GCController?
    static weak var radialMenuDelegate: ControllerNavigatorRadialMenuDelegate?
    @objc static weak var uiNavigationDelegate: ControllerUINavigationDelegate?
    private static weak var previousUINavigationDelegate: ControllerUINavigationDelegate?
    private static var swapABXY = false
    @objc static var radialMenuView: RadialMenuOverlayView?
    @objc static var stickReleasedInRadialMenu: Bool = false
    @objc static var radialMenuButton: ControllerElement = .leftShoulder
    @objc static var radialMenuButtonPool: NSMutableSet {
        let pool:NSMutableSet = NSMutableSet()
        pool.add(ControllerElement.leftTrigger.rawValue)
        pool.add(ControllerElement.rightTrigger.rawValue)
        pool.add(ControllerElement.leftShoulder.rawValue)
        pool.add(ControllerElement.rightShoulder.rawValue)
        pool.add(ControllerElement.select.rawValue)
        pool.add(ControllerElement.start.rawValue)
        pool.add(ControllerElement.special.rawValue)
        pool.add(ControllerElement.paddle1.rawValue)
        pool.add(ControllerElement.paddle2.rawValue)
        pool.add(ControllerElement.paddle3.rawValue)
        pool.add(ControllerElement.paddle4.rawValue)
        return pool
    }
    
    @objc static var radialMenuButtonPosition: ControllerElementPosition {
        var position:ControllerElementPosition = .undefined
        if radialMenuButton.position != .middle && radialMenuButton.position != .undefined {position = radialMenuButton.position}
        else {
            if radialMenuButton == localRadialMenuButton {position = customPositionForLocalRadialMenuButton}
            if radialMenuButton == streamingRadialMenuButton {position = customPositionForStreamingRadialMenuButton}
        }
        return position
    }

    
    @objc static var enabled: Bool = true {
        didSet{
            if enabled {
                if let settingViewVC = uiNavigationDelegate as? SettingsViewController {
                    settingViewVC.highlightViewForControllerNavigator(by: "controllerNavigationStack")
                    GamepadNavigationIllustrationHud.updateHud()
                }
            }
            else {
                stop()
            }
        }
    }
    
    @objc static var localRadialMenuButton: ControllerElement = .leftShoulder
    @objc static var customPositionForLocalRadialMenuButton: ControllerElementPosition = .left
    @objc static var streamingRadialMenuButton: ControllerElement = .leftShoulder
    @objc static var customPositionForStreamingRadialMenuButton: ControllerElementPosition = .left
    @objc static var streamingRadialMenuDelay: TimeInterval = 0
    
    private static let controllerMouseDisplayLinkTarget = ControllerMouseDisplayLinkTarget()
    private static var controllerMouseDisplayLink: CADisplayLink?
    @objc static var controllerMouseStick: ControllerElement = .rightStick
    @objc static var controllerMouseLeftButton: ControllerElement = .dpadRight
    @objc static var controllerMouseRightButton: ControllerElement = .dpadDown
    @objc static var controllerMouseVelocity: CGFloat = 11.3
    @objc static var controllerMouseExpo: CGFloat = 1.6
    private static var controllerMouseInputX: CGFloat = 0
    private static var controllerMouseInputY: CGFloat = 0
    private static var controllerMouseWheelInputX: CGFloat = 0
    private static var controllerMouseWheelInputY: CGFloat = 0
    private static var controllerMouseFrameRate = 60
    @objc static var controllerMouseEnabled: Bool {
        return radialMenuState == .mouseModeEnabled
    }
    private static var controllerMouseNavigationElements: [ControllerNavigationElement] {
        var elements = [ControllerNavigationElement]()
        elements.append(ControllerNavigationElement(control:ControllerNavigator.controllerMouseStick, action: "moveCursor"))
        elements.append(ControllerNavigationElement(control:ControllerNavigator.controllerMouseLeftButton, action: "leftButton"))
        elements.append(ControllerNavigationElement(control:ControllerNavigator.controllerMouseRightButton, action: "rightButton"))
        elements.append(ControllerNavigationElement(control:ControllerNavigator.controllerMouseStick.position == .left ? .rightStick : .leftStick, action: "verticalHorizontalScroll"))
        return elements
    }
    
    static var settingsFavoriteReorderActive: Bool = false
    static var settingsReadTipPendingToken = 0
    static var settingsReadTipPendingWorkItem: DispatchWorkItem?
    static var settingsReadTipPressedAgain = false
    static var settingsReadTipSuppressNextRelease = false
    
    static var navigationTimer: SafeTimer?
    @objc static weak var controllerNavigationHighlightedView: UIView?
    private static let installAlertControllerNavigationHook: Void = {
        UIAlertController.installControllerNavigationDelegateHook()
    }()

    @objc static func setRadialMenuDelegate(_ delegate: ControllerNavigatorRadialMenuDelegate?) {
        _ = installAlertControllerNavigationHook
        radialMenuDelegate = delegate
    }

    @objc static func setUINavigationDelegate(_ delegate: ControllerUINavigationDelegate?) {
        _ = installAlertControllerNavigationHook
        if let currentDelegate = uiNavigationDelegate,
           let nextDelegate = delegate,
           currentDelegate !== nextDelegate, !(currentDelegate is UIAlertController) {
            previousUINavigationDelegate = currentDelegate
        }

        uiNavigationDelegate = delegate
        updateUINavigationDelegateState()
    }
    
    @objc static func setStreamFrameVCAsUINavigationDelegate() {
        if let delegate: ControllerUINavigationDelegate? = StreamFrameViewController.sharedInstance() {
            _ = installAlertControllerNavigationHook
            if let currentDelegate = uiNavigationDelegate,
               let nextDelegate = delegate,
               currentDelegate !== nextDelegate, !(currentDelegate is UIAlertController) {
                previousUINavigationDelegate = currentDelegate
            }
            uiNavigationDelegate = delegate
            listenToRadialMenuButton()
            GamepadNavigationIllustrationHud.updateHud()
        }
    }

    @objc static func restorePreviousUINavigationDelegate(ifCurrentDelegateIs delegate: ControllerUINavigationDelegate) {
        guard uiNavigationDelegate === delegate else { return }
        /*
        if previousUINavigationDelegate is StreamFrameViewController {
            ControllerSupport.sharedInstance().reinitiatePrimaryController()
            return
        } */
        
        
        uiNavigationDelegate = previousUINavigationDelegate
        // previousUINavigationDelegate = nil
        updateUINavigationDelegateState()
    }

    static func updateUINavigationDelegateState() {
        if uiNavigationDelegate is StreamFrameViewController {
            if radialMenuState == .mouseModeEnabled {
                startControllerMouse()
                // GamepadNavigationIllustrationHud.updateNavigationElements(controllerMouseNavigationElements)
                return
            }
            ControllerSupport.sharedInstance().reinitiatePrimaryController()
            GamepadNavigationIllustrationHud.updateHud()
            return;
        }
        
        restartListening()
        GamepadNavigationIllustrationHud.updateHud()
    }

    @objc static func restoreUINavigationHighlight() {
        guard enabled else {return}
        uiNavigationDelegate?.restoreControllerNavigationHighlight()
    }

    @objc static func persistUINavigationHighlight() {
        guard enabled else {return}
        uiNavigationDelegate?.persistControllerNavigationHighlight()
        if previousUINavigationDelegate !== uiNavigationDelegate {
            previousUINavigationDelegate?.persistControllerNavigationHighlight()
        }
    }

    @objc static func restoreSettingsModeSwitchHighlight() {
        guard enabled else {return}
        uiNavigationDelegate?.restoreControllerNavigationHighlightAfterSettingsModeSwitch()
    }
    
    @objc static func updateHudForCustomRadialMenuButtonPosition() {
        var elements: [ControllerNavigationElement] = []
        elements.append(ControllerNavigationElement(control: .dpadLeft, action: "Left"))
        elements.append(ControllerNavigationElement(control: .dpadRight, action: "Right"))
        elements.append(ControllerNavigationElement(control: .dpadUp, action: "Centered (PlayStation)"))
        GamepadNavigationIllustrationHud.updateNavigationElements(elements, forceDisplay: true)
    }
    
    
    /// Controller Mouse

    @objc static func startControllerMouse() {
        controllerMouseInputX = 0
        controllerMouseInputY = 0
        startControllerMouseDisplayLink(frameRate: controllerMouseFrameRate)
        ControllerUtil.stopListeningPrimaryController()
        listenToControllerMouse()
        DispatchQueue.main.async {
            GamepadNavigationIllustrationHud.updateNavigationElements(controllerMouseNavigationElements)
            DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                GamepadNavigationIllustrationHud.clearHud()
            }
        }
    }
    
    @objc static func configureControllerMouse(with settings: TemporarySettings) {
        // controllerMouseEnabledFlag = false
        controllerMouseStick = ControllerElement(rawValue: settings.controllerMouseStick.int32Value) ?? .rightStick
        controllerMouseLeftButton = ControllerElement(rawValue: settings.controllerMouseLeftButton.int32Value) ?? .dpadRight
        controllerMouseRightButton = ControllerElement(rawValue: settings.controllerMouseRightButton.int32Value) ?? .dpadDown
        controllerMouseExpo = CGFloat(settings.controllerMouseExpo.floatValue)
        controllerMouseFrameRate = max(settings.framerate.intValue, 1)
        controllerMouseVelocity = PublicUtils.controllerMouseVelocity(
            pointerVelocity: CGFloat(settings.controllerMousePointerVelocity.floatValue),
            frameRate: CGFloat(controllerMouseFrameRate)
        )
    }

    /*
    @objc static func stopControllerMouse() {
        controllerMouseEnabledFlag = false
        stopControllerMouseDisplayLink()
    }

    @objc static func setControllerMouseEnabled(_ enabled: Bool) {
        controllerMouseEnabledFlag = mapControllerToMouse && enabled
        if !controllerMouseEnabledFlag {
        }
    }

    @objc static func isControllerMouseEnabled() -> Bool {
        return controllerMouseEnabledFlag
    }
    */
 

    fileprivate static func controllerMouseDisplayLinkDidFire() {
        guard radialMenuState == .mouseModeEnabled,
              let displayLink = controllerMouseDisplayLink else {
            return
        }

        // print("controllerMouseDisplayLinkDidFire \(CACurrentMediaTime())")
        
        let delay = 0.5 / Double(max(displayLink.preferredFramesPerSecond, 1))
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            guard radialMenuState == .mouseModeEnabled else { return }
            let moveVector = PublicUtils.controllerMouseMoveVector(
                stickX: controllerMouseInputX,
                stickY: controllerMouseInputY,
                velocity: controllerMouseVelocity,
                expo: controllerMouseExpo
            )
            if moveVector.dx != 0 || moveVector.dy != 0 {
                LiSendMouseMoveEvent(clampedInt16(moveVector.dx), clampedInt16(moveVector.dy))
            }

            let scrollVector = PublicUtils.controllerMouseScrollVector(
                stickX: controllerMouseWheelInputX,
                stickY: controllerMouseWheelInputY,
                multiplier: 15
            )
            if abs(scrollVector.dy) > abs(scrollVector.dx) {
                LiSendHighResScrollEvent(clampedInt16(scrollVector.dy))
            }
            else {
                LiSendHighResHScrollEvent(clampedInt16(scrollVector.dx))
            }
        }
    }

    private static func startControllerMouseDisplayLink(frameRate: Int) {
        stopControllerMouseDisplayLink()

        let displayLink = CADisplayLink(
            target: controllerMouseDisplayLinkTarget,
            selector: #selector(ControllerMouseDisplayLinkTarget.displayLinkDidFire)
        )
        if #available(iOS 15.0, tvOS 15.0, *) {
            displayLink.preferredFrameRateRange = CAFrameRateRange(
                minimum: Float(frameRate),
                maximum: Float(frameRate),
                preferred: Float(frameRate)
            )
        } else {
            displayLink.preferredFramesPerSecond = frameRate
        }
        displayLink.add(to: .main, forMode: .common)
        controllerMouseDisplayLink = displayLink
    }

    private static func stopControllerMouseDisplayLink() {
        controllerMouseInputX = 0
        controllerMouseInputY = 0
        controllerMouseDisplayLink?.invalidate()
        controllerMouseDisplayLink = nil
    }


    private static func swappedFaceButtonIfNeeded(_ button: ControllerElement, swapABXY: Bool) -> ControllerElement {
        guard swapABXY else { return button }
        switch button {
        case .a:
            return .b
        case .b:
            return .a
        case .x:
            return .y
        case .y:
            return .x
        default:
            return button
        }
    }

    private static func clampedInt16(_ value: CGFloat) -> Int16 {
        let roundedValue = value.rounded()
        if roundedValue > CGFloat(Int16.max) {
            return Int16.max
        }
        if roundedValue < CGFloat(Int16.min) {
            return Int16.min
        }
        return Int16(roundedValue)
    }
    
    /*
    @objc static func start(swapABXY: Bool = false) {
        Self.swapABXY = swapABXY
        installControllerObserversIfNeeded()
        listenFirstAvailableController()
     
    }

*/
    private static func navigateContinuously(forward: Bool) {
            navigationTimer?.clean()
            navigationTimer = SafeTimer(interval: 0.23) {
                uiNavigationDelegate?.navigateByController(forward: forward)
            }
            navigationTimer?.restart()
    }
    
    private static func navigateContinuously(downward: Bool) {
            navigationTimer?.clean()
            navigationTimer = SafeTimer(interval: 0.23) {
                uiNavigationDelegate?.navigateByController(downward: downward)
            }
            navigationTimer?.restart()
    }

    @objc static func start() {
        guard let controller = ControllerUtil.primaryGCController, controller.extendedGamepad != nil else { return }
        restartListening()
        GamepadNavigationIllustrationHud.updateHud()
    }

    @objc static func stop() {
        ControllerUtil.stopListeningPrimaryController(stopListenToRadialMenuButton: true)
        radialMenuView?.dismiss()
        radialMenuView = nil
        GamepadNavigationIllustrationHud.clearHud()
        clearNavigationHighlights()
    }

    @objc static func clearNavigationHighlights() {
        PublicUtils.runOnMain {
            if let mainFrameVC = radialMenuDelegate as? MainFrameViewController {
                mainFrameVC.settingsViewController?.clearControllerNavigationHighlightForControllerNavigator()
                mainFrameVC.hostCollectionVC?.clearCollectionControllerNavigationHighlightForControllerNavigator()
            } else {
                (uiNavigationDelegate as? SettingsViewController)?.clearControllerNavigationHighlightForControllerNavigator()
                (uiNavigationDelegate as? UICollectionViewController)?.clearCollectionControllerNavigationHighlightForControllerNavigator()
            }

            controllerNavigationHighlightedView = nil
        }
    }
    
    private static func performRadialMenuAction(_ item: RadialMenuItem) {
        radialMenuDelegate?.controllerNavigatorDidSelect(item:item)
        switch item {
        case .gameProfiles, .addHost, .aboutView:
            radialMenuView?.dismiss()
            radialMenuView = nil
        case .disconnect:
            if radialMenuState == .disconnectAndQuit {
                radialMenuView?.dismiss()
                radialMenuView = nil
                StreamFrameViewController.sharedInstance().returnToMainFrame()
                break
            }
            else {
                radialMenuState = .disconnectAndQuit
                updateRadialMenu()
                break
            }
        case .quitApp:
            radialMenuView?.dismiss()
            radialMenuView = nil
            StreamFrameViewController.sharedInstance().disconnectAndQuitApp()
        case .more:
            radialMenuState = .moreOptions
            updateRadialMenu()
        case .mouse:
            if radialMenuState != .mouseModeEnabled {
                radialMenuState = .mouseModeEnabled
                updateRadialMenu()
            }
            else {
                stopControllerMouseDisplayLink()
                radialMenuState = .main
                updateRadialMenu()
            }
        case .theme:
            let targetTheme: UIUserInterfaceStyle = ThemeManager.userInterfaceStyle() == .light ? .dark : .light
            DispatchQueue.main.async {
                ThemeManager.setUserInterfaceStyle(targetTheme)
                if let mainFrameVC = radialMenuDelegate as? MainFrameViewController, let settingsViewVC = mainFrameVC.settingsViewController {
                    settingsViewVC.appThemeSelector.selectedSegmentIndex = targetTheme.rawValue
                }
            }
            let dataMan = DataManager()
            let settings = dataMan.retrieveSettings()
            settings?.appTheme = NSNumber(value: targetTheme.rawValue)
            dataMan.saveData()
        case .navigationSettings:
            DispatchQueue.main.async {
                radialMenuView?.dismiss()
                radialMenuView = nil
                if let mainFrameVC = radialMenuDelegate as? MainFrameViewController {
                    mainFrameVC.expandSettingsView()
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.3) {
                        if let settingViewVC = uiNavigationDelegate as? SettingsViewController {
                            settingViewVC.expandGamepadSection()
                            settingViewVC.highlightViewForControllerNavigator(by: "controllerNavigationStack")
                        }
                    }
                }
            }
        case .exit:
            exit(0)
        default:
            break
        }
    }
    
    @objc static func updateRadialMenu() {
        controllerMouseInputX = 0
        controllerMouseInputY = 0
        navigationTimer?.clean()
        ControllerUtil.stopListeningPrimaryController()
        if let mainFrameVC = radialMenuDelegate as? MainFrameViewController {
            let streamFrameVC = StreamFrameViewController.sharedInstance()
            let showRadiaMenu = mainFrameVC.isStreaming() ? streamFrameVC?.hasNoPresentedVC == true : mainFrameVC.hasNoPresentedVC
            if showRadiaMenu {
                radialMenuView?.removeFromSuperview()
                RadialMenuOverlayView.menuSectors.removeAll()
                
                if radialMenuState == .disconnectAndQuit {
                    RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Disconnect".localized, subtitle: "", symbol: PublicUtils.disconnectSymbol(), item: .disconnect))
                    RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Quit App".localized, subtitle: "", symbol: PublicUtils.quitSymbol(), item: .quitApp))
                    radialMenuView = RadialMenuOverlayView.presentInKeyWindow()
                    listenToRadialMenuStick()
                    return
                }
                
                let navigationSettingsItem = RadialMenuSector(title: "Navigation Settings".localized, subtitle: "", symbol:"gear", item: .navigationSettings)
                
                if radialMenuState == .moreOptions {
                    if mainFrameVC.isStreaming() {
                        RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Game Profiles".localized, subtitle: "", symbol:PublicUtils.iOS18Available ? "gamecontroller.circle" : "gamecontroller.fill", item: .gameProfiles))
                        RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "=shortcuts".localized, subtitle: "", symbol: "apple.terminal", item: .mouse))
                    }
                    else {
                        if !mainFrameVC.isInAppView(), !mainFrameVC.settingsViewExpanded {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "About".localized, subtitle: "", symbol: "questionmark.circle", item: .aboutView))}
                        if !mainFrameVC.settingsViewExpanded {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Theme".localized, subtitle: "", symbol: "circle.lefthalf.filled", item: .theme))}
                        if !mainFrameVC.settingsViewExpanded {RadialMenuOverlayView.menuSectors.appendIfNotContains(navigationSettingsItem)}
                        if !mainFrameVC.settingsViewExpanded {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Exit".localized, subtitle: "", symbol: "rectangle.portrait.and.arrow.right", item: .exit))}
                    }
                    RadialMenuOverlayView.menuSectors.appendIfNotContains(navigationSettingsItem)
                    
                    radialMenuView = RadialMenuOverlayView.presentInKeyWindow()
                    listenToRadialMenuStick()
                    return
                }
                
                let gameProfileItem = RadialMenuSector(title: "Game Profiles".localized, subtitle: "", symbol:PublicUtils.iOS18Available ? "gamecontroller.circle" : "gamecontroller.fill", item: .gameProfiles)
                
                RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Settings Menu".localized, subtitle: "", symbol: "sidebar.left", item: .settings))
                
                if mainFrameVC.settingsViewExpanded {
                    if mainFrameVC.settingsViewController.currentSettingsMenuMode == .AllSettings {
                        RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Favorite Settings".localized, subtitle: "", symbol: "bookmark", item: .favoriteSettings))
                        RadialMenuOverlayView.menuSectors.appendIfNotContains(gameProfileItem)
                        RadialMenuOverlayView.menuSectors.appendIfNotContains(navigationSettingsItem)
                    }
                    if mainFrameVC.settingsViewController.currentSettingsMenuMode == .FavoriteSettings {
                        RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "All Settings".localized, subtitle: "", symbol: "circle.grid.3x3", item: .allSettings))
                    }
                }
                
                if !mainFrameVC.settingsViewExpanded {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "More".localized, subtitle: "", symbol: "ellipsis.circle", item: .more))}

                if !mainFrameVC.isStreaming() || radialMenuState == .moreOptions { RadialMenuOverlayView.menuSectors.appendIfNotContains(gameProfileItem)
                }
                
                if mainFrameVC.isInAppView(), !mainFrameVC.isStreaming(), !mainFrameVC.settingsViewExpanded {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Host View".localized, subtitle: "", symbol: PublicUtils.liquidGlassEnabled ? "macwindow.on.rectangle" : "tv", item: .hostView))}
                
                if !mainFrameVC.isInAppView(), !mainFrameVC.isStreaming(), !mainFrameVC.settingsViewExpanded {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Add Host".localized, subtitle: "", symbol: "plus.circle", item: .addHost))}
                
                if mainFrameVC.isStreaming(), !mainFrameVC.settingsExpandedInStreamView {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Controller Mouse".localized, subtitle: "", symbol: radialMenuState == .mouseModeEnabled ? "disableControllerMouse" : "controllerMouse", item: .mouse))}
                if mainFrameVC.isStreaming(), !mainFrameVC.settingsExpandedInStreamView {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Disconnect".localized, subtitle: "", symbol: PublicUtils.disconnectSymbol(), item: .disconnect))}
                // if mainFrameVC.isStreaming(), !mainFrameVC.settingsExpandedInStreamView {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Quit App".localized, subtitle: "", symbol: PublicUtils.quitSymbol(), item: .quitApp))}
                radialMenuView = RadialMenuOverlayView.presentInKeyWindow()
            }
        }
        listenToRadialMenuStick()
    }
    
    private static func listenToRadialMenuStick() {
        let radialMenuStick: ControllerElement = radialMenuButtonPosition == .right ? .leftStick : .rightStick
        ControllerUtil.listenPrimaryControllerStick(radialMenuStick) { offsetVector in
            GamepadNavigationIllustrationHud.updateActionState(for: radialMenuStick, isInAction: hypot(offsetVector.dx, offsetVector.dy) >= 0.1)
            if let selectedItem = radialMenuView?.updateSelection(
                xOffset: offsetVector.dx,
                yOffset: offsetVector.dy
            ) {
                PublicUtils.runOnMain {
                    stickReleasedInRadialMenu = true
                    performRadialMenuAction(selectedItem)
                }
            }
        }
    }
    
    private static var radialMenuButtonPressed: Bool = false
    private static var radialMenuDelayTimer: SafeTimer?
    private static var radialMenuState: RadialMenuState = .main
    private static func listenToRadialMenuButton() {
        guard enabled else {return}
        guard let mainFrameVC = radialMenuDelegate as? MainFrameViewController else {return}
        radialMenuState = .main
        radialMenuButton = mainFrameVC.isStreaming() ? streamingRadialMenuButton : localRadialMenuButton
        ControllerUtil.listenPrimaryControllerButton(radialMenuButton) { pressed in
            GamepadNavigationIllustrationHud.updateActionState(for: radialMenuButton, isInAction: pressed)
            if pressed {
                radialMenuButtonPressed = true
                let delayRadialMenu = (mainFrameVC.isStreaming() && !mainFrameVC.settingsExpandedInStreamView) ||
                streamingRadialMenuDelay < 0.03
                streamingRadialMenuDelay = max(streamingRadialMenuDelay, 0.032)
                
                if delayRadialMenu {
                    radialMenuDelayTimer = SafeTimer(interval: streamingRadialMenuDelay) {
                        if radialMenuDelayTimer?.remainingMinimumRunCount == 2 {return}
                        if radialMenuButtonPressed {
                            DispatchQueue.main.async {
                                self.updateRadialMenu()
                                radialMenuDelayTimer?.clean()
                            }
                        }
                    }
                    radialMenuDelayTimer?.restart(minimumRunCount: 2)
                }
                else {
                    self.updateRadialMenu()
                }
            }
            else {
                radialMenuButtonPressed = false
                radialMenuDelayTimer?.clean()
                stickReleasedInRadialMenu = false
                if radialMenuView == nil, uiNavigationDelegate is StreamFrameViewController {
                    ControllerSupport.sharedInstance().sendNavigationButtonPress()
                    return
                }
                radialMenuView?.dismiss()
                radialMenuView = nil
                ControllerNavigator.updateUINavigationDelegateState()
            }
        }
    }
    
    @objc static func listenToControllerMouse() {
        guard radialMenuState == .mouseModeEnabled else { return }
        ControllerUtil.listenPrimaryControllerButton(controllerMouseLeftButton){ pressed in
            GamepadNavigationIllustrationHud.updateActionState(for: controllerMouseLeftButton, isInAction: pressed)
            LiSendMouseButtonEvent(CChar(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE), BUTTON_LEFT)
        }
        ControllerUtil.listenPrimaryControllerButton(controllerMouseRightButton){ pressed in
            GamepadNavigationIllustrationHud.updateActionState(for: controllerMouseRightButton, isInAction: pressed)
            LiSendMouseButtonEvent(CChar(pressed ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE), BUTTON_RIGHT)
        }
        ControllerUtil.listenPrimaryControllerStick(controllerMouseStick){ offsetVector in
            GamepadNavigationIllustrationHud.updateActionState(for: controllerMouseStick, isInAction: hypot(offsetVector.dx, offsetVector.dy) >= 0.1)
            // print("performRadialMenuAction mouse \(offsetVector) \(CACurrentMediaTime())")
            controllerMouseInputX = offsetVector.dx
            controllerMouseInputY = offsetVector.dy
        }
        let wheelStick: ControllerElement = controllerMouseStick == .rightStick ? .leftStick : .rightStick
        ControllerUtil.listenPrimaryControllerStick(wheelStick) { offsetVector in
            GamepadNavigationIllustrationHud.updateActionState(for: wheelStick, isInAction: hypot(offsetVector.dx, offsetVector.dy) >= 0.1)
            controllerMouseWheelInputX = offsetVector.dx
            controllerMouseWheelInputY = offsetVector.dy
        }
    }
    
    @objc static func restartListening() {
        guard enabled else {
            ControllerUtil.stopListeningPrimaryController(stopListenToRadialMenuButton: true)
            GamepadNavigationIllustrationHud.clearHud()
            return
        }
                
        ControllerUtil.stopListeningPrimaryController()
        GamepadNavigationIllustrationHud.resetActionStates()
        
        guard let mainFrameVC = radialMenuDelegate as? MainFrameViewController else {return}
        
        listenToRadialMenuButton()
        listenToRadialMenuStick()
        

        
        if let uiNavigationDelegate = uiNavigationDelegate, !mainFrameVC.isStreaming() || mainFrameVC.settingsExpandedInStreamView {
            let verticalNavigationAxis: ControllerElement = ControllerNavigator.radialMenuButtonPosition == .right ? .leftStickY : .rightStickY
            ControllerUtil.listenPrimaryControllerStickAxis(verticalNavigationAxis, threshold: 0.6) {state in
                GamepadNavigationIllustrationHud.updateActionState(for: verticalNavigationAxis, isInAction: state != .orderedSame)
                guard radialMenuView == nil else {return}
                switch state {
                case .orderedAscending:
                    if navigationTimer?.isRunning() != true {
                        if uiNavigationDelegate is SettingsViewController {
                            navigateContinuously(forward: true)
                        }
                        if uiNavigationDelegate is UICollectionViewController {
                            navigateContinuously(downward: true)
                        }
                    }
                case .orderedDescending:
                    if navigationTimer?.isRunning() != true {
                        if uiNavigationDelegate is SettingsViewController {
                            navigateContinuously(forward: false)
                        }
                        if uiNavigationDelegate is UICollectionViewController {
                            navigateContinuously(downward: false)
                        }
                    }
                case .orderedSame:
                    navigationTimer?.clean()
                }
            }
        }
        
        if let uiNavigationDelegate = uiNavigationDelegate, !mainFrameVC.isStreaming() {
            let horizontalNavigationAxis: ControllerElement = ControllerNavigator.radialMenuButtonPosition == .right ? .leftStickX : .rightStickX
            ControllerUtil.listenPrimaryControllerStickAxis(horizontalNavigationAxis, threshold: 0.6) {state in
                GamepadNavigationIllustrationHud.updateActionState(for: horizontalNavigationAxis, isInAction: state != .orderedSame)
                guard radialMenuView == nil else {return}
                switch state {
                case .orderedAscending:
                    if navigationTimer?.isRunning() != true {
                        if uiNavigationDelegate is UICollectionViewController {
                            navigateContinuously(forward: false)
                        }
                    }
                case .orderedDescending:
                    if navigationTimer?.isRunning() != true {
                        if uiNavigationDelegate is UICollectionViewController {
                            navigateContinuously(forward: true)
                        }
                    }
                case .orderedSame:
                    navigationTimer?.clean()
                }
            }
        }

        if let uiNavigationDelegate = uiNavigationDelegate, !mainFrameVC.isStreaming() || mainFrameVC.settingsExpandedInStreamView || uiNavigationDelegate is UIAlertController || uiNavigationDelegate is OSCProfilesTableViewController {
            let navigations = uiNavigationDelegate.getNavigationElements()
            let buttonNavigations = navigations.filter({$0.control.type == .button})
            // let stickNavigations = navigations.filter({$0.control.type == .stick || $0.control.type == .stickAxis})
            
            var listenedControls = Set<ControllerElement>()
            for buttonNavigation in buttonNavigations {
                if buttonNavigation.control == radialMenuButton {continue}
                if listenedControls.contains(buttonNavigation.control) {continue}
                ControllerUtil.listenPrimaryControllerButton(buttonNavigation.control) {pressed in
                    buttonNavigation.isInAction = pressed
                    GamepadNavigationIllustrationHud.updateActionState(for: buttonNavigation.control, isInAction: pressed)
                    uiNavigationDelegate.uiButtonActionForControllerNavigator(pressed: pressed, from: buttonNavigation)
                    // print("buttonElement.control \(buttonElement.control.displayName) \(pressed)")
                    if !pressed {
                        navigationTimer?.clean()
                    }
                }
                listenedControls.insert(buttonNavigation.control)
            }
        }
        
        /*
        ControllerUtil.listenPrimaryControllerStickAxis(.leftStickX, threshold: 0.8) {state in
            guard uiNavigationDelegate != nil, radialMenuView == nil else {return}
            switch state {
            case .orderedAscending:
                if navigationTimer?.isRunning() != true {uiNavigationDelegate?.uiWidgetActionForControllerNavigator(forward: false)}
            case .orderedDescending:
                if navigationTimer?.isRunning() != true {uiNavigationDelegate?.uiWidgetActionForControllerNavigator(forward: true)}
            case .orderedSame:
                navigationTimer?.clean()
            }
        }
        */
    }
    
    
}

@available(iOS 13.0, *)
extension SettingsViewController: ControllerUINavigationDelegate {
    func persistControllerNavigationHighlight() {
        guard let highlightedView = ControllerNavigator.controllerNavigationHighlightedView,
              let identifier = controllerNavigationPersistenceIdentifier(for: highlightedView) else {
            return
        }

        UserDefaults.standard.set(identifier, forKey: settingsControllerNavigationHighlightedIdentifierKey)
    }

    func restoreControllerNavigationHighlight() {
        guard ControllerNavigator.enabled, ControllerUtil.primaryGCController != nil else {return}
        PublicUtils.runOnMain { [weak self] in
            self?.restoreControllerNavigationHighlightOnMain()
        }
    }

    func restoreControllerNavigationHighlightAfterSettingsModeSwitch() {
        PublicUtils.runOnMain { [weak self] in
            self?.restoreControllerNavigationHighlightAfterSettingsModeSwitchOnMain()
        }
    }
    
    func uiButtonActionForControllerNavigator(pressed: Bool, from navigation: ControllerNavigationElement) {
        let isHighlightingUIStack = ControllerNavigator.controllerNavigationHighlightedView is UIStackView
        
        if navigation.action == "holdToReorder", isHighlightingUIStack {
            handleControllerNavigationReorderHold(pressed: pressed)
            return
        }

        if isHighlightingUIStack, navigation.action == "readTip" || navigation.action == "doublePressToDelete" || navigation.action == "doublePressToAddFavorite" {
            PublicUtils.runOnMain { [weak self] in
                self?.handleControllerNavigationReadTip(pressed: pressed)
            }
            return
        }

        if pressed {
            switch navigation.action {
            case "widgetOperationBackward":
                self.uiWidgetActionForControllerNavigator(forward: false, from: navigation)
            case "widgetOperationForward":
                self.uiWidgetActionForControllerNavigator(forward: true, from: navigation)
            default:
                break
            }
        }
    }
    
    func getNavigationElements() -> [ControllerNavigationElement] {
        var elements: [ControllerNavigationElement] = []
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .dpadUp : .a, action: "readTip"))
        if self.currentSettingsMenuMode == .AllSettings {
            elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .dpadUp : .a, action: "doublePressToAddFavorite"))
        }
        if self.currentSettingsMenuMode == .FavoriteSettings {
            elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .dpadUp : .a, action: "doublePressToDelete"))
            elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .dpadDown : .y, action: "holdToReorder"))
        }
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButton, action: "radialMenu"))
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .rightStickY : .leftStickY, action: "menuNavigation"))
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .dpadLeft : .x, action: "widgetOperationBackward"))
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .dpadRight : .b, action: "widgetOperationForward"))
        return elements
    }
    
    func navigateByController(forward:Bool) {
        guard self.hasNoPresentedVC else {return}
        if currentSettingsMenuMode == .FavoriteSettings,
           ControllerNavigator.settingsFavoriteReorderActive {
            moveHighlightedFavoriteSettingStack(by: forward ? 1 : -1)
            return
        }

        performControllerNavigationSelectionMove(by: forward ? 1 : -1)
    }
    
    func navigateByController(downward:Bool) {
    }
    
    func uiWidgetActionForControllerNavigator(forward: Bool, from navigation:ControllerNavigationElement) {
        guard self.hasNoPresentedVC else {return}

        if let highlightedView = ControllerNavigator.controllerNavigationHighlightedView, highlightedView is UIButton {
            if let section = highlightedView.superview as? MenuSectionView {
                section.toggleFold()
            }
        }
        
        if let stack = ControllerNavigator.controllerNavigationHighlightedView as? UIStackView {
            for view in stack.arrangedSubviews {
                if let selector = view as? UISegmentedControl {
                    guard selector.isEnabled else {continue}
                    var targetIndex:Int = 0
                    repeat {
                        targetIndex = selector.nextIndex(forward: forward)
                        selector.selectedSegmentIndex = targetIndex
                    } while !selector.isEnabledForSegment(at: targetIndex)
                    selector.sendActions(for: .valueChanged)
                }
                if let uiSwitch = view as? UISwitch {
                    guard uiSwitch.isEnabled else {continue}
                    uiSwitch.isOn = !uiSwitch.isOn
                    uiSwitch.sendActions(for: .valueChanged)
                }
                if let slider = view as? UISlider {
                    guard slider.isEnabled else {continue}
                    ControllerNavigator.navigationTimer?.clean()
                    slider.step(forward: forward, visualStepRatio: 0.02)
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.08) {
                        guard navigation.isInAction else { return }
                        ControllerNavigator.navigationTimer = SafeTimer(interval: 0.03) {
                            slider.step(forward: forward, visualStepRatio: 0.02)
                        }
                        ControllerNavigator.navigationTimer?.restart()
                    }
                }
            }
        }
    }

    private func performControllerNavigationSelectionMove(by offset: Int) {
        PublicUtils.runOnMain { [weak self] in
            self?.moveControllerNavigationSelection(by: offset)
        }
    }

    private func restoreControllerNavigationHighlightOnMain() {
        if let persistedIdentifier = UserDefaults.standard.string(forKey: settingsControllerNavigationHighlightedIdentifierKey) {
               highlightViewForControllerNavigator(by: persistedIdentifier)
        }
    }
    
    func highlightViewForControllerNavigator(by identifer: String?){
        let targets = controllerNavigationRestorableTargets()
        let selectableTargets = targets.filter { isControllerNavigationSelectableTarget($0) }
        guard !selectableTargets.isEmpty else {
            clearControllerNavigationHighlight()
            return
        }
        
        if let identifer = identifer,
           let target = selectableTargets.first(where: {
               controllerNavigationPersistenceIdentifier(for: $0) == identifer
           }) {
            highlightControllerNavigationView(target)
            return
        }

        highlightControllerNavigationView(selectableTargets[0])
    }

    private func restoreControllerNavigationHighlightAfterSettingsModeSwitchOnMain() {
        let targets = controllerNavigationRestorableTargets()
        let selectableTargets = targets.filter { isControllerNavigationSelectableTarget($0) }
        guard !selectableTargets.isEmpty else {
            clearControllerNavigationHighlight()
            return
        }

        if let highlightedView = ControllerNavigator.controllerNavigationHighlightedView,
           !isControllerNavigationSectionHeader(highlightedView),
           let highlightedIdentifier = controllerNavigationPersistenceIdentifier(for: highlightedView),
           let target = selectableTargets.first(where: {
               !isControllerNavigationSectionHeader($0) &&
               controllerNavigationPersistenceIdentifier(for: $0) == highlightedIdentifier
           }) {
            highlightControllerNavigationView(target)
            return
        }

        highlightControllerNavigationView(selectableTargets[0])
    }

    private func controllerNavigationRestorableTargets() -> [UIView] {
        var targets: [UIView] = []
        if currentSettingsMenuMode == .FavoriteSettings || currentSettingsMenuMode == .RemoveSettingItem,
           let parentStack = parentStack {
            targets.append(contentsOf: visibleFavoriteSettingStacks(in: parentStack))
        }
        targets.append(contentsOf: controllerNavigationTargets(skippingDisabledStacks: false))

        var seenIdentifiers = Set<ObjectIdentifier>()
        return targets.filter { target in
            let identifier = ObjectIdentifier(target)
            guard !seenIdentifiers.contains(identifier) else { return false }
            seenIdentifiers.insert(identifier)
            return true
        }
    }

    func controllerNavigationPersistenceIdentifier(for view: UIView) -> String? {
        if currentSettingsMenuMode == .FavoriteSettings || currentSettingsMenuMode == .RemoveSettingItem,
           let topLevelStack = topLevelFavoriteSettingStack(containing: view),
           let identifier = topLevelStack.accessibilityIdentifier,
           !identifier.isEmpty {
            return identifier
        }

        var currentView: UIView? = view
        while let viewToCheck = currentView {
            if let identifier = viewToCheck.accessibilityIdentifier,
               !identifier.isEmpty {
                return identifier
            }

            if viewToCheck === parentStack {
                return nil
            }

            currentView = viewToCheck.superview
        }

        return nil
    }

    private func isControllerNavigationSectionHeader(_ view: UIView) -> Bool {
        return view.accessibilityIdentifier?.hasPrefix("sectionHeader") == true
    }

    private func handleControllerNavigationReorderHold(pressed: Bool) {
        guard currentSettingsMenuMode == .FavoriteSettings else {
            ControllerNavigator.settingsFavoriteReorderActive = false
            return
        }

        if pressed {
            ControllerNavigator.settingsFavoriteReorderActive = true
            return
        }

        guard ControllerNavigator.settingsFavoriteReorderActive else { return }
        ControllerNavigator.settingsFavoriteReorderActive = false
        saveFavoriteSettingStackIdentifiers()
    }

    private func handleControllerNavigationReadTip(pressed: Bool) {
        if pressed {
            handleControllerNavigationReadTipPressDown()
        } else {
            handleControllerNavigationReadTipRelease()
        }
    }

    private func handleControllerNavigationReadTipPressDown() {
        if ControllerNavigator.settingsReadTipPendingWorkItem != nil {
            ControllerNavigator.settingsReadTipPressedAgain = true
            ControllerNavigator.settingsReadTipSuppressNextRelease = true
        }
    }

    private func handleControllerNavigationReadTipRelease() {
        if ControllerNavigator.settingsReadTipSuppressNextRelease {
            ControllerNavigator.settingsReadTipSuppressNextRelease = false
            return
        }

        cancelPendingControllerNavigationReadTip()
        ControllerNavigator.settingsReadTipPendingToken += 1
        let token = ControllerNavigator.settingsReadTipPendingToken
        
        let workItem = DispatchWorkItem { [weak self] in
            guard ControllerNavigator.settingsReadTipPendingToken == token else { return }

            if ControllerNavigator.settingsReadTipPressedAgain {
                
                switch self?.currentSettingsMenuMode {
                case .FavoriteSettings:
                    self?.removeHighlightedFavoriteSettingStack()
                case .AllSettings:
                    if let highlitedStack = ControllerNavigator.controllerNavigationHighlightedView as? UIStackView {
                        self?.addSetting(toFavorite: highlitedStack)
                        DispatchQueue.main.async {
                            if AlertControllerUtil.autoCompletion {return}
                            AlertControllerUtil.autoCompletion = true
                            AlertControllerUtil.showAlert(
                                in: self,
                                title: LocalizationHelper.localizedString(forKey: ""),
                                message: "Setting added to favorite".localized,
                                withCancel: false,
                                buttonTitle: "",
                                countdown: 1,
                                completion: {
                            })
                        }
                    }
                default:
                    break
                }
                
                // print("self?.cancelPendingControllerNavigationReadTip(resetSuppressNextRelease: false)");

            } else {
                self?.performControllerNavigationReadTip()
            }
            

            self?.cancelPendingControllerNavigationReadTip(resetSuppressNextRelease: false)
        }
        ControllerNavigator.settingsReadTipPendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: workItem)
    }

    private func cancelPendingControllerNavigationReadTip(resetSuppressNextRelease: Bool = true) {
        ControllerNavigator.settingsReadTipPendingWorkItem?.cancel()
        ControllerNavigator.settingsReadTipPendingWorkItem = nil
        ControllerNavigator.settingsReadTipPressedAgain = false
        if resetSuppressNextRelease {
            ControllerNavigator.settingsReadTipSuppressNextRelease = false
        }
        ControllerNavigator.settingsReadTipPendingToken += 1
    }

    private func performControllerNavigationReadTip() {
        guard let stack = ControllerNavigator.controllerNavigationHighlightedView as? UIStackView,
              stack.hasInfoTag || stack.isGameProfileSetting else {
            return
        }

        for view in stack.subviews.filter({ $0.accessibilityIdentifier == "infoButton" }) {
            if let button = view as? UIButton {
                button.sendActions(for: .touchUpInside)
            }
        }
    }

    private func removeHighlightedFavoriteSettingStack() {
        guard currentSettingsMenuMode == .FavoriteSettings,
              let parentStack = parentStack,
              let highlightedView = ControllerNavigator.controllerNavigationHighlightedView,
              let stack = topLevelFavoriteSettingStack(containing: highlightedView) else {
            return
        }

        let visibleStacksBeforeRemoval = visibleFavoriteSettingStacks(in: parentStack)
        guard let removedVisibleIndex = visibleStacksBeforeRemoval.firstIndex(where: { $0 === stack }) else { return }
        let nextVisibleIndex = max(removedVisibleIndex - 1, 0)

        parentStack.removeArrangedSubview(stack)
        stack.removeFromSuperview()
        saveFavoriteSettingStackIdentifiers()
        parentStack.setNeedsLayout()

        UIView.animate(withDuration: 0.12) {
            parentStack.layoutIfNeeded()
        }

        let visibleStacksAfterRemoval = visibleFavoriteSettingStacks(in: parentStack)
        guard !visibleStacksAfterRemoval.isEmpty else {
            clearControllerNavigationHighlight()
            return
        }

        let targetIndex = min(nextVisibleIndex, visibleStacksAfterRemoval.count - 1)
        highlightControllerNavigationView(visibleStacksAfterRemoval[targetIndex])
    }

    private func visibleFavoriteSettingStacks(in parentStack: UIStackView) -> [UIStackView] {
        return parentStack.arrangedSubviews.compactMap { $0 as? UIStackView }.filter {
            isControllerNavigationVisible($0, within: parentStack)
        }
    }

    private func moveHighlightedFavoriteSettingStack(by offset: Int) {
        PublicUtils.runOnMain { [weak self] in
            self?.moveHighlightedFavoriteSettingStackOnMain(by: offset)
        }
    }

    private func moveHighlightedFavoriteSettingStackOnMain(by offset: Int) {
        guard currentSettingsMenuMode == .FavoriteSettings,
              let parentStack = parentStack,
              let highlightedView = ControllerNavigator.controllerNavigationHighlightedView,
              let stack = topLevelFavoriteSettingStack(containing: highlightedView),
              isControllerNavigationVisible(stack, within: parentStack) else {
            return
        }

        let visibleStacks = parentStack.arrangedSubviews.compactMap { $0 as? UIStackView }.filter {
            isControllerNavigationVisible($0, within: parentStack)
        }
        guard let currentVisibleIndex = visibleStacks.firstIndex(where: { $0 === stack }) else { return }

        let targetVisibleIndex = currentVisibleIndex + offset
        guard visibleStacks.indices.contains(targetVisibleIndex) else { return }

        let targetStack = visibleStacks[targetVisibleIndex]
        guard let targetArrangedIndex = parentStack.arrangedSubviews.firstIndex(where: { $0 === targetStack }) else {
            return
        }

        parentStack.removeArrangedSubview(stack)
        parentStack.insertArrangedSubview(stack, at: targetArrangedIndex)
        parentStack.setNeedsLayout()

        UIView.animate(withDuration: 0.12) {
            parentStack.layoutIfNeeded()
        }

        highlightControllerNavigationView(stack)
    }

    private func topLevelFavoriteSettingStack(containing view: UIView) -> UIStackView? {
        guard let parentStack = parentStack else { return nil }

        var currentView: UIView? = view
        while let viewToCheck = currentView, viewToCheck !== parentStack {
            if let stackView = viewToCheck as? UIStackView,
               parentStack.arrangedSubviews.contains(where: { $0 === stackView }) {
                return stackView
            }

            currentView = viewToCheck.superview
        }

        return nil
    }

    private func moveControllerNavigationSelection(by offset: Int) {
        let allTargets = controllerNavigationTargets(skippingDisabledStacks: false)
        let targets = allTargets.filter { isControllerNavigationSelectableTarget($0) }
        guard !targets.isEmpty else {
            clearControllerNavigationHighlight()
            return
        }

        if let highlightedView = ControllerNavigator.controllerNavigationHighlightedView,
           let currentIndex = allTargets.firstIndex(where: { $0 === highlightedView }) {
            var nextIndex = currentIndex
            for _ in 0..<allTargets.count {
                nextIndex = (nextIndex + offset + allTargets.count) % allTargets.count
                let candidate = allTargets[nextIndex]
                if isControllerNavigationSelectableTarget(candidate) {
                    highlightControllerNavigationView(candidate)
                    return
                }
            }
        }

        let currentIndex = ControllerNavigator.controllerNavigationHighlightedView.flatMap { highlightedView in
            targets.firstIndex { $0 === highlightedView }
        }

        let nextIndex: Int
        if let currentIndex = currentIndex {
            nextIndex = (currentIndex + offset + targets.count) % targets.count
        } else {
            nextIndex = offset >= 0 ? 0 : targets.count - 1
        }

        highlightControllerNavigationView(targets[nextIndex])
    }

    private func controllerNavigationTargets(skippingDisabledStacks: Bool = true) -> [UIView] {
        guard let parentStack = parentStack else { return [] }

        switch currentSettingsMenuMode {
        case .FavoriteSettings, .RemoveSettingItem:
            return favoriteSettingsControllerNavigationTargets(
                in: parentStack,
                skippingDisabledStacks: skippingDisabledStacks
            )
        case .AllSettings:
            break
        @unknown default:
            break
        }

        var targets: [UIView] = []
        for arrangedSubview in parentStack.arrangedSubviews {
            guard let sectionView = arrangedSubview as? MenuSectionView else { continue }
            guard isControllerNavigationVisible(sectionView, within: parentStack) else { continue }

            if let headerView = sectionView.headerView,
               isControllerNavigationVisible(headerView, within: sectionView) {
                targets.append(headerView)
            }

            guard let rootStackView = sectionView.rootStackView else { continue }
            guard isControllerNavigationVisible(rootStackView, within: sectionView) else { continue }

            for arrangedRootSubview in rootStackView.arrangedSubviews {
                guard let stackView = arrangedRootSubview as? UIStackView else { continue }
                targets.append(contentsOf: deepestVisibleControllerNavigationStacks(from: stackView, within: rootStackView, skippingDisabledStacks: skippingDisabledStacks))
            }
        }

        return targets
    }

    private func favoriteSettingsControllerNavigationTargets(in parentStack: UIStackView, skippingDisabledStacks: Bool) -> [UIView] {
        var targets: [UIView] = []
        for arrangedSubview in parentStack.arrangedSubviews {
            guard let stackView = arrangedSubview as? UIStackView else { continue }
            targets.append(contentsOf: deepestVisibleControllerNavigationStacks(
                from: stackView,
                within: parentStack,
                skippingDisabledStacks: skippingDisabledStacks
            ))
        }

        return targets
    }

    private func deepestVisibleControllerNavigationStacks(from stackView: UIStackView, within rootStackView: UIStackView, skippingDisabledStacks: Bool) -> [UIStackView] {
        guard isControllerNavigationVisible(stackView, within: rootStackView) else { return [] }

        let childStackViews = stackView.arrangedSubviews.compactMap { $0 as? UIStackView }
        let visibleChildStackViews = childStackViews.filter {
            isControllerNavigationVisible($0, within: rootStackView)
        }

        guard !visibleChildStackViews.isEmpty else {
            if skippingDisabledStacks, hasDisabledArrangedSubview(in: stackView) {
                return []
            }

            return [stackView]
        }

        return visibleChildStackViews.flatMap {
            deepestVisibleControllerNavigationStacks(from: $0, within: rootStackView, skippingDisabledStacks: skippingDisabledStacks)
        }
    }

    private func isControllerNavigationSelectableTarget(_ view: UIView) -> Bool {
        if currentSettingsMenuMode == .FavoriteSettings || currentSettingsMenuMode == .RemoveSettingItem {
            return true
        }

        guard let stackView = view as? UIStackView else { return true }
        return !hasDisabledArrangedSubview(in: stackView)
    }

    private func hasDisabledArrangedSubview(in stackView: UIStackView) -> Bool {
        for arrangedSubview in stackView.arrangedSubviews {
            if let control = arrangedSubview as? UIControl, !control.isEnabled {
                return true
            }

            if let nestedStackView = arrangedSubview as? UIStackView,
               hasDisabledArrangedSubview(in: nestedStackView) {
                return true
            }
        }

        return false
    }

    private func isControllerNavigationVisible(_ view: UIView, within ancestor: UIView) -> Bool {
        var currentView: UIView? = view
        while let viewToCheck = currentView {
            if viewToCheck.isHidden || viewToCheck.alpha <= 0.01 {
                return false
            }

            if viewToCheck === ancestor {
                return true
            }

            currentView = viewToCheck.superview
        }

        return false
    }

    private func highlightControllerNavigationView(_ view: UIView) {
        guard ControllerNavigator.controllerNavigationHighlightedView !== view else {
            scrollControllerNavigationViewToVisible(view)
            return
        }
        
        var navigations = self.getNavigationElements()
        let shouldShowReadTip = (view as? UIStackView).map { $0.hasInfoTag || $0.isGameProfileSetting } ?? false
        if !shouldShowReadTip {
            navigations.removeAll { $0.action == "readTip" }
        }
        GamepadNavigationIllustrationHud.updateNavigationElements(navigations)

        clearControllerNavigationHighlight()
        ControllerNavigator.controllerNavigationHighlightedView = view

        let overlayView = UIView()
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        overlayView.isUserInteractionEnabled = false
        overlayView.backgroundColor = ThemeManager.appPrimaryColorWithAlpha
        overlayView.layer.cornerRadius = 8
        overlayView.layer.cornerCurve = .continuous
        overlayView.layer.masksToBounds = true
        overlayView.alpha = 0
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: view.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.bringSubviewToFront(overlayView)
        controllerNavigationHighlightOverlayView = overlayView

        UIView.animate(withDuration: 0.12) {
            overlayView.alpha = 1
        }

        scrollControllerNavigationViewToVisible(view)
    }

    private func clearControllerNavigationHighlight() {
        guard let overlayView = controllerNavigationHighlightOverlayView else {
            ControllerNavigator.controllerNavigationHighlightedView = nil
            return
        }

        UIView.animate(withDuration: 0.08, animations: {
            overlayView.alpha = 0
        }, completion: { _ in
            overlayView.removeFromSuperview()
        })

        ControllerNavigator.controllerNavigationHighlightedView = nil
        controllerNavigationHighlightOverlayView = nil
    }

    fileprivate func clearControllerNavigationHighlightForControllerNavigator() {
        clearControllerNavigationHighlight()
    }

    private func scrollControllerNavigationViewToVisible(_ view: UIView) {
        guard let scrollView = scrollView,
              let parentStack = parentStack else { return }

        scrollView.layoutIfNeeded()
        parentStack.layoutIfNeeded()

        let targetRectInParentStack = view.convert(view.bounds, to: parentStack)
        let targetRectInContent = targetRectInParentStack.offsetBy(
            dx: parentStack.frame.minX,
            dy: parentStack.frame.minY
        )

        let edgePadding: CGFloat = 72
        let adjustedInset = scrollView.adjustedContentInset
        let visibleMinY = scrollView.contentOffset.y + adjustedInset.top
        let visibleMaxY = scrollView.contentOffset.y + scrollView.bounds.height - adjustedInset.bottom

        var targetOffsetY = scrollView.contentOffset.y
        if targetRectInContent.minY < visibleMinY + edgePadding {
            targetOffsetY = targetRectInContent.minY - edgePadding - adjustedInset.top
        } else if targetRectInContent.maxY > visibleMaxY - edgePadding {
            targetOffsetY = targetRectInContent.maxY + edgePadding + adjustedInset.bottom - scrollView.bounds.height
        }

        let minOffsetY = -adjustedInset.top
        let maxOffsetY = max(minOffsetY, scrollView.contentSize.height - scrollView.bounds.height + adjustedInset.bottom)
        targetOffsetY = min(max(targetOffsetY, minOffsetY), maxOffsetY)

        guard abs(targetOffsetY - scrollView.contentOffset.y) > 0.5 else { return }
        UIView.animate(withDuration: 0.1) {
            scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: targetOffsetY), animated: false)
        }
    }
}

extension UICollectionViewController {
    var controllerNavigationSelectedIndexPath: IndexPath? {
        get {
            objc_getAssociatedObject(self, &controllerNavigationSelectedIndexPathKey) as? IndexPath
        }
        set {
            objc_setAssociatedObject(self, &controllerNavigationSelectedIndexPathKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    private var controllerNavigationPersistToken: Int {
        get {
            objc_getAssociatedObject(self, &controllerNavigationPersistTokenKey) as? Int ?? 0
        }
        set {
            objc_setAssociatedObject(self, &controllerNavigationPersistTokenKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    func applyControllerNavigationHighlight(to cell: UICollectionViewCell, highlighted: Bool) {
        clearControllerNavigationHighlightBorder(in: cell)
        guard highlighted else { return }
        let highlightedView = controllerNavigationHighlightTargetView(for: cell)
        highlightedView.layer.borderWidth = (self is HostCollectionViewController) ? 3 : 5
        let isDarkTheme = ThemeManager.userInterfaceStyle() == .dark
        highlightedView.layer.borderColor = ThemeManager.appPrimaryColor.withAlphaComponent(isDarkTheme ? 0.85 : 0.93).cgColor
    }

    private func clearControllerNavigationHighlightBorder(in cell: UICollectionViewCell) {
        for view in [cell, cell.contentView] + cell.contentView.subviews + cell.subviews {
            view.layer.borderWidth = 0
            view.layer.borderColor = nil
        }
    }

    private func controllerNavigationHighlightTargetView(for cell: UICollectionViewCell) -> UIView {
        if let contentView = controllerNavigationContentView(in: cell) {
            return contentView
        }

        return cell.contentView
    }

    private func controllerNavigationContentView(in cell: UICollectionViewCell) -> UIView? {
        let contentSubviews = cell.contentView.subviews.filter {
            !$0.isHidden && $0.alpha > 0.01 && !$0.bounds.isEmpty
        }
        if let contentSubview = contentSubviews.first {
            return contentSubview
        }

        let cellSubviews = cell.subviews.filter {
            $0 !== cell.contentView && !$0.isHidden && $0.alpha > 0.01 && !$0.bounds.isEmpty
        }
        return cellSubviews.first
    }
}

@available(iOS 13.0, *)
extension UICollectionViewController: ControllerUINavigationDelegate {
    func persistControllerNavigationHighlight() {
        if let hostCollectionVC = self as? HostCollectionViewController {
            persistHostControllerNavigationHighlight(in: hostCollectionVC)
            return
        }

        if self is MainFrameViewController {
            persistAppControllerNavigationHighlight()
        }
    }

    func restoreControllerNavigationHighlight() {
        guard ControllerNavigator.enabled, ControllerUtil.primaryGCController != nil else {return}

        PublicUtils.runOnMain { [weak self] in
            guard let self else { return }

            if let hostCollectionVC = self as? HostCollectionViewController {
                self.restoreHostControllerNavigationHighlight(in: hostCollectionVC)
                return
            }

            if let mainFrameVC = self as? MainFrameViewController {
                self.restoreAppControllerNavigationHighlight(in: mainFrameVC)
            }
        }
    }

    func restoreControllerNavigationHighlightAfterSettingsModeSwitch() {
    }

    private func currentControllerNavigationCell() -> UICollectionViewCell? {
        guard let selectedIndexPath = controllerNavigationSelectedIndexPath,
              selectedIndexPath.section < collectionView.numberOfSections,
              selectedIndexPath.item >= 0,
              selectedIndexPath.item < collectionView.numberOfItems(inSection: selectedIndexPath.section) else {
            return nil
        }

        return collectionView.cellForItem(at: selectedIndexPath)
    }

    private func currentControllerNavigationContentView() -> UIView? {
        guard let cell = currentControllerNavigationCell() else { return nil }
        return controllerNavigationContentView(in: cell)
    }

    func uiButtonActionForControllerNavigator(pressed: Bool, from navigation: ControllerNavigationElement) {
        PublicUtils.runOnMain { [weak self] in
            guard let self else { return }

            if pressed {
                if self is HostCollectionViewController {
                    guard let hostCardView = self.currentControllerNavigationContentView() as? HostCardView else { return }
                    
                    switch navigation.action {
                    case "launchPairWake":
                        hostCardView.launchButtonTapped()
                        hostCardView.pairButtonTapped()
                        hostCardView.wakeupButtonTapped()
                    case "applications":
                        hostCardView.appButtonTapped()
                    default:
                        break
                    }
                }
                if let mainFrameVC = self as? MainFrameViewController {
                    let appView = self.currentControllerNavigationContentView() as? UIAppView
                    switch navigation.action {
                    case "launch":
                        mainFrameVC.forceLaunchApp(appView?.app)
                    case "quitApp":
                        PublicUtils.runOnMain {
                            mainFrameVC.quitApp(appView?.app)
                        }
                    default:
                        break
                    }
                }
            }
        }
    }
    
    func uiWidgetActionForControllerNavigator(forward: Bool, from navigation: ControllerNavigationElement) {
    }
    
    func getNavigationElements() -> [ControllerNavigationElement] {
        var elements: [ControllerNavigationElement] = []
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButton, action: "radialMenu"))
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .rightStick : .leftStick, action: "focusNavigation"))
        if self is HostCollectionViewController {elements.append(ControllerNavigationElement(control: ControllerNavigator.radialMenuButtonPosition == .left ? .dpadRight : .a, action: "applications"))}
        if self is HostCollectionViewController {elements.append(ControllerNavigationElement(control: ControllerNavigator.radialMenuButtonPosition == .left ? .dpadUp : .x, action: "launchPairWake"))}
        if self is MainFrameViewController {elements.append(ControllerNavigationElement(control: ControllerNavigator.radialMenuButtonPosition == .left ? .dpadRight : .a, action: "launch"))}
        if self is MainFrameViewController {elements.append(ControllerNavigationElement(control: ControllerNavigator.radialMenuButtonPosition == .left ? .dpadUp : .x, action: "quitApp"))}
        return elements
    }
    
    func navigateByController(forward: Bool) {
        guard hasNoPresentedVC else { return }
        performControllerNavigationSelectionMove(horizontalOffset: forward ? 1 : -1)
        scheduleControllerNavigationHighlightPersistenceWhenStickSettles()
    }

    func navigateByController(downward: Bool) {
        guard hasNoPresentedVC else { return }
        performControllerNavigationSelectionMove(verticalOffset: downward ? 1 : -1)
        scheduleControllerNavigationHighlightPersistenceWhenStickSettles()
    }

    func uiWidgetActionForControllerNavigator(forward: Bool) {
    }

    private func scheduleControllerNavigationHighlightPersistenceWhenStickSettles() {
        controllerNavigationPersistToken += 1
        let token = controllerNavigationPersistToken

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            self?.persistControllerNavigationHighlightIfStickSettled(token: token)
        }
    }

    private func persistControllerNavigationHighlightIfStickSettled(token: Int) {
        guard controllerNavigationPersistToken == token else { return }

        if ControllerNavigator.navigationTimer?.isRunning() == true {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
                self?.persistControllerNavigationHighlightIfStickSettled(token: token)
            }
            return
        }

        persistControllerNavigationHighlight()
    }

    private func persistHostControllerNavigationHighlight(in hostCollectionVC: HostCollectionViewController) {
        guard let selectedIndexPath = controllerNavigationSelectedIndexPath,
              selectedIndexPath.section == 0,
              selectedIndexPath.item >= 0,
              selectedIndexPath.item < hostCollectionVC.items.count,
              let host = hostCollectionVC.items[selectedIndexPath.item] as? TemporaryHost else {
            return
        }

        let uuid = host.uuid
        guard !uuid.isEmpty else { return }
        UserDefaults.standard.set(uuid, forKey: hostControllerNavigationHighlightedUUIDKey)
    }

    private func restoreHostControllerNavigationHighlight(in hostCollectionVC: HostCollectionViewController) {
        guard let uuid = UserDefaults.standard.string(forKey: hostControllerNavigationHighlightedUUIDKey),
              !uuid.isEmpty else {
            restoreFirstControllerNavigationItemIfNeeded()
            return
        }

        for index in 0..<hostCollectionVC.items.count {
            guard let host = hostCollectionVC.items[index] as? TemporaryHost,
                  host.uuid == uuid else {
                continue
            }

            highlightControllerNavigationItem(at: IndexPath(item: index, section: 0))
            return
        }

        restoreFirstControllerNavigationItemIfNeeded()
    }

    private func persistAppControllerNavigationHighlight() {
        guard let appView = currentControllerNavigationContentView() as? UIAppView,
              let appID = appView.app.id,
              !appID.isEmpty,
              let host = appView.app.host else {
            return
        }
        host.controllerNavigationHighlightedAppID = appID
        DataManager().update(host)
    }

    private func restoreAppControllerNavigationHighlight(in mainFrameVC: MainFrameViewController) {
        guard let appID = mainFrameVC.sortedAppList.first?.host?.controllerNavigationHighlightedAppID,
              !appID.isEmpty else {
            restoreFirstControllerNavigationItemIfNeeded()
            return
        }
        
        for (index, app) in mainFrameVC.sortedAppList.enumerated() where app.id == appID {
            highlightControllerNavigationItem(at: IndexPath(item: index, section: 0))
            return
        }

        restoreFirstControllerNavigationItemIfNeeded()
    }

    private func restoreFirstControllerNavigationItemIfNeeded() {
        guard collectionView.numberOfSections > 0,
              collectionView.numberOfItems(inSection: 0) > 0 else {
            clearCollectionControllerNavigationHighlight()
            return
        }

        highlightControllerNavigationItem(at: IndexPath(item: 0, section: 0))
    }

    private func performControllerNavigationSelectionMove(horizontalOffset: Int) {
        PublicUtils.runOnMain { [weak self] in
            self?.moveControllerNavigationSelection(horizontalOffset: horizontalOffset)
        }
    }

    private func performControllerNavigationSelectionMove(verticalOffset: Int) {
        PublicUtils.runOnMain { [weak self] in
            self?.moveControllerNavigationSelection(verticalOffset: verticalOffset)
        }
    }

    private func moveControllerNavigationSelection(horizontalOffset: Int) {
        let itemCount = collectionView.numberOfItems(inSection: 0)
        guard itemCount > 0 else {
            clearCollectionControllerNavigationHighlight()
            return
        }

        guard let currentIndexPath = currentControllerNavigationIndexPath() else {
            highlightControllerNavigationItem(at: IndexPath(item: horizontalOffset >= 0 ? 0 : itemCount - 1, section: 0))
            return
        }

        let nextItem = (currentIndexPath.item + horizontalOffset + itemCount) % itemCount
        highlightControllerNavigationItem(at: IndexPath(item: nextItem, section: currentIndexPath.section))
    }

    private func moveControllerNavigationSelection(verticalOffset: Int) {
        let itemCount = collectionView.numberOfItems(inSection: 0)
        guard itemCount > 0 else {
            clearCollectionControllerNavigationHighlight()
            return
        }

        guard let currentIndexPath = currentControllerNavigationIndexPath(),
              let currentAttributes = layoutAttributesForItem(at: currentIndexPath) else {
            highlightControllerNavigationItem(at: IndexPath(item: verticalOffset >= 0 ? 0 : itemCount - 1, section: 0))
            return
        }

        let currentCenter = currentAttributes.center
        let candidates = (0..<itemCount).compactMap { item -> (indexPath: IndexPath, attributes: UICollectionViewLayoutAttributes)? in
            let indexPath = IndexPath(item: item, section: 0)
            guard indexPath != currentIndexPath,
                  let attributes = layoutAttributesForItem(at: indexPath) else {
                return nil
            }

            let isTargetDirection = verticalOffset > 0
                ? attributes.center.y > currentCenter.y + 1
                : attributes.center.y < currentCenter.y - 1
            guard isTargetDirection else { return nil }

            return (indexPath, attributes)
        }

        let nextIndexPath = candidates.min { lhs, rhs in
            let lhsVerticalDistance = abs(lhs.attributes.center.y - currentCenter.y)
            let rhsVerticalDistance = abs(rhs.attributes.center.y - currentCenter.y)
            if abs(lhsVerticalDistance - rhsVerticalDistance) > 0.5 {
                return lhsVerticalDistance < rhsVerticalDistance
            }

            let lhsHorizontalDistance = abs(lhs.attributes.center.x - currentCenter.x)
            let rhsHorizontalDistance = abs(rhs.attributes.center.x - currentCenter.x)
            if abs(lhsHorizontalDistance - rhsHorizontalDistance) > 0.5 {
                return lhsHorizontalDistance < rhsHorizontalDistance
            }

            return verticalOffset > 0
                ? lhs.indexPath.item < rhs.indexPath.item
                : lhs.indexPath.item > rhs.indexPath.item
        }?.indexPath

        if let nextIndexPath {
            highlightControllerNavigationItem(at: nextIndexPath)
        }
    }

    private func currentControllerNavigationIndexPath() -> IndexPath? {
        if let selectedIndexPath = controllerNavigationSelectedIndexPath,
           selectedIndexPath.section < collectionView.numberOfSections,
           selectedIndexPath.item < collectionView.numberOfItems(inSection: selectedIndexPath.section) {
            return selectedIndexPath
        }

        if let highlightedView = ControllerNavigator.controllerNavigationHighlightedView,
           let highlightedCell = collectionViewCell(containing: highlightedView),
           let indexPath = collectionView.indexPath(for: highlightedCell) {
            return indexPath
        }

        return nil
    }

    private func highlightControllerNavigationItem(at indexPath: IndexPath) {
        PublicUtils.runOnMain { [weak self] in
            guard let self else { return }

            guard indexPath.section < self.collectionView.numberOfSections,
                  indexPath.item >= 0,
                  indexPath.item < self.collectionView.numberOfItems(inSection: indexPath.section) else {
                self.clearCollectionControllerNavigationHighlight()
                return
            }

            self.collectionView.layoutIfNeeded()

            let previousIndexPath = self.controllerNavigationSelectedIndexPath
            self.controllerNavigationSelectedIndexPath = indexPath

            if let previousIndexPath,
               previousIndexPath != indexPath,
               let previousCell = self.collectionView.cellForItem(at: previousIndexPath) {
                self.applyControllerNavigationHighlight(to: previousCell, highlighted: false)
            }

            self.collectionView.scrollToItem(at: indexPath, at: [.centeredHorizontally, .centeredVertically], animated: true)

            if let cell = self.collectionView.cellForItem(at: indexPath) {
                self.applyControllerNavigationHighlight(to: cell, highlighted: true)
                ControllerNavigator.controllerNavigationHighlightedView = self.controllerNavigationHighlightTargetView(for: cell)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.controllerNavigationSelectedIndexPath == indexPath,
                      let cell = self.collectionView.cellForItem(at: indexPath) else {
                    return
                }

                self.applyControllerNavigationHighlight(to: cell, highlighted: true)
                ControllerNavigator.controllerNavigationHighlightedView = self.controllerNavigationHighlightTargetView(for: cell)
            }
        }
    }

    private func clearCollectionControllerNavigationHighlight() {
        PublicUtils.runOnMain { [weak self] in
            guard let self else { return }

            if let selectedIndexPath = self.controllerNavigationSelectedIndexPath,
               let cell = self.collectionView.cellForItem(at: selectedIndexPath) {
                self.applyControllerNavigationHighlight(to: cell, highlighted: false)
            }

            self.controllerNavigationSelectedIndexPath = nil
            ControllerNavigator.controllerNavigationHighlightedView = nil
        }
    }

    fileprivate func clearCollectionControllerNavigationHighlightForControllerNavigator() {
        clearCollectionControllerNavigationHighlight()
    }

    private func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        collectionView.collectionViewLayout.layoutAttributesForItem(at: indexPath)
    }

    private func collectionViewCell(containing view: UIView) -> UICollectionViewCell? {
        var currentView: UIView? = view
        while let viewToCheck = currentView {
            if let cell = viewToCheck as? UICollectionViewCell {
                return cell
            }

            currentView = viewToCheck.superview
        }

        return nil
    }
}

extension MainFrameViewController {
    func forceLaunchApp(_ app: TemporaryApp?){
        if let currentRunningApp = self.findRunningApp(app?.host) {
            if currentRunningApp !== app {
                self.quitRunningAppAndStart(app)
            }
            else {
                self.launch(currentRunningApp)
            }
        }
        else {
            self.launch(app)
        }
    }
}

private var alertControllerNavigationHookInstalledKey: UInt8 = 0

@available(iOS 13.0, *)
extension UIAlertController: ControllerUINavigationDelegate {
    static func installControllerNavigationDelegateHook() {
        guard objc_getAssociatedObject(self, &alertControllerNavigationHookInstalledKey) == nil else { return }
        objc_setAssociatedObject(self, &alertControllerNavigationHookInstalledKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        swizzleAlertLifecycleMethod(
            originalSelector: #selector(UIViewController.viewDidAppear(_:)),
            swizzledSelector: #selector(UIAlertController.vl_controllerNavigationViewDidAppear(_:))
        )
        swizzleAlertLifecycleMethod(
            originalSelector: #selector(UIViewController.viewDidDisappear(_:)),
            swizzledSelector: #selector(UIAlertController.vl_controllerNavigationViewDidDisappear(_:))
        )
    }

    private static func swizzleAlertLifecycleMethod(originalSelector: Selector, swizzledSelector: Selector) {
        guard let originalMethod = class_getInstanceMethod(UIAlertController.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(UIAlertController.self, swizzledSelector) else {
            return
        }

        let didAddMethod = class_addMethod(
            UIAlertController.self,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        )

        if didAddMethod {
            class_replaceMethod(
                UIAlertController.self,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }

    @objc private func vl_controllerNavigationViewDidAppear(_ animated: Bool) {
        vl_controllerNavigationViewDidAppear(animated)
        ControllerNavigator.setUINavigationDelegate(self)
    }

    @objc private func vl_controllerNavigationViewDidDisappear(_ animated: Bool) {
        vl_controllerNavigationViewDidDisappear(animated)
        ControllerNavigator.restorePreviousUINavigationDelegate(ifCurrentDelegateIs: self)
    }

    func getNavigationElements() -> [ControllerNavigationElement] {
        let enabledActions = actions.filter { $0.isEnabled }
        guard let firstAction = enabledActions.first else { return [] }

        guard enabledActions.count > 1, let lastAction = enabledActions.last else {
            guard let title = firstAction.title, !title.isEmpty else { return [] }
            return [ControllerNavigationElement(control: ControllerNavigator.radialMenuButtonPosition == .left ? .dpadRight : .x, action: title)]
        }

        return [
            ControllerNavigationElement(control: ControllerNavigator.radialMenuButtonPosition == .left ? .dpadLeft : .x, action: firstAction.title ?? ""),
            ControllerNavigationElement(control: ControllerNavigator.radialMenuButtonPosition == .left ? .dpadRight : .b, action: lastAction.title ?? "")
        ].filter { !$0.action.isEmpty }
    }
    
    func navigateByController(forward: Bool) {}
    func navigateByController(downward: Bool) {}
    func persistControllerNavigationHighlight() {}
    func restoreControllerNavigationHighlight() {}
    func restoreControllerNavigationHighlightAfterSettingsModeSwitch() {}
    
    func uiWidgetActionForControllerNavigator(forward: Bool, from navigation: ControllerNavigationElement) {}
    
    func uiButtonActionForControllerNavigator(pressed: Bool, from navigation: ControllerNavigationElement) {
        guard pressed,
              let action = actions.first(where: { $0.title == navigation.action && $0.isEnabled }) else {
            return
        }

        performControllerNavigationAction(action)
    }

    private func performControllerNavigationAction(_ action: UIAlertAction) {
        let selector = NSSelectorFromString("_invokeHandlersForAction:")
        if responds(to: selector) {
            self.perform(selector, with: action)
            dismiss(animated: true)
            return
        }
    }
}

@available(iOS 13.0, *)
extension StreamFrameViewController: ControllerUINavigationDelegate {
    func getNavigationElements() -> [ControllerNavigationElement] {
        var elements = [ControllerNavigationElement]()
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButton, action: "radialMenu"))
        return elements
    }
    
    func navigateByController(forward: Bool) {}
    func navigateByController(downward: Bool) {}
    func persistControllerNavigationHighlight() {}
    func restoreControllerNavigationHighlight() {}
    func restoreControllerNavigationHighlightAfterSettingsModeSwitch() {}
    func uiWidgetActionForControllerNavigator(forward: Bool, from navigation: ControllerNavigationElement) {}
    func uiButtonActionForControllerNavigator(pressed: Bool, from navigation: ControllerNavigationElement) {}
}
