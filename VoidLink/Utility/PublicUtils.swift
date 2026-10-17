//
//  PublicUtils.swift
//  VoidLink
//
//  Created by True砖家 on 2026/2/26.
//  Copyright © 2026 True砖家@Bilibili. All rights reserved.
//


import Foundation
import ObjectiveC
import UIKit
import AVFoundation
import GameController

@objc public class PublicUtils: NSObject {
    
    @objc public static let isProductionBuild: Bool = {
        return ["com.voidlink.iOS"
            , "com.voidlinkextreme.iOS"
            , "com.voidlink.tf.debug10.iOS"
        ].contains(Bundle.main.bundleIdentifier)
    }()

    /// True when this build runs on Apple TV (tvOS), rather than iOS/iPadOS.
    @objc public static let isTVOS: Bool = {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }()
    @objc public static let tvOS26Aavailable: Bool = {
        if !PublicUtils.isTVOS {
            return false
        }
        if #available(tvOS 26.0, *) {
            return true
        }
        else {
            return false
        }
    }()

    @objc public static var isIPhone: Bool = {
        return UIDevice.current.userInterfaceIdiom == .phone
    }()

    @objc public static var isIPad: Bool = {
        return UIDevice.current.userInterfaceIdiom == .pad
    }()
    
    @objc public static var isRunningOnMacAsiPadApp: Bool = {
        if #available(iOS 14.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac
        }
        return false
    }()

    @objc(setControllerUserInteractionEnabled:inViewController:)
    public static func setControllerUserInteractionEnabled(_ enabled: Bool, in viewController: UIViewController?) {
        var enabled = enabled
        enabled = enabled && PublicUtils.isTVOS
        guard let rootViewController = viewController?.viewIfLoaded?.window?.rootViewController as? GCEventViewController else {
            return
        }

        var pendingViewControllers: [UIViewController] = [viewController!, rootViewController]
        var visitedViewControllers = Set<ObjectIdentifier>()
        while let currentViewController = pendingViewControllers.popLast() {
            guard visitedViewControllers.insert(ObjectIdentifier(currentViewController)).inserted else {
                continue
            }
            if let controllerViewController = currentViewController as? GCEventViewController {
                controllerViewController.controllerUserInteractionEnabled = enabled
            }
            if let parentViewController = currentViewController.parent {
                pendingViewControllers.append(parentViewController)
            }
            if let presentingViewController = currentViewController.presentingViewController {
                pendingViewControllers.append(presentingViewController)
            }
        }
        if enabled {
            rootViewController.setNeedsFocusUpdate()
            rootViewController.updateFocusIfNeeded()
        }
        ControllerNavigator.shouldBlockAppControllerNavigator = enabled
    }
    
    @objc public static let iOS26Available: Bool = {
        if #available(iOS 26.0, tvOS 26.0, *) {
            return true
        } else {
            return false
        }
    }()
        
    @objc public static let liquidGlassEnabled: Bool = {
        if #available(iOS 26.0, tvOS 26.0, *) {
            let useLegacyUI = Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool
            return useLegacyUI != true
        } else {
            return false
        }
    }()
    
    @objc public static var iOS27_2Available: Bool = {
        if #available(iOS 27.2, *) {return true}
        else {return false}
    }()
    
    @objc public static var iOS18Available: Bool = {
        if #available(iOS 18.0, tvOS 18.0, *) {return true}
        else {return false}
    }()
    
    @objc public static var iOS17_5Available: Bool = {
        if #available(iOS 17.5, *) {return true}
        else {return false}
    }()
    
    @objc public static var isZhHans: Bool = {
        if Locale.preferredLanguages.first!.hasPrefix("zh-Hans") { return true }
        else { return false }
    }()
        
    @objc public static var sessionStartTimestamp: TimeInterval = 0
    
    @objc public static var touchSectionAvailable: Bool = {
        return !isTVOS
    }()
    
    @objc public static var pencilSectionAvailable: Bool = {
        let availableIds = ["com.voidlink.iOS", "com.voidlinkextreme.iOS", "com.voidlink.tf.debug10.iOS"]
        return availableIds.contains(Bundle.main.bundleIdentifier ?? "") && isIPad
    }()
    
    @objc public static let isGUIWidgetPickerAvailable: Bool = {
        if #available(iOS 13.0, tvOS 13.0, *) {
            return true
        } else {
            return false
        }
    }()
    
    @objc public static let isIAPAddonAvailable: Bool = {
        let availableBundleIds = ["com.voidlink.iOS", "com.voidlinkextreme.iOS", "com.voidlink.tf.debug10.iOS"]
        return availableBundleIds.contains(Bundle.main.bundleIdentifier ?? "")
    }()
    
    @objc public static func isLandscape() -> Bool {
#if os(tvOS)
        return true
#else
        if #available(iOS 13.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
            else {return false}
            return windowScene.interfaceOrientation.isLandscape
        }
        else {return PublicUtils.screenWidth > PublicUtils.screenHeight}
