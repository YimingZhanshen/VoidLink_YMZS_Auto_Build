//
//  ControllerUtil.swift
//  VoidLink
//
//  Created by True砖家 on 2025/11/19.
//  Copyright © 2025 True砖家 on Bilibili. All rights reserved.
//


import GameController
import Combine
import CoreGraphics
import Foundation
#if !VOIDLINK_PREVIEW
import Collections
#endif

@objc enum ControllerElementType: Int {
    case button
    case stick
    case stickAxis
    case touchpad
    case cluster
    case undefined
}

@objc enum ControllerElementPosition: Int {
    case left
    case right
    case middle
    case undefined
}

@objc enum ControllerElement: Int32 {
    // Face buttons
    case a = 0x1000
    case b = 0x2000
    case x = 0x4000
    case y = 0x8000
    
    // DPad
    case dpadUp    = 0x0001
    case dpadDown  = 0x0002
    case dpadLeft  = 0x0004
    case dpadRight = 0x0008
    
    // Shoulder
    case leftShoulder  = 0x0100
    case rightShoulder = 0x0200
    
    // Stick click
    case leftStickButton  = 0x0040
    case rightStickButton = 0x0080
    
    // Menu/Back/Special
    case start    = 0x0010 // PLAY_FLAG
    case select    = 0x0020 // BACK_FLAG
    case special = 0x0400
    
    // Extended buttons (Sunshine only)
    case paddle1  = 0x010000
    case paddle2  = 0x020000
    case paddle3  = 0x040000
    case paddle4  = 0x080000
    case touchpadButton = 0x100000
    case misc     = 0x200000
    
    case leftTrigger  = 0x400000
    case rightTrigger = 0x800000
    
    case leftStick = 0x800010
    case leftStickX = 0x80011
    case leftStickY = 0x800012
    case rightStick = 0x800020
    case rightStickX = 0x800021
    case rightStickY = 0x800022
    
    case dpad = 0x800013
    case abxy = 0x800023

    case null = 0xFFFFFF

    var displayName: String {
        switch self {
        case .a: return "A"
        case .b: return "B"
        case .x: return "X"
        case .y: return "Y"

        case .dpadUp: return "DPadU".localized
        case .dpadDown: return "DPadD".localized
        case .dpadLeft: return "DPadL".localized
        case .dpadRight: return "DPadR".localized

        case .leftShoulder: return "LB"
        case .rightShoulder: return "RB"

        case .leftStickButton: return "LS"
        case .rightStickButton: return "RS"

        case .start: return "Start"
        case .select: return "Select"
        case .special: return "Home"

        case .paddle1: return "Paddle1".localized
        case .paddle2: return "Paddle2".localized
        case .paddle3: return "Paddle3".localized
        case .paddle4: return "Paddle4".localized
        case .touchpadButton: return "TouchBtn".localized
        case .misc: return "Misc"

        case .leftTrigger: return "LT"
        case .rightTrigger: return "RT"

        case .leftStick: return "LStick".localized
        case .leftStickX: return "LStickX".localized
        case .leftStickY: return "LStickY".localized
        case .rightStick: return "RStick".localized
        case .rightStickX: return "RStickX".localized
        case .rightStickY: return "RStickY".localized
            
        case .dpad: return "DPad".localized
        case .abxy: return "ABXY".localized

        case .null: return "Null".localized
        }
    }
    
    var symbol: String {
        switch self {
        case .dpadUp:
            if #available(iOS 15.0, *) {return "dpad.up.filled"}
            else {return ""}
        case .dpadDown:
            if #available(iOS 15.0, *) {return "dpad.down.filled"}
            else {return ""}
        case .dpadLeft:
            if #available(iOS 15.0, *) {return "dpad.left.filled"}
            else {return ""}
        case .dpadRight:
            if #available(iOS 15.0, *) {return "dpad.right.filled"}
            else {return ""}
        case .dpad:
            if #available(iOS 14.0, *) {return "dpad"}
            else {return ""}
        case .a:
            if #available(iOS 15.0, *) {return "circle.grid.cross.down.filled"}
            else {return ""}
        case .b:
            if #available(iOS 15.0, *) {return "circle.grid.cross.right.filled"}
            else {return ""}
        case .x:
            if #available(iOS 15.0, *) {return "circle.grid.cross.left.filled"}
            else {return ""}
        case .y:
            if #available(iOS 15.0, *) {return "circle.grid.cross.up.filled"}
            else {return ""}
        case .abxy:
            if #available(iOS 14.0, *) {return "circle.grid.cross"}
            else {return ""}

        default: return ""
        }
    }
    
