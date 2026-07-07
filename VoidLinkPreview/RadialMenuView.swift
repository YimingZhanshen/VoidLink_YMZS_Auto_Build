//
//  RadialMenuView.swift
//  VoidLink
//
//  Created by True砖家 on 2026/6/29.
//  Copyright © 2026 True砖家 @ Bilibili. All rights reserved.
//

import SwiftUI
import Combine
import UIKit

public enum RadialMenuItem {
    case settings
    case hostView
    case gameProfiles
    case exit
}

@available(iOS 13.0, *)
struct RadialMenuSector: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImageName: String
    let item: RadialMenuItem

    init(title: String, subtitle: String, systemImageName: String, item: RadialMenuItem) {
        self.title = title
        self.subtitle = subtitle
        self.systemImageName = systemImageName
        self.item = item
    }
}

@available(iOS 13.0, *)
struct RadialMenuStyle: Equatable {
    var ringColor = Color(white: 0.86)
    var selectedRingColor = Color(red: 0.19, green: 0.72, blue: 0.96)
    var ringStrokeColor = Color.white.opacity(0.72)
    var centerFillColor = Color.white
    var iconColor = Color(white: 0.23)
    var selectedIconColor = Color(white: 0.16)
    var titleColor = Color(white: 0.24)
    var subtitleColor = Color(white: 0.48)
    var shadowColor = Color.black.opacity(0.18)
    var ringWidthRatio: CGFloat = 0.41
    var segmentGapWidth: CGFloat = 1
    var centerIconScale: CGFloat = 0.16
    var segmentIconScale: CGFloat = 0.085
}

@available(iOS 13.0, *)
final class RadialMenuSelectionState: ObservableObject {
    @Published private(set) var selectedIndex: Int?
    @Published private(set) var hasReceivedJoystickInput = false

    private var itemCount = 0

    func updateSelection(xOffset: Float, yOffset: Float) {
        updateSelection(xOffset: xOffset, yOffset: yOffset, deadZone: 0.1)
    }

    func updateSelection(xOffset: Float, yOffset: Float, deadZone: Float) {
        let nextSelectedIndex = Self.selectedIndex(
            xOffset: xOffset,
            yOffset: yOffset,
            itemCount: itemCount,
            deadZone: deadZone
        )

        guard !hasReceivedJoystickInput || nextSelectedIndex != selectedIndex else {
            return
        }

        hasReceivedJoystickInput = true
        selectedIndex = nextSelectedIndex
    }

    fileprivate func configureItemCount(_ itemCount: Int) {
        self.itemCount = max(itemCount, 0)
        if let selectedIndex, selectedIndex >= itemCount {
            self.selectedIndex = nil
        }
    }

    static func selectedIndex(xOffset: Float, yOffset: Float, itemCount: Int, deadZone: Float = 0.1) -> Int? {
        guard itemCount > 0 else { return nil }

        let x = max(min(xOffset, 1), -1)
        let y = max(min(yOffset, 1), -1)
        let distance = hypot(x, y)
        guard distance >= deadZone else {
            return nil
        }

        let clockwiseDegreesFromWest = positiveRemainder(atan2(Double(y), -Double(x)) * 180 / .pi, 360)
        let segmentDegrees = 360 / Double(itemCount)
        let centeredDegrees = positiveRemainder(clockwiseDegreesFromWest + segmentDegrees / 2, 360)
        return min(Int(centeredDegrees / segmentDegrees), itemCount - 1)
    }

