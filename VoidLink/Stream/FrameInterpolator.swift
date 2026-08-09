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
final class InterpolationResolutionConfiguration: NSObject {
    let maximumDimension: Int
    let maximumPixelCount: Int
    let dimensions: CMVideoDimensions

    init(
        maximumDimension: Int,
        maximumPixelCount: Int,
        dimensions: CMVideoDimensions
    ) {
        self.maximumDimension = maximumDimension
        self.maximumPixelCount = maximumPixelCount
        self.dimensions = dimensions
    }
}

@objcMembers
final class FrameInterpolator: NSObject {
    typealias Completion = (NSArray) -> Void

    enum DimensionSelectionStrategy {
        case maximumScale
        case aspectRatioMatched
    }

    @objc enum ResolutionTier:Int {
        case system
        case p480
        case p720
        case p1080
        case disabled
    }

    private struct PendingFrame {
        let frame: Frame
        let completion: Completion
    }

    private let queue = DispatchQueue(label: "com.voidlink.FrameInterpolator", qos: .userInteractive)
    private var processor: AnyObject?
    private var pixelTransferSession: AnyObject?
    private var interpolationSourcePixelBufferPool: CVPixelBufferPool?
    private var pixelBufferPool: CVPixelBufferPool?
    private var formatDescription: CMVideoFormatDescription?
    private var previousInterpolationPixelBuffer: CVPixelBuffer?
    private var previousInterpolationPTS = CMTime.invalid
    private var pendingFrames: [PendingFrame] = []
    private var isProcessing = false
    private var isPaused = false
    private var resetRequested = false
    private var resetResolutionTierRequested = false
    private var configuredResolutionTier = ResolutionTier.system
    private var resolutionTier = ResolutionTier.system
    private var configuredMaximumDimension = 0
    private var configuredMaximumPixelCount = 0
    private var width = 0
    private var height = 0
    private var sourceWidth = 0
    private var sourceHeight = 0
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

    @objc(initWithResolutionTierRawValue:)
    convenience init(resolutionTierRawValue: Int) {
        self.init()
        let tier = ResolutionTier(rawValue: resolutionTierRawValue) ?? .system
        configuredResolutionTier = tier == .disabled ? .system : tier
        resolutionTier = configuredResolutionTier
    }

    @objc(initWithMaximumDimension:maximumPixelCount:)
    convenience init(maximumDimension: Int, maximumPixelCount: Int) {
        self.init()
        configuredMaximumDimension = max(0, maximumDimension)
        configuredMaximumPixelCount = max(0, maximumPixelCount)
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

    private static let runtimeSupportedPixelFormats: [OSType] = {
        #if targetEnvironment(simulator)
        return []
        #else
        guard
            #available(iOS 26.0, tvOS 26.0, *),
            VTLowLatencyFrameInterpolationConfiguration.isSupported,
            let configuration = VTLowLatencyFrameInterpolationConfiguration(
                frameWidth: 1280,
                frameHeight: 720,
                numberOfInterpolatedFrames: 1
            )
        else {
            return []
        }

        return configuration.supportedPixelFormats
        #endif
    }()

    private static let pixelFormatTraits: [OSType: (bitDepth: Int, range: Int, chroma: Int)] = [
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange: (8, 0, 0),
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange: (8, 1, 0),
        kCVPixelFormatType_422YpCbCr8BiPlanarVideoRange: (8, 0, 1),
        kCVPixelFormatType_422YpCbCr8BiPlanarFullRange: (8, 1, 1),
        kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange: (8, 0, 2),
        kCVPixelFormatType_444YpCbCr8BiPlanarFullRange: (8, 1, 2),
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: (10, 0, 0),
        kCVPixelFormatType_420YpCbCr10BiPlanarFullRange: (10, 1, 0),
        kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange: (10, 0, 1),
        kCVPixelFormatType_422YpCbCr10BiPlanarFullRange: (10, 1, 1),
        kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange: (10, 0, 2),
        kCVPixelFormatType_444YpCbCr10BiPlanarFullRange: (10, 1, 2),
    ]

    @objc static let hdrSupported: Bool = {
        runtimeSupportedPixelFormats.contains {
            pixelFormatTraits[$0]?.bitDepth == 10
        }
    }()

    @objc(supportedPixelFormatClosestTo:)
    static func supportedPixelFormat(closestTo nativePixelFormat: OSType) -> OSType {
        guard let firstSupportedFormat = runtimeSupportedPixelFormats.first else {
            return 0
        }
        if runtimeSupportedPixelFormats.contains(nativePixelFormat) {
            return nativePixelFormat
        }
        guard let nativeTraits = pixelFormatTraits[nativePixelFormat] else {
            return firstSupportedFormat
        }

        return runtimeSupportedPixelFormats.min { lhs, rhs in
            func distance(from format: OSType) -> Int {
                guard let traits = pixelFormatTraits[format] else {
                    return Int.max
                }
                return abs(traits.bitDepth - nativeTraits.bitDepth) * 100
                    + abs(traits.range - nativeTraits.range) * 10
                    + abs(traits.chroma - nativeTraits.chroma)
            }
            return distance(from: lhs) < distance(from: rhs)
        } ?? firstSupportedFormat
    }
    
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

    static func runtimeMaximumInterpolationDimensions() -> CMVideoDimensions {
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

        return CMVideoDimensions(
            width: Int32(maximumDimension),
            height: Int32(maximumPixelCount / maximumDimension)
        )
        #endif
    }

    static func runtimeMaximumInterpolationPixelCount() -> Int {
        #if targetEnvironment(simulator)
        return 0
        #else
        guard #available(iOS 26.0, tvOS 26.0, *) else {
            return 0
        }

        return VTLowLatencyFrameInterpolationConfiguration
            .runtimeDimensionLimits(spatialScaleFactor: 1)
            .maximumPixelCount ?? 0
        #endif
    }

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