    var type: ControllerElementType {
        switch self {
        case .a: return .button
        case .b: return .button
        case .x: return .button
        case .y: return .button

        case .dpadUp: return .button
        case .dpadDown: return .button
        case .dpadLeft: return .button
        case .dpadRight: return .button

        case .leftShoulder: return .button
        case .rightShoulder: return .button

        case .leftStickButton: return .button
        case .rightStickButton: return .button

        case .start: return .button
        case .select: return .button
        case .special: return .button

        case .paddle1: return .button
        case .paddle2: return .button
        case .paddle3: return .button
        case .paddle4: return .button
        case .touchpadButton: return .button
        case .misc: return .button

        case .leftTrigger: return .button
        case .rightTrigger: return .button

        case .leftStick: return .stick
        case .leftStickX: return .stickAxis
        case .leftStickY: return .stickAxis
        case .rightStick: return .stick
        case .rightStickX: return .stickAxis
        case .rightStickY: return .stickAxis
        
        case .dpad: return .cluster
        case .abxy: return .cluster

        case .null: return .undefined
        }
    }
    
    var position: ControllerElementPosition {
        switch self {
        case .a: return .right
        case .b: return .right
        case .x: return .right
        case .y: return .right

        case .dpadUp: return .left
        case .dpadDown: return .left
        case .dpadLeft: return .left
        case .dpadRight: return .left

        case .leftShoulder: return .left
        case .rightShoulder: return .right

        case .leftStickButton: return .left
        case .rightStickButton: return .right

        case .start: return .right
        case .select: return .left
        case .special: return .undefined

        case .paddle1: return .right
        case .paddle2: return .right
        case .paddle3: return .left
        case .paddle4: return .left
        case .touchpadButton: return .middle
        case .misc: return .undefined

        case .leftTrigger: return .left
        case .rightTrigger: return .right

        case .leftStick: return .left
        case .leftStickX: return .left
        case .leftStickY: return .left
        case .rightStick: return .right
        case .rightStickX: return .right
        case .rightStickY: return .right
            
        case .abxy: return .right
        case .dpad: return .left

        case .null: return .undefined
        }
    }
}

@objc protocol ControllerUtilDelegate: AnyObject {
    func isStreaming() -> Bool
    func isInAppView() -> Bool
}

@objc class ControllerUtil: NSObject {
    @objc static weak var delegate: ControllerUtilDelegate?

#if !VOIDLINK_PREVIEW
    private struct DualSensePCMChunk {
        let controllerNumber: UInt16
        let flags: UInt8
        let sequenceNumber: UInt32
        let presentationTimeUs: UInt64
        let frameCount: UInt16
        let pcmData: Data
    }

    private final class AuthoredEngineState {
        var engine: OpaquePointer?
        var renderHostAnchorUs: UInt64?
        var renderLocalAnchor = 0.0

        init?() {
            var config = AhAuthoredConfig()
            guard ah_authored_config_init(&config, 48_000) == AH_STATUS_OK else {
                return nil
            }
            guard ah_authored_create(&config, &engine) == AH_STATUS_OK, engine != nil else {
                return nil
            }
        }

        deinit {
            ah_authored_destroy(engine)
        }

        func renderDelay(for timestampUs: UInt64, resetTimeline: Bool) -> TimeInterval {
            let now = ProcessInfo.processInfo.systemUptime
            if resetTimeline || renderHostAnchorUs == nil {
                renderHostAnchorUs = timestampUs
                renderLocalAnchor = now + 0.01
            }
            let anchor = renderHostAnchorUs ?? timestampUs
            let hostDelta = timestampUs >= anchor ? Double(timestampUs - anchor) / 1_000_000.0 : 0
            return min(max(renderLocalAnchor + hostDelta - now, 0), 0.08)
        }
    }

