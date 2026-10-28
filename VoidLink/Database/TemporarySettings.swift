//
//  TemporarySettings.m -> TemporarySettings.swift
//  Moonlight
//
//  Created by Cameron Gutman on 12/1/15.
//  Copyright © 2015 Moonlight Stream. All rights reserved.
//
//  Modified by True砖家 since 2024.6.1
//  Copyright © 2024 True砖家 @ Bilibili. All rights reserved.
//

import Foundation
import CoreGraphics

// Touchpad settings stay in UserDefaults to avoid changing the database schema.
let CursorInertiaDefaultsKey = "touchpadCursorInertia"
let CursorInertiaDecelerationDefaultsKey = "touchpadCursorInertiaDeceleration"
let CursorInertiaDecelerationDefault: Float = 5.0
let PortraitStreamOffsetDefaultsKey = "portraitStreamVerticalOffset"

// Keep raw values stable for existing persisted codec preferences.
@objc enum TemporarySettingsCodecPreference: Int {
    case auto = 0
    case h264 = 1
    case hevc = 2
    case av1 = 3
}

@objcMembers
class TemporarySettings: NSObject {
    // MARK: Snapshot

    var parent: Settings!
    var uniqueId: String!

    // MARK: Video

    var resolutionSelected: NSNumber!
    var width: NSNumber!
    var height: NSNumber!
    var framerate: NSNumber!
    var bitrate: NSNumber!
    var preferredCodec: Int32 = 0
    var enableHdr: Bool = false
    var enableYUV444: Bool = false
    var framePacingMode: NSNumber!
    var interpolationMaximumDimension: NSNumber!
    var interpolationMaximumPixelCount: NSNumber!
    var streamDimensionScale: NSNumber!
    var frameQueueSize: NSNumber!
    var enableFrameTimebase: Bool = false
    var asyncFrameDequeue: Bool = false
    var enablePIP: Bool = false

    // MARK: Touch Control

    var touchMode: NSNumber!
    var mousePointerVelocityFactor: NSNumber!
    var zoomViewportPointerVelocityFactor: NSNumber!
    var trackpadGestureSensitivity: NSNumber!
    var pointerVelocityModeDivider: NSNumber!
    var touchPointerVelocityFactor: NSNumber!
    var passthroughGestures: Bool = false
    var trackpadGestureMode: NSNumber!
    var ctrlDownForPinch: Bool = false
    var scrollSensitivity: NSNumber!
    var pinchSensitivity: NSNumber!
    var floatingKeyboardButton: Bool = false
    var onscreenControls: NSNumber!
    var buttonVisualFeedback: Bool = false
    var touchPointTracking: Bool = false
    var touchMoveEventInterval: NSNumber!
    // Deprecated; retained for Objective-C callers without loading the persisted value.
    var asyncNativeTouchPriority: NSNumber!

    // MARK: Controller

    var enableControllerNavigation: Bool = false
    var streamingRadialMenuDelay: NSNumber!
    var controllerMousePointerVelocity: NSNumber!
    var controllerMouseExpo: NSNumber!
    var swapABXYButtons: Bool = false
    var hapticEngine: NSNumber!
    var emulatedControllerType: NSNumber!
    var gyroMode: NSNumber!
    var gyroSensitivity: NSNumber!
    var controllerMouseLeftButton: NSNumber!
    var controllerMouseRightButton: NSNumber!
    var controllerMouseStick: NSNumber!
    var localRadialMenuButton: NSNumber!
    var streamingRadialMenuButton: NSNumber!

    // MARK: Motion Control

    var gyroBiasX: NSNumber!
    var gyroBiasY: NSNumber!
    var gyroBiasZ: NSNumber!
    var controllerGyroBiasX: NSNumber!
    var controllerGyroBiasY: NSNumber!
    var controllerGyroBiasZ: NSNumber!

    // MARK: Drawing Toolkit

    var pencilTickMode: NSNumber!
    var pencilTickIntervalUs: NSNumber!
    var pencilTipOffsetX: NSNumber!
    var pencilTipOffsetY: NSNumber!

    // MARK: Gestures

    var keyboardToggleFingers: NSNumber!
    var slideToSettingsScreenEdge: NSNumber!
    var slideToSettingsDistance: NSNumber!
    var edgeSlidingSensitivity: NSNumber!
    var oscLayoutToolFingers: NSNumber!