    private static func positiveRemainder(_ value: Double, _ divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

@available(iOS 13.0, *)
struct RadialMenuView: View {
    let sectors: [RadialMenuSector]
    var selectedIndex: Int?
    var isTouchSelectionEnabled: Bool
    var style: RadialMenuStyle

    @ObservedObject private var joystickSelectionState: RadialMenuSelectionState
    @SwiftUI.State private var touchSelectedIndex: Int?

    private var effectiveSelectedIndex: Int? {
        if isTouchSelectionEnabled, let touchSelectedIndex {
            return touchSelectedIndex
        }

        if joystickSelectionState.hasReceivedJoystickInput {
            return joystickSelectionState.selectedIndex
        }

        return selectedIndex
    }

    private var selectedItem: RadialMenuSector? {
        guard let selectedIndex = effectiveSelectedIndex,
              sectors.indices.contains(selectedIndex) else {
            return sectors.first
        }
        return sectors[selectedIndex]
    }

    init(
        sectors: [RadialMenuSector],
        selectedIndex: Int? = nil,
        isTouchSelectionEnabled: Bool = true,
        style: RadialMenuStyle = RadialMenuStyle(),
        selectionState: RadialMenuSelectionState = RadialMenuSelectionState()
    ) {
        self.sectors = sectors
        self.selectedIndex = selectedIndex
        self.isTouchSelectionEnabled = isTouchSelectionEnabled
        self.style = style
        self.joystickSelectionState = selectionState
        self.joystickSelectionState.configureItemCount(sectors.count)
    }

    func updateSelection(xOffset: Float, yOffset: Float) {
        joystickSelectionState.configureItemCount(sectors.count)
        joystickSelectionState.updateSelection(xOffset: xOffset, yOffset: yOffset)
    }

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let outerRadius = diameter / 2
            let innerRadius = outerRadius * (1 - style.ringWidthRatio)

            ZStack {
                ForEach(sectors.indices, id: \.self) { index in
                    RadialMenuSegmentShape(
                        index: index,
                        count: sectors.count,
                        innerRadiusRatio: 1 - style.ringWidthRatio,
                        gapWidth: style.segmentGapWidth
                    )
                    .fill(index == effectiveSelectedIndex ? style.selectedRingColor : style.ringColor)
                    .overlay(
                        RadialMenuSegmentShape(
                            index: index,
                            count: sectors.count,
                            innerRadiusRatio: 1 - style.ringWidthRatio,
                            gapWidth: style.segmentGapWidth
                        )
                        .stroke(style.ringStrokeColor.opacity(index == effectiveSelectedIndex ? 0.95 : 0.28), lineWidth: index == effectiveSelectedIndex ? 1.6 : 0.8)
                    )
                    .scaleEffect(index == effectiveSelectedIndex ? 1.018 : 1)
                    .animation(.spring(response: 0.24, dampingFraction: 0.78), value: effectiveSelectedIndex)
                }

                Circle()
                    .fill(style.centerFillColor)
                    .frame(width: innerRadius * 2, height: innerRadius * 2)
                    .shadow(color: style.shadowColor, radius: 10, x: 0, y: 3)

                ForEach(sectors.indices, id: \.self) { index in
                    let item = sectors[index]
                    Image(systemName: item.systemImageName)
                        .font(.system(size: max(diameter * style.segmentIconScale, 18), weight: .medium))
                        .foregroundColor(index == effectiveSelectedIndex ? style.selectedIconColor : style.iconColor)
                        .scaleEffect(index == effectiveSelectedIndex ? 1.18 : 1)
                        .position(iconPosition(index: index, count: sectors.count, center: center, radius: (outerRadius + innerRadius) / 2))
                        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: effectiveSelectedIndex)
                }

                RadialMenuCenterView(item: selectedItem, style: style, diameter: diameter)
                    .frame(width: innerRadius * 1.72, height: innerRadius * 1.72)
                    .position(center)
                    .animation(.easeInOut(duration: 0.16), value: effectiveSelectedIndex)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Circle())
            .gesture(touchSelectionGesture(center: center, innerRadius: innerRadius, outerRadius: outerRadius))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func touchSelectionGesture(center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard isTouchSelectionEnabled else { return }
                touchSelectedIndex = index(for: value.location, center: center, innerRadius: innerRadius, outerRadius: outerRadius)
            }
            .onEnded { _ in
                guard isTouchSelectionEnabled else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    touchSelectedIndex = nil
                }
            }
    }

    private func index(for location: CGPoint, center: CGPoint, innerRadius: CGFloat, outerRadius: CGFloat) -> Int? {
        guard !sectors.isEmpty else { return nil }

        let dx = location.x - center.x
        let dy = location.y - center.y
        let distance = hypot(dx, dy)
        guard distance >= innerRadius * 0.72, distance <= outerRadius * 1.08 else {
            return nil
        }

        let clockwiseDegreesFromWest = positiveRemainder(atan2(Double(-dy), Double(-dx)) * 180 / Double.pi, 360)
        let segmentDegrees = 360 / Double(sectors.count)
        let centeredDegrees = positiveRemainder(clockwiseDegreesFromWest + segmentDegrees / 2, 360)
        return min(Int(centeredDegrees / segmentDegrees), sectors.count - 1)
    }

    private func iconPosition(index: Int, count: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        guard count > 0 else { return center }
        let segmentDegrees = 360 / Double(count)
        let angleDegrees = 180 + Double(index) * segmentDegrees
        let radians = angleDegrees * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }

    private func positiveRemainder(_ value: Double, _ divisor: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder >= 0 ? remainder : remainder + divisor
    }
}

