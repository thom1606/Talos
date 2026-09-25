import SwiftUI

/// Visual gaps are decorative; file-drop hit testing partitions the full ring.
nonisolated struct WheelLayout: Equatable {
    static let runtime = Self(size: 336, outerRadius: 146, innerRadius: 57, centerRadius: 44, cornerRadius: 11, progressOffset: 9)
    static let editor = runtime

    let size: CGFloat
    let outerRadius: CGFloat
    let innerRadius: CGFloat
    let centerRadius: CGFloat
    let cornerRadius: CGFloat
    let progressOffset: CGFloat
    let gap: CGFloat = 6

    var contentRadius: Double { Double((innerRadius + outerRadius) / 2) }

    func angle(index: Int, count: Int) -> Double {
        -.pi / 2 + Double(index) * 2 * .pi / Double(max(1, count))
    }

    func contains(_ point: CGPoint) -> Bool {
        hypot(point.x - size / 2, point.y - size / 2) <= outerRadius
    }

    func index(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }

        let x = point.x - size / 2
        let y = point.y - size / 2
        let radius = hypot(x, y)
        guard radius >= innerRadius, radius <= outerRadius else { return nil }

        return insertionIndex(at: point, count: count)
    }

    func insertionIndex(at point: CGPoint, count: Int) -> Int {
        let count = max(1, count)
        let x = point.x - size / 2
        let y = point.y - size / 2
        let step = 2 * Double.pi / Double(count)
        let normalized = (atan2(y, x) + .pi / 2 + step / 2 + 2 * .pi)
            .truncatingRemainder(dividingBy: 2 * .pi)
        return Int(normalized / step) % count
    }

    /// Fit both decorative gaps and corners inside even very narrow segments.
    func segmentMetrics(halfAngle: Double) -> (gap: CGFloat, corner: CGFloat) {
        let half = max(0, min(.pi, halfAngle))
        let fittedGap = min(gap, 2 * innerRadius * sin(half / 4))
        let availableAngle = max(0, half - asin(fittedGap / (2 * innerRadius)))
        return (fittedGap, min(cornerRadius, innerRadius * availableAngle * 0.9))
    }

    func contentWidth(count: Int, maximum: CGFloat) -> CGFloat {
        let half = min(.pi / 2, .pi / Double(max(1, count)))
        return min(maximum, 2 * contentRadius * sin(half) * 0.8)
    }
}

nonisolated struct WheelSegment: Shape {
    var angle: Double
    var half: Double
    let layout: WheelLayout

    init(angle: Double, count: Int, layout: WheelLayout = .runtime) {
        self.angle = angle
        half = .pi / Double(max(1, count))
        self.layout = layout
    }

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, half) }
        set {
            angle = newValue.first
            half = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = layout.outerRadius
        let inner = layout.innerRadius
        let metrics = layout.segmentMetrics(halfAngle: half)
        let rounding = metrics.corner

        func boundary(_ radius: CGFloat, atEnd: Bool) -> Double {
            let inset = asin(metrics.gap / (2 * radius))
            return angle + (atEnd ? half - inset : -half + inset)
        }

        func point(radius: CGFloat, angle: Double) -> CGPoint {
            CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
        }

        let outerStart = boundary(outer, atEnd: false)
        let outerEnd = boundary(outer, atEnd: true)
        let innerStart = boundary(inner, atEnd: false)
        let innerEnd = boundary(inner, atEnd: true)

        var path = Path()
        path.move(to: point(radius: outer, angle: outerStart + rounding / outer))
        path.addArc(
            center: center,
            radius: outer,
            startAngle: .radians(outerStart + rounding / outer),
            endAngle: .radians(outerEnd - rounding / outer),
            clockwise: false
        )
        path.addQuadCurve(
            to: point(radius: outer - rounding, angle: boundary(outer - rounding, atEnd: true)),
            control: point(radius: outer, angle: outerEnd)
        )
        path.addLine(
            to: point(radius: inner + rounding, angle: boundary(inner + rounding, atEnd: true))
        )
        path.addQuadCurve(
            to: point(radius: inner, angle: innerEnd - rounding / inner),
            control: point(radius: inner, angle: innerEnd)
        )
        path.addArc(
            center: center,
            radius: inner,
            startAngle: .radians(innerEnd - rounding / inner),
            endAngle: .radians(innerStart + rounding / inner),
            clockwise: true
        )
        path.addQuadCurve(
            to: point(radius: inner + rounding, angle: boundary(inner + rounding, atEnd: false)),
            control: point(radius: inner, angle: innerStart)
        )
        path.addLine(
            to: point(radius: outer - rounding, angle: boundary(outer - rounding, atEnd: false))
        )
        path.addQuadCurve(
            to: point(radius: outer, angle: outerStart + rounding / outer),
            control: point(radius: outer, angle: outerStart)
        )
        path.closeSubpath()
        return path
    }
}

nonisolated struct WheelCenter: Shape {
    var layout: WheelLayout = .runtime

    func path(in rect: CGRect) -> Path {
        Circle().path(
            in: CGRect(
                x: rect.midX - layout.centerRadius,
                y: rect.midY - layout.centerRadius,
                width: layout.centerRadius * 2,
                height: layout.centerRadius * 2
            )
        )
    }
}

nonisolated struct WheelProgressArc: Shape {
    var angle: Double = -.pi / 2
    var count: Int? = nil
    var layout: WheelLayout = .runtime

    func path(in rect: CGRect) -> Path {
        let radius = count == nil
            ? min(rect.width, rect.height) / 2 - 5
            : layout.outerRadius + layout.progressOffset
        let half = count.map {
            let segmentHalf = Double.pi / Double(max(1, $0))
            return segmentHalf - min(0.06, segmentHalf / 4)
        } ?? Double.pi
        let start = count == nil ? angle : angle - half
        let end = count == nil ? angle + 2 * .pi : angle + half

        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .radians(start),
            endAngle: .radians(end),
            clockwise: false
        )
        return path
    }
}
