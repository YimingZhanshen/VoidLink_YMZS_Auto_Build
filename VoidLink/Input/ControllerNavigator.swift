//
//  ControllerNavigator.swift
//  VoidLink
//
//  Created by True砖家 on 2026/7/1.
//  Copyright © 2026 True砖家 on Bilibili. All rights reserved.
//

import Foundation
import GameController

@available(iOS 13.0, *)
@objc protocol ControllerNavigatorRadialMenuDelegate: AnyObject {
    func controllerNavigatorDidSelectSettings()
    func controllerNavigatorDidSelectHostView()
    func controllerNavigatorDidSelectGameProfiles()
    func controllerNavigatorDidSelectExit()
    func isStreaming() -> Bool
    func isInAppView() -> Bool
}

@available(iOS 13.0, *)
@objc protocol ControllerUINavigationDelegate: AnyObject {
    func nextItemForControllerNavigator()
    func previousItemForControllerNavigator()
}

@available(iOS 13.0, *)
final class ControllerNavigator: NSObject {
    typealias Handler = (_ buttonDict: NSDictionary, _ gamepad: GCExtendedGamepad, _ element: GCControllerElement) -> Void

    private static var connectObserver: NSObjectProtocol?
    private static var disconnectObserver: NSObjectProtocol?
    private static weak var listeningController: GCController?
    private static weak var radialMenuDelegate: ControllerNavigatorRadialMenuDelegate?
    private static weak var uiNavigationDelegate: ControllerUINavigationDelegate?
    private static var swapABXY = false
    private static var radialMenuView: RadialMenuOverlayView?
    private static var localRadialMenuButton: ControllerButton = .leftShoulder
    private static var localRadialMenuButtonFlag: Bool = false

    @objc static func setRadialMenuDelegate(_ delegate: ControllerNavigatorRadialMenuDelegate?) {
        radialMenuDelegate = delegate
    }

    @objc static func setUINavigationDelegate(_ delegate: ControllerUINavigationDelegate?) {
        uiNavigationDelegate = delegate
    }
    
    @objc static func start(swapABXY: Bool = false) {
        Self.swapABXY = swapABXY
        installControllerObserversIfNeeded()
        listenFirstAvailableController()
    }

    @objc static func stop() {
        stopListeningCurrentController()
        removeControllerObservers()
    }

    static func listen(controller: GCController, swapABXY: Bool = false) {
        guard controller.extendedGamepad != nil else { return }
        listeningController = controller
        ControllerUtil.listen(controller: controller, swapABXY: swapABXY) { buttonDict, gamepad, element in

            if let gcButton = buttonDict[localRadialMenuButton.rawValue] as? GCControllerButtonInput {
                if gcButton.isPressed != localRadialMenuButtonFlag {
                    if gcButton.isPressed, radialMenuView == nil {
                        RadialMenuOverlayView.menuSectors.removeAll()
                        RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Settings Menu".localized, subtitle: "", systemImageName: "sidebar.left", item: .settings))
                        if radialMenuDelegate?.isInAppView() == true, !(radialMenuDelegate?.isStreaming() ?? false) {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Host View".localized, subtitle: "", systemImageName: PublicUtils.liquidGlassEnabled ? "macwindow.on.rectangle" : "tv", item: .hostView))}
                        if radialMenuDelegate?.isStreaming() == true {RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Disconnect".localized, subtitle: "", systemImageName: PublicUtils.disconnectSymbol(), item: .exit))}
                        RadialMenuOverlayView.menuSectors.append(RadialMenuSector(title: "Game Profiles".localized, subtitle: "", systemImageName:PublicUtils.iOS18Available ? "gamecontroller.circle" : "gamecontroller.fill", item: .gameProfiles))
                        
                        radialMenuView = RadialMenuOverlayView.presentInKeyWindow()
                    }
                    if !gcButton.isPressed {
                        radialMenuView?.dismiss()
                        radialMenuView = nil
                    }
                }
                localRadialMenuButtonFlag = gcButton.isPressed
            }
                        
            if let selectedItem = radialMenuView?.updateSelection(
                xOffset: gamepad.rightThumbstick.xAxis.value,
                yOffset: gamepad.rightThumbstick.yAxis.value
            ) {
                performRadialMenuAction(selectedItem)
            }
        }
    }

    private static func installControllerObserversIfNeeded() {
        guard connectObserver == nil, disconnectObserver == nil else { return }

        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { notification in
            guard (notification.object as? GCController)?.extendedGamepad != nil else { return }
            listenFirstAvailableController()
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { notification in
            listenFirstAvailableController()
        }
    }

    private static func removeControllerObservers() {
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
            self.connectObserver = nil
        }

        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
            self.disconnectObserver = nil
        }
    }

    private static func listenFirstAvailableController() {
        guard let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }) else {
            stopListeningCurrentController()
            radialMenuView?.dismiss()
            radialMenuView = nil
            return
        }
        
        listen(controller: controller)
    }

    private static func listen(controller: GCController) {
        guard controller !== listeningController else { return }
        stopListeningCurrentController()
        
        if #available(iOS 14.0, *) {
            for element in controller.physicalInputProfile.allElements {
                element.preferredSystemGestureState = .disabled
            }
        }

        listen(controller: controller, swapABXY: swapABXY)
    }

    private static func stopListeningCurrentController() {
        listeningController?.extendedGamepad?.valueChangedHandler = nil
        listeningController = nil
    }

    private static func performRadialMenuAction(_ item: RadialMenuItem) {
        switch item {
        case .settings:
            radialMenuDelegate?.controllerNavigatorDidSelectSettings()

        case .hostView:
            radialMenuDelegate?.controllerNavigatorDidSelectHostView()

        case .gameProfiles:
            radialMenuDelegate?.controllerNavigatorDidSelectGameProfiles()

        case .exit:
            radialMenuDelegate?.controllerNavigatorDidSelectExit()
        }
    }
}