    // MARK: Peripherals

    var externalDisplayMode: NSNumber!
    var localMousePointerMode: NSNumber!
    var reverseMouseWheelDirection: Bool = false
    var btMouseSupport: Bool = false
    var globeAsEscape: Bool = false

    // MARK: Audio

    var playAudioOnPC: Bool = false
    var localVolume: NSNumber!
    var redirectMic: Bool = false
    var useBuiltinMic: Bool = false
    var micVolume: NSNumber!
    var duckOtherApps: Bool = false
    var muteInBackground: Bool = false
    var audioConfig: NSNumber!
    var audioBufferLimitMs: NSNumber!

    // MARK: Others

    var statsOverlayLevel: NSNumber!
    var statsOverlayEnabled: Bool = false
    var unlockDisplayOrientation: Bool = false
    var portraitStreamOffset: NSNumber!
    var backgroundSessionTimer: NSNumber!
    var appTheme: NSNumber!
    var optimizeGames: Bool = false
    var multiController: Bool = false
    var showKeyboardToolbar: Bool = false
    var softKeyboardHeight: CGFloat = 0
    var liftStreamViewForKeyboard: Bool = false
    var rememberFoldState: Bool = false
    var settingsMenuOffset: NSNumber!
    var settingsMenuMode: NSNumber!
    var settingsMenuWidth: NSNumber!

    // MARK: Experimental

    var cursorInertia: Bool = false
    var cursorInertiaDeceleration: NSNumber!
    var relativeTouchSlideThreshold: NSNumber!
    var singleTapSensitivity: NSNumber!
    var delayLeftClick: Bool = false
    var leftClickDelayMs: NSNumber!
    var renderingBackend: NSNumber!
    var fullColorRange: Bool = false
    var enableGraphs: Bool = false
    var graphOpacity: NSNumber!
    var sendDummyEvent: Bool = false
    var sdrPerformanceWorkaround: Bool = false