    static func interpolatableDimensionsBy480p(_ dimensions: CMVideoDimensions) -> CMVideoDimensions {
        guard deviceSupportsInterpolation else {
            return CMVideoDimensions(width: 0, height: 0)
        }

        return constrainedDimensions(
            dimensions,
            maximumDimension: 854,
            maximumPixelCount: 854 * 480
        )
    }

    @objc(interpolatableDimensionsBy:maximumDimension:maximumPixelCount:)
    static func interpolatableDimensionsBy(
        _ dimensions: CMVideoDimensions,
        maximumDimension: Int,
        maximumPixelCount: Int
    ) -> CMVideoDimensions {
        constrainedDimensions(
            dimensions,
            maximumDimension: maximumDimension,
            maximumPixelCount: maximumPixelCount
        )
    }

    @objc(resolutionConfigurationForDimensions:level:)
    static func resolutionConfiguration(
        for dimensions: CMVideoDimensions,
        level: Float
    ) -> InterpolationResolutionConfiguration {
        let sliderLimits = interpolationSliderLimits(for: dimensions)
        let clampedLevel = min(1, max(0, Double(level)))
        let maximumDimension = Int(
            (Double(sliderLimits.minimumDimension) +
             Double(sliderLimits.maximumDimension - sliderLimits.minimumDimension) * clampedLevel)
                .rounded()
        )

        let maximumPixelCount: Int
        if clampedLevel <= 0 {
            maximumPixelCount = 854 * 480
        } else if clampedLevel >= 1 {
            maximumPixelCount = sliderLimits.maximumPixelCount
        } else {
            maximumPixelCount = min(
                Int((Double(maximumDimension * maximumDimension) / sliderLimits.aspectRatio).rounded()),
                sliderLimits.maximumPixelCount
            )
        }

        return InterpolationResolutionConfiguration(
            maximumDimension: maximumDimension,
            maximumPixelCount: maximumPixelCount,
            dimensions: constrainedDimensions(
                dimensions,
                maximumDimension: maximumDimension,
                maximumPixelCount: maximumPixelCount
            )
        )
    }

    @objc(interpolationLevelForDimensions:savedMaximumDimension:)
    static func interpolationLevel(
        for dimensions: CMVideoDimensions,
        savedMaximumDimension: Int
    ) -> Float {
        let limits = interpolationSliderLimits(for: dimensions)
        guard savedMaximumDimension > 0,
              limits.maximumDimension != limits.minimumDimension else {
            return 1
        }

        return Float(min(1, max(0,
            Double(savedMaximumDimension - limits.minimumDimension) /
            Double(limits.maximumDimension - limits.minimumDimension)
        )))
    }