#endif
    }
    
    @objc public static func disconnectSymbol() -> String {
        if #available(iOS 18.0, tvOS 18.0, *) {
            return "personalhotspot.slash"
        }
        else if #available(iOS 14.0, tvOS 14.0, *) {
            return "rectangle.slash"
        }
        else {
            return "nosign"
        }
    }

    @objc public static func installTextFieldControllerUserInteractionTracking() {
#if os(tvOS)
        UITextField.installControllerUserInteractionTracking()
#endif
    }
    
    @objc public static func controllerMouseSymbol() -> String {
        if #available(iOS 17.0, tvOS 17.0, *) {
            return "pointer.arrow.ipad"
        }
        else if #available(iOS 16.0, tvOS 16.0, *) {
            return "pointer.arrow.ipad"
        }
        else {
            return "paperplane"
        }
    }
    
    @objc public static func disableControllerMouseSymbol() -> String {
        if #available(iOS 17.0, tvOS 17.0, *) {
            return "pointer.arrow.slash.square"
        }
        else if #available(iOS 16.0, tvOS 16.0, *) {
            return "pointer.arrow"
        }
        else {
            return "paperplane"
        }
    }
    
    @objc public static func quitSymbol() -> String {
        if #available(iOS 14.0, tvOS 14.0, *) {
            return "pip.exit"
        }
        else {
            return "arrow.left.square"
        }
    }

    @objc public static func disconnectSymbolSize() -> CGFloat {
        if #available(iOS 26.0, tvOS 26.0, *) {
            return 15
        }
        if #available(iOS 18.0, tvOS 18.0, *) {
            return 19
        }
        else if #available(iOS 14.0, tvOS 14.0, *) {return 17.5}
        else {return 20.7}
    }
    
    @objc public static func disconnectSymbolWeight() -> Int {
        if #available(iOS 26.0, tvOS 26.0, *) {
            return UIImage.SymbolWeight.bold.rawValue
        }
        if #available(iOS 18.0, tvOS 18.0, *) {
            return UIImage.SymbolWeight.semibold.rawValue
        }
        else if #available(iOS 13.0, tvOS 13.0, *) {return UIImage.SymbolWeight.semibold.rawValue}
        else {return 666}
    }

    
    @objc public static func toCGFloat(_ str: String) -> CGFloat {
        return CGFloat(Double(str) ?? 0)
    }
        
    @objc public static func viewIsLandscape(_ view: UIView?) -> Bool {
        guard let view else {return false}
        return view.bounds.width > view.bounds.height
    }
    
    @objc public static var screenWidth: CGFloat {
        return UIScreen.main.bounds.width
    }
    
    @objc public static var screenHeight: CGFloat {
        return UIScreen.main.bounds.height
    }
    
    @objc public static var refreshRate: CGFloat = {
        return CGFloat(UIScreen.main.maximumFramesPerSecond)
    }()

        
    @objc(parentViewControllerForView:)
    static func parentViewController(for view: UIView?) -> UIViewController? {
        var responder: UIResponder? = view
        while let currentResponder = responder {
            if let viewController = currentResponder as? UIViewController {
                return viewController
            }
            responder = currentResponder.next
        }
        return nil
    }

    @objc public static func rootViewController() -> UIViewController? {
        if #available(iOS 13.0, *) {
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .windows
                .first { $0.isKeyWindow }?
                .rootViewController
        } else {
            return UIApplication.shared.keyWindow?.rootViewController
        }
    }

    @objc public static func topViewController() -> UIViewController? {
        return topViewController(from: rootViewController())
    }

    private static func topViewController(from rootViewController: UIViewController?) -> UIViewController? {
        if let navigationController = rootViewController as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = rootViewController as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }

        if let splitViewController = rootViewController as? UISplitViewController,
           let lastViewController = splitViewController.viewControllers.last {
            return topViewController(from: lastViewController)
        }

        if let presentedViewController = rootViewController?.presentedViewController {
            return topViewController(from: presentedViewController)
        }

        return rootViewController
    }
    
    @objc public static func hasNoPresentedVC(_ vc: UIViewController) -> Bool {
        let hasNoPresentedVC = vc.presentedViewController == nil && vc.view.window != nil
        return hasNoPresentedVC
    }
    
    #if os(iOS)
    @objc(getCurrentOrientationForWindow:)
    public static func getCurrentOrientation(for window: UIWindow?) -> UIInterfaceOrientationMask {
        let size = window?.bounds.size ?? .zero
        return size.width > size.height ? .landscape : [.portrait, .portraitUpsideDown]
    }
    #endif

    public static func runOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }

    @objc public static func controllerMouseExpoMappedOffset(_ offset: CGFloat, expo: CGFloat) -> CGFloat {
        guard offset != 0 else { return 0 }
        let magnitude = pow(abs(offset), expo)
        return offset > 0 ? magnitude : -magnitude
    }

    @objc public static func controllerMouseVelocity(pointerVelocity: CGFloat, frameRate: CGFloat) -> CGFloat {
        guard frameRate > 0 else { return pointerVelocity }
        return pointerVelocity * 60 / frameRate
    }

    @objc public static func controllerMouseMoveVector(stickX: CGFloat, stickY: CGFloat, velocity: CGFloat, expo: CGFloat) -> CGVector {
        let hypot = hypot(stickX, stickY)
        guard hypot > 0 else {return CGVector(dx: 0, dy: 0)}
        let targetHypot = controllerMouseExpoMappedOffset(hypot, expo: expo)
        let targetX = targetHypot * (stickX/hypot)
        let targetY = targetHypot * (stickY/hypot)
        return CGVector(
            dx: targetX * velocity,
            dy: -targetY * velocity
        )
    }

    @objc public static func controllerMouseScrollVector(stickX: CGFloat, stickY: CGFloat, multiplier: CGFloat) -> CGVector {
        return CGVector(dx: multiplier * stickX, dy: multiplier * stickY)
    }
        
    @objc(openUrl:)
    static func openUrl(_ urlString: String) {
        guard let url = URL(string: urlString),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    @objc static var onScreenRuntimeStats: String = ""
    
    @objc static var tvOSSoftkeyboardBeingEnteredByController: Bool = false
    @objc static var tvOSSoftkeyboardIsWorking: Bool = false
    // @objc static var controllerMovedFocusOnTvOSSoftKeyboard:Bool = false
}

