//
//  FrameInterpolator.swift
//  VoidLink
//
//  Created by True砖家 on 2026/8/6.
//  Copyright © 2026 True砖家 @ Bilibili. All rights reserved.
//

import AVFoundation
import CoreVideo
import ObjectiveC.runtime
import VideoToolbox

@objcMembers
final class FrameInterpolator: NSObject {
    typealias Completion = (NSArray) -> Void

    private struct PendingFrame {
        let frame: Frame
        let completion: Completion
    }

    private let queue = DispatchQueue(label: "com.voidlink.FrameInterpolator", qos: .userInteractive)
    private var processor: AnyObject?
    private var pixelBufferPool: CVPixelBufferPool?
    private var formatDescription: CMVideoFormatDescription?
    private var previousFrame: Frame?
    private var pendingFrames: [PendingFrame] = []
    private var isProcessing = false
    private var resetRequested = false
    private var width = 0
    private var height = 0
    private var slowUntil = CFTimeInterval(0)
    private var completedProcessingCount = 0
    private var consecutiveSlowFrames = 0
    private var loggedEvents = Set<String>()
    private var overlayGeneration = 0

    var isEnabled = false {
        didSet {
            if !isEnabled {
                reset()
            }
        }
    }

    @objc static let deviceSupportsInterpolation: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 26.0, tvOS 26.0, *) {
            VTLowLatencyFrameInterpolationConfiguration.printLimits()
            return VTLowLatencyFrameInterpolationConfiguration.isSupported
        }
        return false
        #endif
    }()
    
    static var dimensionLimitsAreKnown: Bool = {
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 26.0, tvOS 26.0, *) {
            let limits = VTLowLatencyFrameInterpolationConfiguration
                .runtimeDimensionLimits(spatialScaleFactor: 1)
            guard
                let maximumDimension = limits.maximumDimension,
                let maximumPixelCount = limits.maximumPixelCount,
                maximumDimension > 0,
                maximumPixelCount > 0
            else {return false}
            return true
        }
        else {
            return false
        }
        #endif
    }()

    static func interpolatableDimensionsBy(_ dimensions: CMVideoDimensions) -> CMVideoDimensions {
        guard deviceSupportsInterpolation else {
            return CMVideoDimensions(width: 0, height: 0)
        }

#if targetEnvironment(simulator)
        return CMVideoDimensions(width: 0, height: 0)
#else
        guard #available(iOS 26.0, tvOS 26.0, *) else {
            return CMVideoDimensions(width: 0, height: 0)
        }
        
        let limits = VTLowLatencyFrameInterpolationConfiguration
            .runtimeDimensionLimits(spatialScaleFactor: 1)
        guard
            let maximumDimension = limits.maximumDimension,
            let maximumPixelCount = limits.maximumPixelCount,
            maximumDimension > 0,
            maximumPixelCount > 0
        else {
            return CMVideoDimensions(width: 0, height: 0)
        }

        return constrainedDimensions(
            dimensions,
            maximumDimension: maximumDimension,
            maximumPixelCount: maximumPixelCount
        )
        #endif
    }

    static func interpolatableDimensionsBy1080p(_ dimensions: CMVideoDimensions) -> CMVideoDimensions {
        guard deviceSupportsInterpolation else {
            return CMVideoDimensions(width: 0, height: 0)
        }

        return constrainedDimensions(
            dimensions,
            maximumDimension: 1920,
            maximumPixelCount: 1920 * 1080
        )
    }
    
    static func interpolatableDimensionsBy720p(_ dimensions: CMVideoDimensions) -> CMVideoDimensions {
        guard deviceSupportsInterpolation else {
            return CMVideoDimensions(width: 0, height: 0)
        }

        return constrainedDimensions(
            dimensions,
            maximumDimension: 1280,
            maximumPixelCount: 1280 * 720
        )
    }

    @objc(sourcePixelBufferAttributesForDimensions:)
    static func sourcePixelBufferAttributes(for dimensions: CMVideoDimensions) -> NSDictionary? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard
            #available(iOS 26.0, tvOS 26.0, *),
            dimensions.width > 0,
            dimensions.height > 0,
            VTLowLatencyFrameInterpolationConfiguration.isSupported,
            let configuration = VTLowLatencyFrameInterpolationConfiguration(
                frameWidth: Int(dimensions.width),
                frameHeight: Int(dimensions.height),
                numberOfInterpolatedFrames: 1
            )
        else {
            return nil
        }

        return configuration.sourcePixelBufferAttributes as NSDictionary
        #endif
    }

    private static func constrainedDimensions(
        _ dimensions: CMVideoDimensions,
        maximumDimension: Int,
        maximumPixelCount: Int
    ) -> CMVideoDimensions {
        guard
            dimensions.width > 0,
            dimensions.height > 0,
            maximumDimension > 0,
            maximumPixelCount > 0
        else {
            return CMVideoDimensions(width: 0, height: 0)
        }

        let width = Int(dimensions.width)
        let height = Int(dimensions.height)
        let (sourcePixelCount, pixelCountOverflow) = width.multipliedReportingOverflow(by: height)
        let fullHDWidth = 1920
        let fullHDHeight = 1080
        let fullHDPixelCount = fullHDWidth * fullHDHeight
        let isSixteenByNine = width * 9 == height * 16
        if !pixelCountOverflow,
           isSixteenByNine,
           sourcePixelCount > fullHDPixelCount,
           maximumDimension >= fullHDWidth,
           maximumPixelCount >= fullHDPixelCount {
            return CMVideoDimensions(width: Int32(fullHDWidth), height: Int32(fullHDHeight))
        }

        if !pixelCountOverflow,
           max(width, height) <= maximumDimension,
           sourcePixelCount <= maximumPixelCount {
            return dimensions
        }
        
        let sourceWidth = Double(width)
        let sourceHeight = Double(height)
        let dimensionScale = Double(maximumDimension) / max(sourceWidth, sourceHeight)
        let pixelCountScale = sqrt(Double(maximumPixelCount) / (sourceWidth * sourceHeight))
        let scale = min(dimensionScale, pixelCountScale)
        
        let scaledWidth = Int((sourceWidth * scale).rounded(.down)) & ~(31)
        let scaledHeight = Int((sourceHeight * scale).rounded(.down)) & ~(31)
        guard
            scaledWidth > 0,
            scaledHeight > 0,
            scaledWidth <= Int(Int32.max),
            scaledHeight <= Int(Int32.max)
        else {
            return CMVideoDimensions(width: 0, height: 0)
        }

        return CMVideoDimensions(width: Int32(scaledWidth), height: Int32(scaledHeight))
    }

    var isAvailable: Bool {
        isEnabled && Self.deviceSupportsInterpolation
    }

    func reset() {
        queue.async {
            self.requestResetLocked()
        }
    }

    func processFrame(_ frame: Frame, completion: @escaping Completion) {
        queue.async { [weak self] in
            guard let self else {
                completion([frame])
                return
            }

            guard !self.resetRequested else {
                completion([frame])
                return
            }

            self.pendingFrames.append(PendingFrame(frame: frame, completion: completion))
            self.drainPendingFrames()
        }
    }

    private func drainPendingFrames() {
        guard !isProcessing, !pendingFrames.isEmpty else {
            return
        }

        let pendingFrame = pendingFrames.removeFirst()
        let frame = pendingFrame.frame
        let completion = pendingFrame.completion
        guard isAvailable, CACurrentMediaTime() >= slowUntil else {
            if isEnabled && !Self.deviceSupportsInterpolation {
                logOnce("unavailable", "disabled: VT low-latency frame interpolation is unsupported on this OS/device")
            }
            previousFrame = frame
            completion([frame])
            drainPendingFrames()
            return
        }

        if frame.frameType == FRAME_TYPE_IDR {
            resetLocked(keepPendingFrames: true)
            previousFrame = frame
            completion([frame])
            drainPendingFrames()
            return
        }

        guard let currentPixelBuffer = frame.imageBuffer else {
            logOnce("missing-image-buffer", "input Frame has no CVPixelBuffer")
            previousFrame = frame
            completion([frame])
            drainPendingFrames()
            return
        }

        // renderFrame() rewrites the sample buffer's output PTS for local display pacing.
        // Frame.pts90 retains the original upstream PTS required for interpolation.
        let currentPTS = frame.pts90
        guard CMTIME_IS_VALID(currentPTS) else {
            logOnce("invalid-pts", "input frame has an invalid PTS")
            previousFrame = frame
            completion([frame])
            drainPendingFrames()
            return
        }

        guard prepareSessionIfNeeded(pixelBuffer: currentPixelBuffer) else {
            previousFrame = frame
            completion([frame])
            drainPendingFrames()
            return
        }

        guard let previousFrame, let previousPixelBuffer = previousFrame.imageBuffer else {
            previousFrame = frame
            completion([frame])
            drainPendingFrames()
            return
        }

        let previousPTS = previousFrame.pts90
        guard CMTIME_IS_VALID(previousPTS), CMTimeCompare(currentPTS, previousPTS) > 0 else {
            logOnce(
                "non-monotonic-pts",
                "upstream PTS is not increasing: previous \(CMTimeGetSeconds(previousPTS)), current \(CMTimeGetSeconds(currentPTS))"
            )
            self.previousFrame = frame
            completion([frame])
            drainPendingFrames()
            return
        }
        let sourceFrameInterval = CMTimeGetSeconds(CMTimeSubtract(currentPTS, previousPTS))

        #if targetEnvironment(simulator)
        self.previousFrame = frame
        completion([frame])
        drainPendingFrames()
        return
        #else
        guard #available(iOS 26.0, tvOS 26.0, *) else {
            self.previousFrame = frame
            completion([frame])
            drainPendingFrames()
            return
        }

        guard
            let processor = processor as? VTFrameProcessor,
            let sourceProcessorFrame = VTFrameProcessorFrame(buffer: currentPixelBuffer, presentationTimeStamp: currentPTS),
            let previousProcessorFrame = VTFrameProcessorFrame(buffer: previousPixelBuffer, presentationTimeStamp: previousPTS),
            let destinationPixelBuffer = makeDestinationPixelBuffer(),
            let destinationProcessorFrame = VTFrameProcessorFrame(
                buffer: destinationPixelBuffer,
                presentationTimeStamp: midpointTime(previousPTS, currentPTS)
            ),
            let parameters = VTLowLatencyFrameInterpolationParameters(
                sourceFrame: sourceProcessorFrame,
                previousFrame: previousProcessorFrame,
                interpolationPhase: [0.5],
                destinationFrames: [destinationProcessorFrame]
            )
        else {
            logOnce(
                "parameters-failed",
                "could not create interpolation parameters; input pixel format is \(pixelFormatName(CVPixelBufferGetPixelFormatType(currentPixelBuffer)))"
            )
            self.previousFrame = frame
            completion([frame])
            drainPendingFrames()
            return
        }

        isProcessing = true
        let startedAt = CACurrentMediaTime()
        processor.process(parameters: parameters) { [self] _, error in
            self.queue.async {
                self.isProcessing = false

                if self.resetRequested {
                    self.resetLocked()
                    completion([frame])
                    return
                }

                self.previousFrame = frame

                let elapsed = CACurrentMediaTime() - startedAt
                guard
                    error == nil,
                    let interpolatedFrame = self.makeInterpolatedFrame(
                        from: frame,
                        imageBuffer: destinationPixelBuffer,
                        presentationTimeStamp: destinationProcessorFrame.presentationTimeStamp
                    )
                else {
                    if let error {
                        self.logOnce("process-error", error: error)
                    } else {
                        self.logOnce(
                            "sample-buffer-failed",
                            "processing completed but the interpolated CMSampleBuffer could not be created",
                            overlayText: "Interpolation failed for an unknown reason.".localized
                        )
                    }
                    completion([frame])
                    self.drainPendingFrames()
                    return
                }

                self.logOnce(
                    "first-interpolated-frame",
                    "produced the first interpolated frame",
                    overlayText: "Interpolator started.".localized
                )
                self.completedProcessingCount += 1
                if sourceFrameInterval.isFinite, sourceFrameInterval > 0, elapsed >= sourceFrameInterval {
                    self.consecutiveSlowFrames += 1
                } else {
                    self.consecutiveSlowFrames = 0
                }
                if self.completedProcessingCount >= 10, self.consecutiveSlowFrames >= 3 {
                    self.slowUntil = CACurrentMediaTime() + 1.0
                    self.consecutiveSlowFrames = 0
                    self.logOnce(
                        "sustained-overrun",
                        "processing repeatedly exceeded the source-frame interval; temporarily falling back to original frames",
                        overlayText: "Interpolation overhead is too high. Falling back to normal mode.".localized
                    )
                }

                // NSLog("[FrameInterpolator] interpolated frame in %.2f ms",)
                completion([interpolatedFrame, frame])
                self.drainPendingFrames()
            }
        }
        #endif
    }

    private func prepareSessionIfNeeded(pixelBuffer: CVPixelBuffer) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        if processor != nil, self.width == width, self.height == height {
            return true
        }

        resetLocked(keepPendingFrames: true)

        guard #available(iOS 26.0, tvOS 26.0, *) else {
            return false
        }

        guard
            VTLowLatencyFrameInterpolationConfiguration.isSupported,
            let configuration = VTLowLatencyFrameInterpolationConfiguration(
                frameWidth: width,
                frameHeight: height,
                numberOfInterpolatedFrames: 1
            )
        else {
            logOnce("configuration-failed", "could not create a configuration for \(width)x\(height)")
            return false
        }

        let inputPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        var extendedLeft = 0
        var extendedRight = 0
        var extendedTop = 0
        var extendedBottom = 0
        CVPixelBufferGetExtendedPixels(
            pixelBuffer,
            &extendedLeft,
            &extendedRight,
            &extendedTop,
            &extendedBottom
        )
        logOnce(
            "input-layout-\(width)x\(height)",
            "input pixel buffer layout for \(width)x\(height): " +
            "extended left=\(extendedLeft), right=\(extendedRight), " +
            "top=\(extendedTop), bottom=\(extendedBottom)"
        )
        let runtimeLimits = VTLowLatencyFrameInterpolationConfiguration
            .runtimeDimensionLimits(spatialScaleFactor: 1)
        logOnce(
            "runtime-limits-\(width)x\(height)",
            "runtime limits for spatial scale 1: minimum=\(String(describing: runtimeLimits.minimumDimensions)), " +
            "legacyMaximum=\(String(describing: runtimeLimits.maximumDimensions)), " +
            "maximumDimension=\(String(describing: runtimeLimits.maximumDimension)), " +
            "maximumPixelCount=\(String(describing: runtimeLimits.maximumPixelCount))"
        )
        logOnce(
            "source-attributes-\(width)x\(height)",
            "source pixel buffer attributes for \(width)x\(height): \(configuration.sourcePixelBufferAttributes)"
        )
        logOnce(
            "destination-attributes-\(width)x\(height)",
            "destination pixel buffer attributes for \(width)x\(height): \(configuration.destinationPixelBufferAttributes)"
        )
        if !configuration.supportedPixelFormats.contains(inputPixelFormat) {
            let supportedFormats = configuration.supportedPixelFormats
                .map(pixelFormatName)
                .joined(separator: ", ")
            logOnce(
                "unsupported-pixel-format-\(inputPixelFormat)",
                "input pixel format \(pixelFormatName(inputPixelFormat)) is unsupported; supported formats: \(supportedFormats)"
            )
            return false
        }

        let processor = VTFrameProcessor()
        do {
            try processor.startSession(configuration: configuration)
        } catch {
            logOnce("session-error-\((error as NSError).code)", "failed to start session: \(error)")
            return false
        }

        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            nil,
            configuration.destinationPixelBufferAttributes as CFDictionary,
            &pool
        )
        guard status == kCVReturnSuccess, let pool else {
            processor.endSession()
            logOnce("pool-error-\(status)", "failed to create destination pixel buffer pool: \(status)")
            return false
        }

        self.width = width
        self.height = height
        self.processor = processor
        self.pixelBufferPool = pool
        logOnce(
            "session-started-\(width)x\(height)",
            "session started for \(width)x\(height), input pixel format \(pixelFormatName(inputPixelFormat))"
        )
        return true
        #endif
    }

    private func makeDestinationPixelBuffer() -> CVPixelBuffer? {
        guard let pixelBufferPool else {
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &pixelBuffer)
        return status == kCVReturnSuccess ? pixelBuffer : nil
    }

    private func makeInterpolatedFrame(
        from sourceFrame: Frame,
        imageBuffer: CVPixelBuffer,
        presentationTimeStamp: CMTime
    ) -> Frame? {
        if formatDescription == nil || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: imageBuffer) {
            var newFormatDescription: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault,
                imageBuffer: imageBuffer,
                formatDescriptionOut: &newFormatDescription
            )
            guard status == noErr else {
                return nil
            }
            formatDescription = newFormatDescription
        }

        let duration = sourceFrame.sampleBuffer.map { CMSampleBufferGetDuration($0) } ?? .invalid
        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: presentationTimeStamp,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: imageBuffer,
            formatDescription: formatDescription!,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            return nil
        }

        let retainedSampleBuffer = Unmanaged.passRetained(sampleBuffer).takeUnretainedValue()
        let frame = Frame(
            sampleBuffer: retainedSampleBuffer,
            frameNumber: sourceFrame.frameNumber,
            frameType: FRAME_TYPE_PFRAME
        )
        frame?.isInterpolated = true
        return frame
    }

    private func midpointTime(_ first: CMTime, _ second: CMTime) -> CMTime {
        CMTimeAdd(first, CMTimeMultiplyByFloat64(CMTimeSubtract(second, first), multiplier: 0.5))
    }

    private func logOnce(_ event: String, _ message: String, overlayText: String? = nil) {
        guard loggedEvents.insert(event).inserted || event == "sustained-overrun" else {
            return
        }
        if let overlayText {
            showTransientHUDText(overlayText)
            NSLog("[FrameInterpolator] %@", message)
        }
    }

    private func logOnce(_ event: String, error: Error) {
        let nsError = error as NSError
        logOnce(
            event,
            "processing failed: \(error)",
            overlayText: "\("Interpolator error:".localized) \(nsError.localizedDescription)"
        )
    }

    private func showTransientHUDText(_ text: String) {
        overlayGeneration &+= 1

        let generation = overlayGeneration

        DispatchQueue.main.async {
            guard let streamFrameVC = StreamFrameViewController.sharedInstance() else {
                return
            }

            streamFrameVC.updateTransientHUDText(text)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self, weak streamFrameVC] in
                guard let self, let streamFrameVC else {
                    return
                }

                self.queue.async {
                    guard self.overlayGeneration == generation else {
                        return
                    }
                    DispatchQueue.main.async {
                        streamFrameVC.updateTransientHUDText(nil)
                    }
                }
            }
        }
    }

    private func pixelFormatName(_ pixelFormat: OSType) -> String {
        let bytes: [UInt8] = [
            UInt8((pixelFormat >> 24) & 0xff),
            UInt8((pixelFormat >> 16) & 0xff),
            UInt8((pixelFormat >> 8) & 0xff),
            UInt8(pixelFormat & 0xff),
        ]
        let fourCC = String(bytes: bytes, encoding: .ascii) ?? "????"
        return "\(fourCC) (\(pixelFormat))"
    }

    private func requestResetLocked() {
        pendingFrames.removeAll()
        guard !isProcessing else {
            resetRequested = true
            return
        }

        resetLocked()
    }

    private func resetLocked(keepPendingFrames: Bool = false) {
        #if !targetEnvironment(simulator)
        if #available(iOS 26.0, tvOS 26.0, *),
           let processor = processor as? VTFrameProcessor {
            processor.endSession()
        }
        #endif

        processor = nil
        pixelBufferPool = nil
        formatDescription = nil
        previousFrame = nil
        isProcessing = false
        resetRequested = false
        width = 0
        height = 0
        slowUntil = 0
        completedProcessingCount = 0
        consecutiveSlowFrames = 0
        if !keepPendingFrames {
            pendingFrames.removeAll()
        }
    }
}