@available(iOS 13.0, *)
private struct RadialMenuCenterView: View {
    let item: RadialMenuSector?
    let style: RadialMenuStyle
    let diameter: CGFloat

    var body: some View {
        VStack(spacing: max(diameter * 0.018, 4)) {
            Image(systemName: item?.systemImageName ?? "circle.grid.cross")
                .font(.system(size: max(diameter * style.centerIconScale, 28), weight: .medium))
                .foregroundColor(style.iconColor)
                .id(item?.id)
                .transition(.opacity)

            Text(item?.title ?? "")
                .font(.system(size: max(diameter * 0.047, 13), weight: .medium))
                .foregroundColor(style.titleColor)
                .lineLimit(1)
                .minimumScaleFactor(0.62)

            if item?.subtitle.isEmpty == false {
                Text(item?.subtitle ?? "")
                    .font(.system(size: max(diameter * 0.032, 10), weight: .regular))
                    .foregroundColor(style.subtitleColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, diameter * 0.035)
    }
}

@available(iOS 13.0, *)
private struct RadialMenuSegmentShape: Shape {
    let index: Int
    let count: Int
    let innerRadiusRatio: CGFloat
    let gapWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        guard count > 0 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRadiusRatio
        let segmentDegrees = 360 / Double(count)
        let centerDegrees = 180 + Double(index) * segmentDegrees
        let startBoundaryDegrees = centerDegrees - segmentDegrees / 2
        let endBoundaryDegrees = centerDegrees + segmentDegrees / 2
        let halfGap = min(gapWidth / 2, max(innerRadius - 1, 0))

        var path = Path()
        let outerStart = offsetBoundaryPoint(center: center, radius: outerRadius, boundaryDegrees: startBoundaryDegrees, inwardSign: 1, halfGap: halfGap)
        let innerStart = offsetBoundaryPoint(center: center, radius: innerRadius, boundaryDegrees: startBoundaryDegrees, inwardSign: 1, halfGap: halfGap)
        let outerEnd = offsetBoundaryPoint(center: center, radius: outerRadius, boundaryDegrees: endBoundaryDegrees, inwardSign: -1, halfGap: halfGap)
        let innerEnd = offsetBoundaryPoint(center: center, radius: innerRadius, boundaryDegrees: endBoundaryDegrees, inwardSign: -1, halfGap: halfGap)
        let outerStartDegrees = degrees(from: center, to: outerStart)
        let outerEndDegrees = unwrappedEndDegrees(start: outerStartDegrees, end: degrees(from: center, to: outerEnd))
        let innerStartDegrees = degrees(from: center, to: innerStart)
        let innerEndDegrees = unwrappedEndDegrees(start: innerStartDegrees, end: degrees(from: center, to: innerEnd))

        path.move(to: outerStart)

        let outerSteps = max(Int((outerEndDegrees - outerStartDegrees) / 4), 6)
        for step in 1...outerSteps {
            let progress = Double(step) / Double(outerSteps)
            let degrees = outerStartDegrees + (outerEndDegrees - outerStartDegrees) * progress
            path.addLine(to: point(center: center, radius: outerRadius, degrees: degrees))
        }

        path.addLine(to: innerEnd)

        let innerSteps = max(Int((innerEndDegrees - innerStartDegrees) / 4), 6)
        for step in 0...innerSteps {
            let progress = Double(step) / Double(innerSteps)
            let degrees = innerEndDegrees - (innerEndDegrees - innerStartDegrees) * progress
            path.addLine(to: point(center: center, radius: innerRadius, degrees: degrees))
        }

        path.addLine(to: outerStart)
        path.closeSubpath()
        return path
    }

    private func offsetBoundaryPoint(
        center: CGPoint,
        radius: CGFloat,
        boundaryDegrees: Double,
        inwardSign: CGFloat,
        halfGap: CGFloat
    ) -> CGPoint {
        let radians = boundaryDegrees * .pi / 180
        let radialX = CGFloat(cos(radians))
        let radialY = CGFloat(sin(radians))
        let tangentX = -radialY
        let tangentY = radialX
        let radialDistance = sqrt(max(radius * radius - halfGap * halfGap, 0))

        return CGPoint(
            x: center.x + radialX * radialDistance + tangentX * halfGap * inwardSign,
            y: center.y + radialY * radialDistance + tangentY * halfGap * inwardSign
        )
    }

    private func point(center: CGPoint, radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(
            x: center.x + CGFloat(cos(radians)) * radius,
            y: center.y + CGFloat(sin(radians)) * radius
        )
    }

    private func degrees(from center: CGPoint, to point: CGPoint) -> Double {
        atan2(point.y - center.y, point.x - center.x) * 180 / .pi
    }

    private func unwrappedEndDegrees(start: Double, end: Double) -> Double {
        end < start ? end + 360 : end
    }
}

@available(iOS 13.0, *)
struct RadialMenuDemoView: View {
    @SwiftUI.State private var itemCount = 8
    @SwiftUI.State private var isTouchSelectionEnabled = true