    private static let dualSenseHapticsLock = NSLock()
    private static let dualSenseHapticsWorker = DispatchQueue(
        label: "com.voidlink.dualsense-authored-haptics",
        qos: .userInteractive
    )
    private static let maxQueuedDualSensePCMChunks = 8
    private static var dualSensePCMQueue = Deque<DualSensePCMChunk>()
    private static var dualSenseWorkerScheduled = false
    private static var dualSenseForcedDiscontinuities = Set<UInt16>()
    private static var dualSenseAuthoredEngines = [UInt16: AuthoredEngineState]()

    @objc(enqueueDualSenseHapticsPCMWithControllerNumber:flags:sequenceNumber:presentationTimeUs:frameCount:pcmData:)
    static func enqueueDualSenseHapticsPCM(
        controllerNumber: UInt16,
        flags: UInt8,
        sequenceNumber: UInt32,
        presentationTimeUs: UInt64,
        frameCount: UInt16,
        pcmData: Data
    ) {
        let expectedByteCount = Int(frameCount) * 2 * MemoryLayout<Int16>.size
        guard frameCount <= 480, pcmData.count == expectedByteCount else {
            NSLog("DualSense haptics: rejected malformed PCM chunk for controller %u", controllerNumber)
            return
        }

        let chunk = DualSensePCMChunk(
            controllerNumber: controllerNumber,
            flags: flags,
            sequenceNumber: sequenceNumber,
            presentationTimeUs: presentationTimeUs,
            frameCount: frameCount,
            pcmData: pcmData
        )

        dualSenseHapticsLock.lock()
        if dualSensePCMQueue.count >= maxQueuedDualSensePCMChunks,
           let dropped = dualSensePCMQueue.popFirst() {
            dualSenseForcedDiscontinuities.insert(dropped.controllerNumber)
        }
        dualSensePCMQueue.append(chunk)
        let shouldScheduleWorker = !dualSenseWorkerScheduled
        dualSenseWorkerScheduled = true
        dualSenseHapticsLock.unlock()

        if shouldScheduleWorker {
            dualSenseHapticsWorker.async {
                drainDualSensePCMQueue()
            }
        }
    }

    @objc static func stopAllDualSenseHaptics() {
        ControllerSupport.sharedInstance()?.cancelScheduledDualSenseHaptics()

        dualSenseHapticsLock.lock()
        dualSensePCMQueue.removeAll(keepingCapacity: true)
        dualSenseForcedDiscontinuities.removeAll(keepingCapacity: true)
        dualSenseHapticsLock.unlock()

        dualSenseHapticsWorker.async {
            let controllerNumbers = Array(dualSenseAuthoredEngines.keys)
            dualSenseAuthoredEngines.removeAll(keepingCapacity: false)
            for controllerNumber in controllerNumbers {
                renderDualSenseHaptics(controllerNumber: controllerNumber, left: nil, right: nil, delay: 0)
            }
        }
    }

    private static func drainDualSensePCMQueue() {
        while true {
            dualSenseHapticsLock.lock()
            guard var chunk = dualSensePCMQueue.popFirst() else {
                dualSenseWorkerScheduled = false
                dualSenseHapticsLock.unlock()
                return
            }
            if dualSenseForcedDiscontinuities.remove(chunk.controllerNumber) != nil {
                chunk = DualSensePCMChunk(
                    controllerNumber: chunk.controllerNumber,
                    flags: chunk.flags | 0x04,
                    sequenceNumber: chunk.sequenceNumber,
                    presentationTimeUs: chunk.presentationTimeUs,
                    frameCount: chunk.frameCount,
                    pcmData: chunk.pcmData
                )
            }
            dualSenseHapticsLock.unlock()
            processDualSensePCMChunk(chunk)
        }
    }