    @objc(initFromSettings:)
    init(from settings: Settings) {
        super.init()
#if !os(tvOS)
        let defaults = UserDefaults.standard
#endif

        // MARK: Snapshot

        parent = settings
        uniqueId = settings.uniqueId

        // MARK: Video

        resolutionSelected = settings.resolutionSelected
        width = settings.width
        height = settings.height
        framerate = settings.framerate
        bitrate = settings.bitrate
        preferredCodec = settings.preferredCodec
        enableHdr = settings.enableHdr
        enableYUV444 = settings.enableYUV444
        framePacingMode = settings.framePacingMode
        interpolationMaximumDimension = settings.interpolationMaximumDimension
        interpolationMaximumPixelCount = settings.interpolationMaximumPixelCount
        streamDimensionScale = settings.streamDimensionScale
        frameQueueSize = settings.frameQueueSize
        asyncFrameDequeue = settings.asyncFrameDequeue
#if !os(tvOS)
        enablePIP = settings.enablePIP

        // MARK: Touch Control

        touchMode = settings.touchMode
        mousePointerVelocityFactor = settings.mousePointerVelocityFactor
        zoomViewportPointerVelocityFactor = settings.zoomViewportPointerVelocityFactor ?? 1
        trackpadGestureSensitivity = settings.trackpadGestureSensitivity ?? 1
        pointerVelocityModeDivider = settings.pointerVelocityModeDivider
        touchPointerVelocityFactor = settings.touchPointerVelocityFactor
        passthroughGestures = settings.passthroughGestures
        trackpadGestureMode = settings.trackpadGestureMode
        ctrlDownForPinch = settings.ctrlDownForPinch
        scrollSensitivity = settings.scrollSensitivity
        pinchSensitivity = settings.pinchSensitivity
        floatingKeyboardButton = settings.floatingKeyboardButton
        onscreenControls = settings.onscreenControls
        buttonVisualFeedback = settings.buttonVisualFeedback
        touchPointTracking = settings.touchPointTracking
        touchMoveEventInterval = settings.touchMoveEventInterval
#endif

        // MARK: Controller

        enableControllerNavigation = settings.enableControllerNavigation
        streamingRadialMenuDelay = settings.streamingRadialMenuDelay
        controllerMousePointerVelocity = settings.controllerMousePointerVelocity
        controllerMouseExpo = settings.controllerMouseExpo
        swapABXYButtons = settings.swapABXYButtons
        hapticEngine = settings.hapticEngine
        emulatedControllerType = settings.emulatedControllerType
        gyroMode = settings.gyroMode
        gyroSensitivity = settings.gyroSensitivity
        controllerMouseLeftButton = settings.controllerMouseLeftButton
        controllerMouseRightButton = settings.controllerMouseRightButton
        controllerMouseStick = settings.controllerMouseStick
        localRadialMenuButton = settings.localRadialMenuButton
        streamingRadialMenuButton = settings.streamingRadialMenuButton

        // MARK: Motion Control

        gyroBiasX = settings.gyroBiasX
        gyroBiasY = settings.gyroBiasY
        gyroBiasZ = settings.gyroBiasZ
        controllerGyroBiasX = settings.controllerGyroBiasX
        controllerGyroBiasY = settings.controllerGyroBiasY
        controllerGyroBiasZ = settings.controllerGyroBiasZ

        // MARK: Drawing Toolkit

#if !os(tvOS)
        pencilTickMode = settings.pencilTickMode
        pencilTickIntervalUs = settings.pencilTickIntervalUs
        pencilTipOffsetX = settings.pencilTipOffsetX
        pencilTipOffsetY = settings.pencilTipOffsetY

        // MARK: Gestures

        keyboardToggleFingers = settings.keyboardToggleFingers
        slideToSettingsScreenEdge = settings.slideToSettingsScreenEdge
        slideToSettingsDistance = settings.slideToSettingsDistance
        edgeSlidingSensitivity = settings.edgeSlidingSensitivity
        oscLayoutToolFingers = settings.oscLayoutToolFingers

        // MARK: Peripherals

        externalDisplayMode = settings.externalDisplayMode
        localMousePointerMode = settings.localMousePointerMode
        reverseMouseWheelDirection = settings.reverseMouseWheelDirection
        btMouseSupport = settings.btMouseSupport
        globeAsEscape = settings.globeAsEscape
#endif

        // MARK: Audio

        playAudioOnPC = settings.playAudioOnPC
        localVolume = settings.localVolume
        redirectMic = settings.redirectMic
#if !os(tvOS)
        useBuiltinMic = settings.useBuiltinMic
#endif
        micVolume = settings.micVolume
        duckOtherApps = settings.duckOtherApps
        muteInBackground = settings.muteInBackground
        audioConfig = settings.audioConfig
        audioBufferLimitMs = settings.audioBufferLimitMs

        // MARK: Others

        statsOverlayLevel = settings.statsOverlayLevel
        statsOverlayEnabled = settings.statsOverlayEnabled
#if !os(tvOS)
        unlockDisplayOrientation = settings.unlockDisplayOrientation
        portraitStreamOffset = NSNumber(value: defaults.float(forKey: PortraitStreamOffsetDefaultsKey))
#endif
        backgroundSessionTimer = settings.backgroundSessionTimer
        appTheme = settings.appTheme
        optimizeGames = settings.optimizeGames
        multiController = settings.multiController
#if !os(tvOS)
        showKeyboardToolbar = settings.showKeyboardToolbar
        softKeyboardHeight = CGFloat(settings.softKeyboardHeight)
        liftStreamViewForKeyboard = settings.liftStreamViewForKeyboard
#endif
        rememberFoldState = settings.rememberFoldState
        settingsMenuOffset = settings.settingsMenuOffset
        settingsMenuMode = settings.settingsMenuMode
        settingsMenuWidth = settings.settingsMenuWidth

        // MARK: Experimental

#if !os(tvOS)
        cursorInertia = defaults.bool(forKey: CursorInertiaDefaultsKey)
        cursorInertiaDeceleration = defaults.object(forKey: CursorInertiaDecelerationDefaultsKey) as? NSNumber
            ?? NSNumber(value: CursorInertiaDecelerationDefault)
        relativeTouchSlideThreshold = settings.relativeTouchSlideThreshold
        singleTapSensitivity = settings.singleTapSensitivity
        delayLeftClick = settings.delayLeftClick
        leftClickDelayMs = settings.leftClickDelayMs
#endif
        renderingBackend = settings.renderingBackend
        fullColorRange = settings.fullColorRange
        enableGraphs = settings.enableGraphs
        graphOpacity = settings.graphOpacity
        sendDummyEvent = settings.sendDummyEvent
        sdrPerformanceWorkaround = settings.sdrPerformanceWorkaround
    }
}