    static let menuItems = [
        RadialMenuSector(title: "Settings Menu".localized, subtitle: "", systemImageName: "sidebar.left", item: .settings),
        RadialMenuSector(title: "Host View".localized, subtitle: "", systemImageName: PublicUtils.liquidGlassEnabled ? "macwindow.on.rectangle" : "tv", item: .hostView),
        RadialMenuSector(title: "Game Profiles".localized, subtitle: "", systemImageName: "gamecontroller.circle", item: .gameProfiles),
        RadialMenuSector(title: "Exit/Disconnect".localized, subtitle: "", systemImageName: "personalhotspot.slash", item: .gameProfiles),
    ]

    private var visibleItems: [RadialMenuSector] {
        Array(Self.menuItems.prefix(itemCount))
    }

    var body: some View {
        VStack(spacing: 28) {
            RadialMenuView(
                sectors: visibleItems,
                selectedIndex: isTouchSelectionEnabled ? nil : 2,
                isTouchSelectionEnabled: isTouchSelectionEnabled
            )
            .frame(width: 320, height: 320)
            .padding(.top, 24)

            VStack(spacing: 16) {
                Stepper("Segments: \(itemCount)", value: $itemCount, in: 3...RadialMenuDemoView.menuItems.count)
                    .frame(maxWidth: 320)

                Toggle("Touch selection", isOn: $isTouchSelectionEnabled)
                    .frame(maxWidth: 320)
            }
            .font(.system(size: 15, weight: .medium))
            .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.97))
    }
}

@available(iOS 13.0, *)
struct RadialMenuView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RadialMenuDemoView()
                .previewLayout(.sizeThatFits)

            RadialMenuView(
                sectors: Array(RadialMenuDemoView.menuItems.prefix(6)),
                selectedIndex: 1,
                isTouchSelectionEnabled: false
            )
            .frame(width: 300, height: 300)
            .padding(36)
            .previewLayout(.sizeThatFits)
        }
    }
}