    private static func processDualSensePCMChunk(_ chunk: DualSensePCMChunk) {
        let isStreamStart = (chunk.flags & 0x01) != 0
        let isStreamEnd = (chunk.flags & 0x02) != 0
        let isDiscontinuity = (chunk.flags & 0x04) != 0

        if isStreamStart || dualSenseAuthoredEngines[chunk.controllerNumber] == nil {
            dualSenseAuthoredEngines[chunk.controllerNumber] = AuthoredEngineState()
            NSLog("DualSense haptics: stream started for controller %u", chunk.controllerNumber)
        }
        guard let state = dualSenseAuthoredEngines[chunk.controllerNumber],
              let engine = state.engine else {
            NSLog("DualSense haptics: failed to create authored engine for controller %u", chunk.controllerNumber)
            return
        }

        var inputFlags: UInt32 = 0
        if isStreamStart { inputFlags |= UInt32(AH_AUTHORED_INPUT_STREAM_START) }
        if isDiscontinuity { inputFlags |= UInt32(AH_AUTHORED_INPUT_DISCONTINUITY) }
        if isStreamEnd { inputFlags |= UInt32(AH_AUTHORED_INPUT_STREAM_END) }

        var samples = [Int16](repeating: 0, count: Int(chunk.frameCount) * 2)
        chunk.pcmData.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            for index in samples.indices {
                let offset = index * 2
                let value = UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
                samples[index] = Int16(bitPattern: value)
            }
        }

        let outputCapacity = ah_authored_get_max_output_frames(
            engine,
            UInt32(chunk.frameCount),
            inputFlags
        )
        var outputFrames = [AhAuthoredHapticFrame](
            repeating: AhAuthoredHapticFrame(),
            count: Int(outputCapacity)
        )
        var outputCount: UInt32 = 0
        let status = samples.withUnsafeBufferPointer { sampleBuffer -> AhStatus in
            var input = AhAuthoredProcessInput()
            input.struct_size = UInt32(MemoryLayout<AhAuthoredProcessInput>.size)
            input.interleaved_pcm = sampleBuffer.baseAddress
            input.frame_count = UInt32(chunk.frameCount)
            input.flags = inputFlags
            input.first_sample_time_us = chunk.presentationTimeUs
            input.sequence_number = chunk.sequenceNumber
            return ah_authored_process_i16(
                engine,
                &input,
                &outputFrames,
                outputCapacity,
                &outputCount
            )
        }

        guard status == AH_STATUS_OK || status == AH_STATUS_OUTPUT_AVAILABLE else {
            NSLog("DualSense haptics: authored conversion failed with status %d", status)
            ah_authored_reset(engine)
            renderDualSenseHaptics(controllerNumber: chunk.controllerNumber, left: nil, right: nil, delay: 0)
            return
        }

        var finalRenderDelay = 0.0
        for index in 0..<Int(outputCount) {
            let frame = outputFrames[index]
            let silent = (frame.flags & UInt32(AH_AUTHORED_FRAME_SILENT)) != 0
            let resetTimeline = isStreamStart || isDiscontinuity ||
                (frame.flags & UInt32(AH_AUTHORED_FRAME_DISCONTINUITY)) != 0
            let delay = state.renderDelay(for: frame.timestamp_us, resetTimeline: resetTimeline && index == 0)
            finalRenderDelay = max(finalRenderDelay, delay)
            renderDualSenseHaptics(
                controllerNumber: chunk.controllerNumber,
                left: silent ? nil : frame.lanes.0,
                right: silent ? nil : frame.lanes.1,
                delay: delay
            )
        }

        if isStreamEnd {
            renderDualSenseHaptics(
                controllerNumber: chunk.controllerNumber,
                left: nil,
                right: nil,
                delay: finalRenderDelay + 0.005
            )
            dualSenseAuthoredEngines.removeValue(forKey: chunk.controllerNumber)
            NSLog("DualSense haptics: stream ended for controller %u", chunk.controllerNumber)
        }
    }

    private static func renderDualSenseHaptics(
        controllerNumber: UInt16,
        left: AhAuthoredLaneFrame?,
        right: AhAuthoredLaneFrame?,
        delay: TimeInterval
    ) {
        guard let controllerSupport = ControllerSupport.sharedInstance() else {
            return
        }

        let leftAmplitude = min(max(left?.rms_amplitude ?? 0, 0), 1)
        let rightAmplitude = min(max(right?.rms_amplitude ?? 0, 0), 1)
        let leftSharpness = min(max(1 - (left?.low_band_ratio ?? 1), 0), 1)
        let rightSharpness = min(max(1 - (right?.low_band_ratio ?? 1), 0), 1)
        let leftTransient = min(max(left?.transient_strength ?? 0, 0), 1)
        let rightTransient = min(max(right?.transient_strength ?? 0, 0), 1)

        controllerSupport.renderDualSenseHaptics(
            controllerNumber,
            leftAmplitude: leftAmplitude,
            leftSharpness: leftSharpness,
            leftTransient: leftTransient,
            rightAmplitude: rightAmplitude,
            rightSharpness: rightSharpness,
            rightTransient: rightTransient,
            delaySeconds: delay
        )
    }