#if os(tvOS)
private var textFieldControllerUserInteractionTrackingKey: UInt8 = 0
private var willEndStreamTextSession:Bool = false
private var willSendEnterToHost:Bool = false

private extension UITextField {
    
    static func installControllerUserInteractionTracking() {
        _ = controllerUserInteractionTrackingInstalled
    }

    static let controllerUserInteractionTrackingInstalled: Void = {
        guard let originalMethod = class_getInstanceMethod(
            UITextField.self,
            #selector(UIView.didMoveToWindow)
        ), let swizzledMethod = class_getInstanceMethod(
            UITextField.self,
            #selector(UITextField.vl_publicUtilsDidMoveToWindow)
        ) else {
            return
        }

        let originalSelector = #selector(UIView.didMoveToWindow)
        let swizzledSelector = #selector(UITextField.vl_publicUtilsDidMoveToWindow)
        if class_addMethod(
            UITextField.self,
            originalSelector,
            method_getImplementation(swizzledMethod),
            method_getTypeEncoding(swizzledMethod)
        ) {
            class_replaceMethod(
                UITextField.self,
                swizzledSelector,
                method_getImplementation(originalMethod),
                method_getTypeEncoding(originalMethod)
            )
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }()

    @objc func vl_publicUtilsDidMoveToWindow() {
        vl_publicUtilsDidMoveToWindow()
        guard window != nil,
              objc_getAssociatedObject(self, &textFieldControllerUserInteractionTrackingKey) == nil else {
            return
        }

        objc_setAssociatedObject(self, &textFieldControllerUserInteractionTrackingKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        addTarget(self, action: #selector(UITextField.vl_publicUtilsEditingDidBegin), for: .editingDidBegin)
        addTarget(self, action: #selector(UITextField.vl_publicUtilsEditingDidEnd), for: .editingDidEnd)
    }
    
    private func getNavigationElements() -> [ControllerNavigationElement] {
        var elements: [ControllerNavigationElement] = []
        elements.append(ControllerNavigationElement(control: ControllerNavigator.radialMenuButtonPosition == .left ? .rightStick : .leftStick, action: "focusNavigation"))
        elements.append(ControllerNavigationElement(control: ControllerNavigator.radialMenuButtonPosition == .left ? .dpadRight : .a, action: "execute"))
        elements.append(ControllerNavigationElement(control:ControllerNavigator.radialMenuButtonPosition == .left ? .dpadUp : .rightTrigger, action: "holdToEndWithEnter"))
        return elements
    }

    @objc func vl_publicUtilsEditingDidBegin() {
        PublicUtils.tvOSSoftkeyboardIsWorking = true
        // PublicUtils.controllerMovedFocusOnTvOSSoftKeyboard = false
        PublicUtils.setControllerUserInteractionEnabled(true, in: PublicUtils.parentViewController(for: self))

        if self.accessibilityIdentifier == "streamRemoteTextField" {
            if (ControllerUtil.delegate as? MainFrameViewController)?.isStreaming() == true { ControllerNavigator.dimissRadialMenu()
            }
            willEndStreamTextSession = false
            willSendEnterToHost = false
            ControllerUtil.listenPrimaryControllerButton(.a) {pressed in
                PublicUtils.tvOSSoftkeyboardBeingEnteredByController = pressed
                if pressed {
                    willEndStreamTextSession = true
                }
                else {
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.02) {
                        willEndStreamTextSession = !PublicUtils.tvOSSoftkeyboardBeingEnteredByController
                    }
                }
            }
            ControllerUtil.listenPrimaryControllerButton(.leftTrigger) {pressed in
                willSendEnterToHost = pressed
            }
            ControllerUtil.listenPrimaryControllerStick(.leftStick) { offsetVector in
                /*
                 if(!PublicUtils.controllerMovedFocusOnTvOSSoftKeyboard) {
                 PublicUtils.controllerMovedFocusOnTvOSSoftKeyboard = true
                 } */
            }
        }
    }

    @objc func vl_publicUtilsEditingDidEnd() {
        PublicUtils.tvOSSoftkeyboardIsWorking = false
        PublicUtils.setControllerUserInteractionEnabled(false, in: PublicUtils.parentViewController(for: self))
        if self.accessibilityIdentifier == "streamRemoteTextField" {
            ControllerUtil.clearPrimaryControllerButtonHandler(.a)
            ControllerUtil.clearPrimaryControllerButtonHandler(.rightTrigger)
            ControllerUtil.clearPrimaryControllerStickHandler(.leftStick)
            if willEndStreamTextSession {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .VoidLinkTvOSRemotePlayPauseTapped,
                        object: nil
                    )
                }
            }
            if willSendEnterToHost {
                DispatchQueue.main.asyncAfter(deadline: .now()+0.1) {
                    CommandManager.shared.sendAutoReleaseComboCommand(cmdStrings: ["ENTER"], delay: 0.05)
                }
            }
        }
        GamepadNavigationIllustrationHud.updateHud(forceDisplay: true)
    }
}
#endif