#if !targetEnvironment(simulator)
@available(iOS 26.0, tvOS 26.0, *)
extension VTLowLatencyFrameInterpolationConfiguration {
    struct RuntimeDimensionLimits {
        let minimumDimensions: CMVideoDimensions?
        let maximumDimensions: CMVideoDimensions?
        let maximumDimension: Int?
        let maximumPixelCount: Int?

        func supports(width: Int, height: Int) -> Bool {
            guard width > 0, height > 0 else {
                return false
            }

            if let minimumDimensions,
               (width < Int(minimumDimensions.width) || height < Int(minimumDimensions.height)) {
                return false
            }

            if let maximumDimensions,
               (width > Int(maximumDimensions.width) || height > Int(maximumDimensions.height)) {
                return false
            }

            if let maximumDimension,
               (width > maximumDimension || height > maximumDimension) {
                return false
            }

            if let maximumPixelCount {
                let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
                if overflow || pixelCount > maximumPixelCount {
                    return false
                }
            }

            return maximumDimensions != nil || maximumDimension != nil || maximumPixelCount != nil
        }
    }

    static func runtimeDimensionLimits(spatialScaleFactor: Int = 1) -> RuntimeDimensionLimits {
        RuntimeDimensionLimits(
            minimumDimensions: minimumDimensions,
            maximumDimensions: maximumDimensions,
            maximumDimension: callRuntimeIntegerClassMethod(
                "maximumDimensionForSpatialScaleFactor:",
                argument: spatialScaleFactor
            ),
            maximumPixelCount: callRuntimeIntegerClassMethod(
                "maximumPixelCountForSpatialScaleFactor:",
                argument: spatialScaleFactor
            )
        )
    }

    private static func callRuntimeIntegerClassMethod(
        _ selectorName: String,
        argument: Int
    ) -> Int? {
        let configurationClass: AnyClass = self
        let selector = NSSelectorFromString(selectorName)
        guard let method = class_getClassMethod(configurationClass, selector) else {
            return nil
        }

        typealias Function = @convention(c) (AnyClass, Selector, Int) -> Int
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        let result = function(configurationClass, selector, argument)
        return result > 0 ? result : nil
    }
    
    static func printLimits() {
        let limits =
            VTLowLatencyFrameInterpolationConfiguration
                .runtimeDimensionLimits(spatialScaleFactor: 1)

        print("minimum:", limits.minimumDimensions as Any)
        print("legacy maximum:", limits.maximumDimensions as Any)
        print("maximum dimension:", limits.maximumDimension as Any)
        print("maximum pixel count:", limits.maximumPixelCount as Any)

        let supported = limits.supports(width: 1920, height: 1080)
        print("1920x1080 supported:", supported)
    }
}
#endif