#endif
    
    static private let stickMaxOffset:CGFloat = 0x7FFE
    @objc static var navigationActionTriggered:Bool = false
    @objc static private(set) var navigationActionTriggeredPrivate:Bool = false
    
    @objc static func listen(
        controller: GCController,
        swapABXY: Bool,
        handler: @escaping (_ elementDict: NSDictionary,
                            _ gamepad: GCExtendedGamepad,
                            _ element: GCControllerElement) -> Void
    ) {
        guard let gamepad = controller.extendedGamepad else { return }
        
        // 内部生成 map
        var tempMap: [NSNumber: GCControllerElement] = [:]
        let swiftMap = buildMapping(for: controller, swapABXY: swapABXY)
        for (button, input) in swiftMap {
            tempMap[NSNumber(value: button.rawValue)] = input
        }
        let elementDict = tempMap as NSDictionary
        
        // 单一 gamepad.valueChangedHandler
        gamepad.valueChangedHandler = { gamepad, element in
            handler(elementDict, gamepad, element)
            if #available(iOS 13.0, *) {
                // print("controller.playerIndex \(controller.playerIndex)")
                if controller.playerIndex == .index1 {
                    GamepadOverlayStateCenter.shared.publish(snapshot: GamepadOverlaySnapshot(gamepad: gamepad))
                }
            }
        }
    }
    
    // MARK: - 构建按钮映射
    static func buildMapping(for controller: GCController, swapABXY:Bool)
    -> [ControllerElement : GCControllerElement]
    {
        var result: [ControllerElement : GCControllerElement] = [:]
        ControllerUtil.swapABXY = swapABXY
        
        if let pad = controller.extendedGamepad {
            // Face buttons
            if swapABXY {
                result[.a] = pad.buttonB
                result[.b] = pad.buttonA
                result[.x] = pad.buttonY
                result[.y] = pad.buttonX
            }
            else{
                result[.a] = pad.buttonA
                result[.b] = pad.buttonB
                result[.x] = pad.buttonX
                result[.y] = pad.buttonY
            }
            
            // Shoulders & triggers
            result[.leftShoulder]  = pad.leftShoulder
            result[.rightShoulder] = pad.rightShoulder
            result[.leftTrigger]   = pad.leftTrigger
            result[.rightTrigger]  = pad.rightTrigger

            // Stick buttons
            if #available(iOS 12.1, *) {
                result[.leftStickButton]  = pad.leftThumbstickButton
                result[.rightStickButton] = pad.rightThumbstickButton
            }
            
            // DPad
            result[.dpadUp]    = pad.dpad.up
            result[.dpadDown]  = pad.dpad.down
            result[.dpadLeft]  = pad.dpad.left
            result[.dpadRight] = pad.dpad.right
            
            // Sticks
            result[.leftStick] = pad.leftThumbstick
            result[.leftStickX] = pad.leftThumbstick.xAxis
            result[.leftStickY] = pad.leftThumbstick.yAxis
            result[.rightStick] = pad.rightThumbstick
            result[.rightStickX] = pad.rightThumbstick.xAxis
            result[.rightStickY] = pad.rightThumbstick.yAxis
            

            // Menu / Options / Share
            if #available(iOS 13.0, *) {
                result[.start] = pad.buttonMenu
                if let options = pad.buttonOptions { result[.select] = options }
            }
            
            if #available(iOS 14.0, tvOS 14.0, *) {
                if let home = pad.buttonHome {
                    result[.special] = home
                }
                
                if let controller = pad.controller {
                    let profile = controller.physicalInputProfile
                    if let paddle1 = profile.buttons[GCInputXboxPaddleOne] {
                        result[.paddle1] = paddle1
                    }
                    if let paddle2 = profile.buttons[GCInputXboxPaddleTwo] {
                        result[.paddle2] = paddle2
                    }
                    if let paddle3 = profile.buttons[GCInputXboxPaddleThree] {
                        result[.paddle3] = paddle3
                    }
                    if let paddle4 = profile.buttons[GCInputXboxPaddleFour] {
                        result[.paddle4] = paddle4
                    }
                    if let touchpadBtn = profile.buttons[GCInputDualShockTouchpadButton] {
                        result[.touchpadButton] = touchpadBtn
                    }
                    if #available(iOS 15.0, tvOS 15.0, *) {
                        if let share = profile.buttons[GCInputButtonShare] {
                            result[.misc] = share
                        }
                    }
                }
            }
        }
        
        if controller === primaryGCController {ControllerUtil.primaryControllerElementMap = result}
        
        return result
    }
    
    @objc static var activeStreamingGCControllers:NSMutableSet = NSMutableSet()
    
    @objc static var swapABXY:Bool = false
    
    @objc static var gamepadArrivalReported: Bool = false
    
    @objc static func string(for element: ControllerElement) -> String {
        return element.displayName
    }
    
    @objc static func position(for element: ControllerElement) -> ControllerElementPosition {
        return element.position
    }


    // MARK: - primary controller section
    
    private static var connectObserver: NSObjectProtocol?
    private static var disconnectObserver: NSObjectProtocol?
    
    @objc static weak var primaryGCController: GCController?
    static var primaryControllerElementMap: [ControllerElement : GCControllerElement]?
    private static var primaryControllerAxisStates: [ControllerElement : ComparisonResult] = [:]

    @objc static func installControllerObserversIfNeeded() {
        guard connectObserver == nil, disconnectObserver == nil else { return }
        
        if GCController.controllers().first(where: { $0.extendedGamepad != nil }) != nil {
            preparePrimaryController()
        }
        
        connectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { notification in
            guard (notification.object as? GCController)?.extendedGamepad != nil else { return }
            preparePrimaryController()
        }

        disconnectObserver = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { notification in
            preparePrimaryController()
        }
    }

    @objc static func removeControllerObservers() {
        if let connectObserver {
            NotificationCenter.default.removeObserver(connectObserver)
            self.connectObserver = nil
        }

        if let disconnectObserver {
            NotificationCenter.default.removeObserver(disconnectObserver)
            self.disconnectObserver = nil
        }
    }
    
    @objc static func disableSysGestures(_ controller: GCController?){
        if let controller = controller {
            if #available(iOS 14.0, *) {
                for element in controller.physicalInputProfile.allElements {
                    element.preferredSystemGestureState = .disabled
                }
            }
        }
    }

    private static func preparePrimaryController() {
        guard let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }) else {
            stopListeningPrimaryController()
            ControllerUtil.primaryGCController = nil
            if #available(iOS 13.0, *) {
                ControllerNavigator.stop()
            }
            return
        }
        
        guard GCController.controllers().count == 1 else { return }
        
        if let mainFrameVC = delegate as? MainFrameViewController {
            let vc = mainFrameVC.isStreaming() ? StreamFrameViewController.sharedInstance() : mainFrameVC
            GenericUtils.handleFirstGamepadConnection(in: vc) {
                setGCControllerToPrimary(controller)
                return
            }
        }
        
        setGCControllerToPrimary(controller)
    }
    
    private static func setGCControllerToPrimary(_ controller: GCController) {
        primaryGCController = controller
        _ = buildMapping(for: controller, swapABXY: false)
        disableSysGestures(controller)
        
        if #available(iOS 13.0, *) {
            if ControllerNavigator.enabled {
                ControllerNavigator.start()
                GamepadNavigationIllustrationHud.updateNavigationElements(ControllerNavigator.uiNavigationDelegate?.getNavigationElements() ?? [])
                ControllerNavigator.restoreUINavigationHighlight()
            }
        }
    }

    @objc static func stopListeningPrimaryController(stopListenToRadialMenuButton: Bool = false) {
        guard let primaryControllerButtonMap = primaryControllerElementMap else { return }
        for gcElement in primaryControllerButtonMap.values {
            if let gcButton = gcElement as? GCControllerButtonInput {
                if #available(iOS 13.0, *) {
                    if !stopListenToRadialMenuButton, gcButton === primaryControllerButtonMap[ControllerNavigator.radialMenuButton] as? GCControllerButtonInput {continue}
                }
                gcButton.pressedChangedHandler = nil
            }
            if let gcStick = gcElement as? GCControllerDirectionPad {
                gcStick.valueChangedHandler = nil
            }
            if let gcAxis = gcElement as? GCControllerAxisInput {
                gcAxis.valueChangedHandler = nil
            }
        }
        primaryControllerAxisStates.removeAll()
        primaryGCController?.extendedGamepad?.valueChangedHandler = nil
    }
    
    @objc static func listenPrimaryControllerButton(_ button: ControllerElement, ignoreSwapABXY: Bool = true, handler: @escaping (_ pressed: Bool) -> Void){
        if var elementMap = ControllerUtil.primaryControllerElementMap {
            if ignoreSwapABXY {
                elementMap[.a] = ControllerUtil.primaryGCController?.extendedGamepad?.buttonA
                elementMap[.b] = ControllerUtil.primaryGCController?.extendedGamepad?.buttonB
                elementMap[.x] = ControllerUtil.primaryGCController?.extendedGamepad?.buttonX
                elementMap[.y] = ControllerUtil.primaryGCController?.extendedGamepad?.buttonY
            }
            if let gcButton = elementMap[button] as? GCControllerButtonInput {
                gcButton.pressedChangedHandler = { _, _, pressed in
                    handler(pressed)
                }
            }
        }
    }
    
    @objc static func listenPrimaryControllerStick(_ stick: ControllerElement, handler: @escaping (_ offsetVector: CGVector) -> Void){
        if let elementMap = ControllerUtil.primaryControllerElementMap {
            if let gcStick = elementMap[stick] as? GCControllerDirectionPad {
                gcStick.valueChangedHandler = { _, xValue, yValue in
                    handler(CGVector(dx: CGFloat(xValue), dy: CGFloat(yValue)))
                }
            }
        }
    }

    @objc static func listenPrimaryControllerStickAxis(_ stickAxis: ControllerElement, threshold: CGFloat, handler: @escaping (_ state: ComparisonResult) -> Void) {
        guard threshold > 0 else { return }
        guard let elementMap = ControllerUtil.primaryControllerElementMap,
              let gcAxis = elementMap[stickAxis] as? GCControllerAxisInput else { return }

        primaryControllerAxisStates[stickAxis] = stickAxisState(for: CGFloat(gcAxis.value), threshold: threshold)
        gcAxis.valueChangedHandler = { _, value in
            let newState = stickAxisState(for: CGFloat(value), threshold: threshold)
            let previousState = primaryControllerAxisStates[stickAxis] ?? .orderedSame
            guard newState != previousState else { return }

            primaryControllerAxisStates[stickAxis] = newState
            handler(newState)
        }
    }

    private static func stickAxisState(for value: CGFloat, threshold: CGFloat) -> ComparisonResult {
        if value > threshold {
            return .orderedDescending
        }

        if value < -threshold {
            return .orderedAscending
        }

        return .orderedSame
    }

    
    

    // MARK: - input processing

    @objc static func compensated(offsetVector: CGVector, minOffset: CGFloat, circulate:Bool=false) -> CGVector{
        let vectorHypot = hypot(offsetVector.dx, offsetVector.dy)
        guard vectorHypot > 0 else {return CGVector(dx: 0, dy: 0)}
        let targetHypot = minOffset + (stickMaxOffset-minOffset)*(vectorHypot/stickMaxOffset)
        var compensatedX = targetHypot * (offsetVector.dx/vectorHypot)
        var compensatedY = targetHypot * (offsetVector.dy/vectorHypot)
        
        if circulate {
            return circulated(offsetVector: CGVector(dx: compensatedX, dy: compensatedY))
        }
        else {
            compensatedX = max(min(compensatedX, stickMaxOffset),-stickMaxOffset)
            compensatedY = max(min(compensatedY, stickMaxOffset),-stickMaxOffset)
            return CGVector(dx: compensatedX, dy: compensatedY)
        }
    }
    
    @objc static func circulated(offsetVector: CGVector) -> CGVector{
        let vectorHypot = hypot(offsetVector.dx, offsetVector.dy)
        guard vectorHypot > 0 else {return CGVector(dx: 0, dy: 0)}
        let targetHypot = min(vectorHypot, stickMaxOffset)
        let circulatedX = targetHypot*(offsetVector.dx/vectorHypot)
        let circulatedY = targetHypot*(offsetVector.dy/vectorHypot)
        return CGVector(dx: circulatedX, dy: circulatedY)
    }
}