    @objc(scaledStreamDimensionsWithPresetDimensions:interpolationDimensions:scale:)
    static func scaledStreamDimensions(
        presetDimensions: CMVideoDimensions,
        interpolationDimensions: CMVideoDimensions,
        scale: Float
    ) -> CMVideoDimensions {
        let clampedScale = min(1, max(0, Double(scale)))
        let width = Int(
            (Double(interpolationDimensions.width) +
             Double(presetDimensions.width - interpolationDimensions.width) * clampedScale)
                .rounded()
        )
        let height = Int(
            (Double(interpolationDimensions.height) +
             Double(presetDimensions.height - interpolationDimensions.height) * clampedScale)
                .rounded()
        )

        return videoDimensions(
            width: max(4, width & ~3),
            height: max(4, height & ~3)
        )
    }

    private static func interpolationSliderLimits(
        for dimensions: CMVideoDimensions
    ) -> (
        minimumDimension: Int,
        maximumDimension: Int,
        maximumPixelCount: Int,
        aspectRatio: Double
    ) {
        let systemDimensions = interpolatableDimensionsBy(dimensions)
        let systemDimensionsAreValid = systemDimensions.width > 0 && systemDimensions.height > 0
        let maximumDimension = systemDimensionsAreValid
            ? max(Int(systemDimensions.width), Int(systemDimensions.height))
            : 1280
        let maximumPixelCount = systemDimensionsAreValid
            ? Int(systemDimensions.width) * Int(systemDimensions.height)
            : 1280 * 720
        let aspectRatio = Double(maximumDimension * maximumDimension) /
            Double(maximumPixelCount)
        let minimumDimension = min(
            Int((Double(854 * 480) * aspectRatio).squareRoot().rounded()),
            maximumDimension
        )

        return (
            minimumDimension,
            maximumDimension,
            maximumPixelCount,
            aspectRatio
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
        maximumPixelCount: Int,
        strategy: DimensionSelectionStrategy = .aspectRatioMatched
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
        
        let constrainedDimensions: CMVideoDimensions
        switch strategy {
        case .maximumScale:
            constrainedDimensions = maximumScaleDimensions(
                width: width,
                height: height,
                maximumDimension: maximumDimension,
                maximumPixelCount: maximumPixelCount
            )
        case .aspectRatioMatched:
            constrainedDimensions = aspectRatioMatchedDimensions(
                width: width,
                height: height,
                maximumDimension: maximumDimension,
                maximumPixelCount: maximumPixelCount
            )
        }

        guard
            constrainedDimensions.width > 0,
            constrainedDimensions.height > 0
        else {
            return CMVideoDimensions(width: 0, height: 0)
        }

        return constrainedDimensions
    }

    private static func maximumScaleDimensions(
        width: Int,
        height: Int,
        maximumDimension: Int,
        maximumPixelCount: Int
    ) -> CMVideoDimensions {
        let sourceWidth = Double(width)
        let sourceHeight = Double(height)
        let dimensionScale = Double(maximumDimension) / max(sourceWidth, sourceHeight)
        let pixelCountScale = sqrt(Double(maximumPixelCount) / (sourceWidth * sourceHeight))
        let scale = min(dimensionScale, pixelCountScale)
        let interpolationAlignment = 16
        let scaledWidth = Int((sourceWidth * scale).rounded(.down)) & ~(interpolationAlignment - 1)
        let scaledHeight = Int((sourceHeight * scale).rounded(.down)) & ~(interpolationAlignment - 1)

        return videoDimensions(width: scaledWidth, height: scaledHeight)
    }

    private static func aspectRatioMatchedDimensions(
        width: Int,
        height: Int,
        maximumDimension: Int,
        maximumPixelCount: Int
    ) -> CMVideoDimensions {
        let interpolationAlignment = 16
        let sourceWidth = Double(width)
        let sourceHeight = Double(height)
        let sourceAspectRatio = sourceWidth / sourceHeight
        let dimensionScale = Double(maximumDimension) / max(sourceWidth, sourceHeight)
        let pixelCountScale = sqrt(Double(maximumPixelCount) / (sourceWidth * sourceHeight))
        let idealScale = min(1, dimensionScale, pixelCountScale)
        let minimumCandidateArea = sourceWidth * idealScale * sourceHeight * idealScale * 0.9
        let maximumCandidateWidth = min(width, maximumDimension) & ~(interpolationAlignment - 1)
        let maximumCandidateHeight = min(height, maximumDimension)

        var bestWidth = 0
        var bestHeight = 0
        var bestArea = 0
        var bestAspectRatioError = Double.greatestFiniteMagnitude

        for candidateWidth in stride(
            from: interpolationAlignment,
            through: maximumCandidateWidth,
            by: interpolationAlignment
        ) {
            let exactHeight = Double(candidateWidth) / sourceAspectRatio
            let lowerHeight = Int(exactHeight.rounded(.down)) & ~(interpolationAlignment - 1)

            for candidateHeight in [lowerHeight, lowerHeight + interpolationAlignment] {
                guard
                    candidateHeight > 0,
                    candidateHeight <= maximumCandidateHeight
                else {
                    continue
                }

                let (candidateArea, areaOverflow) = candidateWidth.multipliedReportingOverflow(
                    by: candidateHeight
                )
                guard
                    !areaOverflow,
                    candidateArea <= maximumPixelCount,
                    Double(candidateArea) >= minimumCandidateArea
                else {
                    continue
                }

                let candidateAspectRatio = Double(candidateWidth) / Double(candidateHeight)
                let aspectRatioError = abs(candidateAspectRatio / sourceAspectRatio - 1)
                let hasBetterAspectRatio = aspectRatioError < bestAspectRatioError
                let hasEqualAspectRatio = abs(aspectRatioError - bestAspectRatioError) < 1e-12

                if hasBetterAspectRatio || (hasEqualAspectRatio && candidateArea > bestArea) {
                    bestWidth = candidateWidth
                    bestHeight = candidateHeight
                    bestArea = candidateArea
                    bestAspectRatioError = aspectRatioError
                }
            }
        }

        guard bestWidth > 0, bestHeight > 0 else {
            return maximumScaleDimensions(
                width: width,
                height: height,
                maximumDimension: maximumDimension,
                maximumPixelCount: maximumPixelCount
            )
        }

        return videoDimensions(width: bestWidth, height: bestHeight)
    }

    private static func videoDimensions(width: Int, height: Int) -> CMVideoDimensions {
        guard
            width > 0,
            height > 0,
            width <= Int(Int32.max),
            height <= Int(Int32.max)
        else {
            return CMVideoDimensions(width: 0, height: 0)
        }

        return CMVideoDimensions(width: Int32(width), height: Int32(height))
    }

    var isAvailable: Bool {
        isEnabled && Self.deviceSupportsInterpolation && resolutionTier != .disabled
    }

    func reset() {
        queue.async {
            self.requestResetLocked()
        }
    }

    func setPaused(_ paused: Bool) {
        queue.async {
            guard self.isPaused != paused else {
                return
            }

            self.isPaused = paused
            guard paused else {
                return
            }

            let pendingFrames = self.pendingFrames
            self.pendingFrames.removeAll()
            for pendingFrame in pendingFrames {
                pendingFrame.completion([pendingFrame.frame])
            }

            if self.isProcessing {
                self.resetRequested = true
            } else {
                self.resetLocked()
            }
        }
    }

    func processFrame(_ frame: Frame, completion: @escaping Completion) {
        queue.async { [weak self] in
            guard let self else {
                completion([frame])
                return
            }

            guard !self.isPaused, !self.resetRequested else {
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
        guard isAvailable else {
            if isEnabled && !Self.deviceSupportsInterpolation {
                logOnce("unavailable", "disabled: VT low-latency frame interpolation is unsupported on this OS/device")
            }
            previousInterpolationPixelBuffer = nil
            previousInterpolationPTS = .invalid
            completion([frame])
            drainPendingFrames()
            return
        }

        if frame.frameType == FRAME_TYPE_IDR {
            resetLocked(keepPendingFrames: true)
        }

        guard let currentPixelBuffer = frame.imageBuffer else {
            logOnce("missing-image-buffer", "input Frame has no CVPixelBuffer")
            previousInterpolationPixelBuffer = nil
            previousInterpolationPTS = .invalid
            completion([frame])
            drainPendingFrames()
            return
        }

        // renderFrame() rewrites the sample buffer's output PTS for local display pacing.
        // Frame.pts90 retains the original upstream PTS required for interpolation.
        let currentPTS = frame.pts90
        guard CMTIME_IS_VALID(currentPTS) else {
            logOnce("invalid-pts", "input frame has an invalid PTS")
            previousInterpolationPixelBuffer = nil
            previousInterpolationPTS = .invalid
            completion([frame])
            drainPendingFrames()
            return
        }

        let startedAt = CACurrentMediaTime()
        guard
            prepareSessionIfNeeded(pixelBuffer: currentPixelBuffer),
            let currentInterpolationPixelBuffer = makeInterpolationSourcePixelBuffer(
                from: currentPixelBuffer
            )
        else {
            previousInterpolationPixelBuffer = nil
            previousInterpolationPTS = .invalid
            completion([frame])
            drainPendingFrames()
            return
        }

        guard
            let previousPixelBuffer = previousInterpolationPixelBuffer,
            CMTIME_IS_VALID(previousInterpolationPTS)
        else {
            previousInterpolationPixelBuffer = currentInterpolationPixelBuffer
            previousInterpolationPTS = currentPTS
            completion([frame])
            drainPendingFrames()
            return
        }

        let previousPTS = previousInterpolationPTS
        guard CMTIME_IS_VALID(previousPTS), CMTimeCompare(currentPTS, previousPTS) > 0 else {
            logOnce(
                "non-monotonic-pts",
                "upstream PTS is not increasing: previous \(CMTimeGetSeconds(previousPTS)), current \(CMTimeGetSeconds(currentPTS))"
            )
            previousInterpolationPixelBuffer = currentInterpolationPixelBuffer
            previousInterpolationPTS = currentPTS
            completion([frame])
            drainPendingFrames()
            return
        }
        let sourceFrameInterval = CMTimeGetSeconds(CMTimeSubtract(currentPTS, previousPTS))

        #if targetEnvironment(simulator)
        previousInterpolationPixelBuffer = currentInterpolationPixelBuffer
        previousInterpolationPTS = currentPTS
        completion([frame])
        drainPendingFrames()
        return
        #else
        guard #available(iOS 26.0, tvOS 26.0, *) else {
            previousInterpolationPixelBuffer = currentInterpolationPixelBuffer
            previousInterpolationPTS = currentPTS
            completion([frame])
            drainPendingFrames()
            return
        }

        guard
            let processor = processor as? VTFrameProcessor,
            let sourceProcessorFrame = VTFrameProcessorFrame(buffer: currentInterpolationPixelBuffer, presentationTimeStamp: currentPTS),
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
                "could not create interpolation parameters; input pixel format is \(pixelFormatName(CVPixelBufferGetPixelFormatType(currentInterpolationPixelBuffer)))"
            )
            previousInterpolationPixelBuffer = currentInterpolationPixelBuffer
            previousInterpolationPTS = currentPTS
            completion([frame])
            drainPendingFrames()
            return
        }

        CVBufferPropagateAttachments(
            currentInterpolationPixelBuffer,
            destinationPixelBuffer
        )

        isProcessing = true
        processor.process(parameters: parameters) { [self] _, error in
            self.queue.async {
                self.isProcessing = false

                if self.resetRequested {
                    self.resetLocked(
                        resetResolutionTier: self.resetResolutionTierRequested
                    )
                    completion([frame])
                    return
                }

                self.previousInterpolationPixelBuffer = currentInterpolationPixelBuffer
                self.previousInterpolationPTS = currentPTS

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
                if self.completedProcessingCount >= 10, self.consecutiveSlowFrames >= 30 {
                    // self.handleSustainedOverrun() // disable degradation for now
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
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        if processor != nil,
           self.sourceWidth == sourceWidth,
           self.sourceHeight == sourceHeight {
            return true
        }

        resetLocked(keepPendingFrames: true)

        guard #available(iOS 26.0, tvOS 26.0, *) else {
            return false
        }

        let sourceDimensions = CMVideoDimensions(
            width: Int32(sourceWidth),
            height: Int32(sourceHeight)
        )
        let interpolationDimensions = interpolationDimensions(for: sourceDimensions)
        let width = Int(interpolationDimensions.width)
        let height = Int(interpolationDimensions.height)

        guard
            width > 0,
            height > 0,
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
            "input-layout-\(sourceWidth)x\(sourceHeight)",
            "input pixel buffer layout for \(sourceWidth)x\(sourceHeight): " +
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
        print("configuration.supportedPixelFormats \(configuration.supportedPixelFormats)")
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

        guard let sourcePool = makeInterpolationSourcePixelBufferPool(
            configuration: configuration,
            pixelFormat: inputPixelFormat,
            width: width,
            height: height
        ) else {
            logOnce("source-pool-error", "failed to create the interpolation source pixel buffer pool")
            return false
        }

        var transferSession: VTPixelTransferSession?
        let transferStatus = VTPixelTransferSessionCreate(
            allocator: kCFAllocatorDefault,
            pixelTransferSessionOut: &transferSession
        )
        guard transferStatus == noErr, let transferSession else {
            logOnce(
                "pixel-transfer-session-error-\(transferStatus)",
                "failed to create pixel transfer session: \(transferStatus)"
            )
            return false
        }
        VTSessionSetProperty(
            transferSession,
            key: kVTPixelTransferPropertyKey_ScalingMode,
            value: kVTScalingMode_Normal
        )
        VTSessionSetProperty(
            transferSession,
            key: kVTPixelTransferPropertyKey_RealTime,
            value: kCFBooleanTrue
        )
        VTSessionSetProperty(
            transferSession,
            key: kVTPixelTransferPropertyKey_DownsamplingMode,
            value: kVTDownsamplingMode_Average
        )

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

        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.width = width
        self.height = height
        self.processor = processor
        self.pixelTransferSession = transferSession
        self.interpolationSourcePixelBufferPool = sourcePool
        self.pixelBufferPool = pool
        logOnce(
            "session-started-\(width)x\(height)",
            "session started for \(width)x\(height) from \(sourceWidth)x\(sourceHeight), input pixel format \(pixelFormatName(inputPixelFormat))"
        )
        return true
        #endif
    }

    private func interpolationDimensions(
        for sourceDimensions: CMVideoDimensions
    ) -> CMVideoDimensions {
        switch resolutionTier {
        case .system:
            if configuredMaximumDimension > 0, configuredMaximumPixelCount > 0 {
                return Self.constrainedDimensions(
                    sourceDimensions,
                    maximumDimension: configuredMaximumDimension,
                    maximumPixelCount: configuredMaximumPixelCount
                )
            }
            let dimensions = Self.interpolatableDimensionsBy(sourceDimensions)
            if dimensions.width > 0, dimensions.height > 0 {
                return dimensions
            }
            return Self.interpolatableDimensionsBy720p(sourceDimensions)
        case .p1080:
            return Self.interpolatableDimensionsBy1080p(sourceDimensions)
        case .p720:
            return Self.interpolatableDimensionsBy720p(sourceDimensions)
        case .p480:
            return Self.interpolatableDimensionsBy480p(sourceDimensions)
        case .disabled:
            return CMVideoDimensions(width: 0, height: 0)
        }
    }

    private func handleSustainedOverrun() {
        switch resolutionTier {
        case .system:
            resolutionTier = .p720
            logOnce(
                "sustained-overrun-720p",
                "processing repeatedly exceeded the source-frame interval; reducing interpolation resolution to the 720p limit",
                overlayText: "Interpolation overhead is too high. Reducing interpolation resolution to 720p.".localized
            )
        case .p1080:
            resolutionTier = .p720
            logOnce(
                "sustained-overrun-1080p",
                "processing repeatedly exceeded the source-frame interval at the 1080p limit; reducing interpolation resolution to the 720p limit",
                overlayText: "Interpolation overhead is too high. Reducing interpolation resolution to 480p.".localized
            )
        case .p720:
            resolutionTier = .p480
            logOnce(
                "sustained-overrun-480p",
                "processing repeatedly exceeded the source-frame interval at the 720p limit; reducing interpolation resolution to the 480p limit",
                overlayText: "Interpolation overhead is too high. Reducing interpolation resolution to 480p.".localized
            )
        case .p480:
            resolutionTier = .disabled
            logOnce(
                "sustained-overrun-disabled",
                "processing repeatedly exceeded the source-frame interval at the 480p limit; falling back to original frames",
                overlayText: "Interpolation overhead is too high. Falling back to normal mode.".localized
            )
        case .disabled:
            return
        }

        resetLocked(keepPendingFrames: true)
    }

    #if !targetEnvironment(simulator)
    @available(iOS 26.0, tvOS 26.0, *)
    private func makeInterpolationSourcePixelBufferPool(
        configuration: VTLowLatencyFrameInterpolationConfiguration,
        pixelFormat: OSType,
        width: Int,
        height: Int
    ) -> CVPixelBufferPool? {
        let requestedAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var resolvedAttributes: CFDictionary?
        let resolveStatus = CVPixelBufferCreateResolvedAttributesDictionary(
            kCFAllocatorDefault,
            [requestedAttributes as CFDictionary,
             configuration.sourcePixelBufferAttributes as CFDictionary] as CFArray,
            &resolvedAttributes
        )
        guard resolveStatus == kCVReturnSuccess, let resolvedAttributes else {
            return nil
        }

        var pool: CVPixelBufferPool?
        let poolStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            nil,
            resolvedAttributes,
            &pool
        )
        return poolStatus == kCVReturnSuccess ? pool : nil
    }
    #endif

    private func makeInterpolationSourcePixelBuffer(
        from sourcePixelBuffer: CVPixelBuffer
    ) -> CVPixelBuffer? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard
            #available(iOS 16.0, tvOS 16.0, *),
            let pixelTransferSession,
            let interpolationSourcePixelBufferPool
        else {
            return nil
        }
        let transferSession = pixelTransferSession as! VTPixelTransferSession

        var destinationPixelBuffer: CVPixelBuffer?
        let createStatus = CVPixelBufferPoolCreatePixelBuffer(
            kCFAllocatorDefault,
            interpolationSourcePixelBufferPool,
            &destinationPixelBuffer
        )
        guard createStatus == kCVReturnSuccess, let destinationPixelBuffer else {
            logOnce("downsize-buffer-error-\(createStatus)", "failed to allocate downsize buffer: \(createStatus)")
            return nil
        }

        let transferStatus = VTPixelTransferSessionTransferImage(
            transferSession,
            from: sourcePixelBuffer,
            to: destinationPixelBuffer
        )
        guard transferStatus == noErr else {
            logOnce("downsize-error-\(transferStatus)", "failed to downsize frame: \(transferStatus)")
            return nil
        }
        return destinationPixelBuffer
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
        }
        NSLog("[FrameInterpolator] %@", message)
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
            resetResolutionTierRequested = true
            return
        }

        resetLocked(resetResolutionTier: true)
    }

    private func resetLocked(
        keepPendingFrames: Bool = false,
        resetResolutionTier: Bool = false
    ) {
        #if !targetEnvironment(simulator)
        if #available(iOS 26.0, tvOS 26.0, *),
           let processor = processor as? VTFrameProcessor {
            processor.endSession()
        }
        #endif

        processor = nil
        #if !targetEnvironment(simulator)
        if #available(iOS 16.0, tvOS 16.0, *),
           let pixelTransferSession {
            VTPixelTransferSessionInvalidate(pixelTransferSession as! VTPixelTransferSession)
        }
        #endif
        pixelTransferSession = nil
        interpolationSourcePixelBufferPool = nil
        pixelBufferPool = nil
        formatDescription = nil
        previousInterpolationPixelBuffer = nil
        previousInterpolationPTS = .invalid
        isProcessing = false
        resetRequested = false
        resetResolutionTierRequested = false
        width = 0
        height = 0
        sourceWidth = 0
        sourceHeight = 0
        completedProcessingCount = 0
        consecutiveSlowFrames = 0
        if resetResolutionTier {
            resolutionTier = configuredResolutionTier
        }
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