// MARK: - realtime overlay

@available(iOS 13.0, *)
struct GamepadOverlaySnapshot: Equatable {
    var pressedButtons: Set<ControllerElement> = []
    var dpadHighlight: Int = 0
    var leftStick: CGPoint = .zero
    var rightStick: CGPoint = .zero
    var leftTrigger: CGFloat = 0
    var rightTrigger: CGFloat = 0

    static let idle = GamepadOverlaySnapshot()

    init() {}

    init(gamepad: GCExtendedGamepad) {
        var pressedButtons = Set<ControllerElement>()

        if gamepad.buttonA.isPressed { pressedButtons.insert(.a) }
        if gamepad.buttonB.isPressed { pressedButtons.insert(.b) }
        if gamepad.buttonX.isPressed { pressedButtons.insert(.x) }
        if gamepad.buttonY.isPressed { pressedButtons.insert(.y) }
        if gamepad.leftShoulder.isPressed { pressedButtons.insert(.leftShoulder) }
        if gamepad.rightShoulder.isPressed { pressedButtons.insert(.rightShoulder) }
        if gamepad.buttonMenu.isPressed { pressedButtons.insert(.start) }
        if gamepad.buttonOptions?.isPressed == true { pressedButtons.insert(.select) }
        if #available(iOS 14.0, *), gamepad.buttonHome?.isPressed == true { pressedButtons.insert(.special) }
        if gamepad.leftThumbstickButton?.isPressed == true { pressedButtons.insert(.leftStickButton) }
        if gamepad.rightThumbstickButton?.isPressed == true { pressedButtons.insert(.rightStickButton) }

        var dpadHighlight = 0
        if gamepad.dpad.up.isPressed { dpadHighlight |= DPadHighlight.up.rawValue }
        if gamepad.dpad.down.isPressed { dpadHighlight |= DPadHighlight.down.rawValue }
        if gamepad.dpad.left.isPressed { dpadHighlight |= DPadHighlight.left.rawValue }
        if gamepad.dpad.right.isPressed { dpadHighlight |= DPadHighlight.right.rawValue }

        self.pressedButtons = pressedButtons
        self.dpadHighlight = dpadHighlight
        self.leftStick = CGPoint(
            x: CGFloat(max(-1, min(1, gamepad.leftThumbstick.xAxis.value))),
            y: CGFloat(max(-1, min(1, gamepad.leftThumbstick.yAxis.value)))
        )
        self.rightStick = CGPoint(
            x: CGFloat(max(-1, min(1, gamepad.rightThumbstick.xAxis.value))),
            y: CGFloat(max(-1, min(1, gamepad.rightThumbstick.yAxis.value)))
        )
        self.leftTrigger = CGFloat(max(0, min(1, gamepad.leftTrigger.value)))
        self.rightTrigger = CGFloat(max(0, min(1, gamepad.rightTrigger.value)))
    }
}

@available(iOS 13.0, *)
@objc(GamepadOverlayStateCenter)
final class GamepadOverlayStateCenter: NSObject, ObservableObject {
    static let shared = GamepadOverlayStateCenter()

    @Published private(set) var snapshot: GamepadOverlaySnapshot = .idle

    func publish(snapshot: GamepadOverlaySnapshot) {
        DispatchQueue.main.async {
            self.snapshot = snapshot
        }
    }

    @objc static func clearSharedState() {
        shared.publish(snapshot: .idle)
    }
}
