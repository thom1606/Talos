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

    // Navigation keeps a fixed bottom segment at every folder depth.
    var backAngle: Double { .pi / 2 }
    var backSpan: Double { 70 * .pi / 180 }

    var contentRadius: Double { Double((innerRadius + outerRadius) / 2) }

    func angle(index: Int, count: Int, reservesBack: Bool = false) -> Double {
        if reservesBack {
            return actionStartAngle + (Double(index) + 0.5) * span(count: count, reservesBack: true)
        }
        return -.pi / 2 + Double(index) * 2 * .pi / Double(max(1, count))
    }

    func span(count: Int, reservesBack: Bool = false) -> Double {
        (2 * .pi - (reservesBack ? backSpan : 0)) / Double(max(1, count))
    }

    private var actionStartAngle: Double { backAngle + backSpan / 2 - 2 * .pi }

    func contains(_ point: CGPoint) -> Bool {
        hypot(point.x - size / 2, point.y - size / 2) <= outerRadius
    }

    func index(at point: CGPoint, count: Int, reservesBack: Bool = false) -> Int? {
        guard count > 0 else { return nil }

        let x = point.x - size / 2
        let y = point.y - size / 2
        let radius = hypot(x, y)
        guard radius >= innerRadius, radius <= outerRadius else { return nil }
        guard !reservesBack || !isBack(at: point) else { return nil }

        return insertionIndex(at: point, count: count, reservesBack: reservesBack)
    }

    func isBack(at point: CGPoint) -> Bool {
        let x = point.x - size / 2
        let y = point.y - size / 2
        let radius = hypot(x, y)
        return radius >= innerRadius && radius <= outerRadius
            && abs(atan2(y, x) - backAngle) <= backSpan / 2
    }

    func insertionIndex(at point: CGPoint, count: Int, reservesBack: Bool = false) -> Int {
        let count = max(1, count)
        let x = point.x - size / 2
        let y = point.y - size / 2
        if reservesBack {
            let normalized = (atan2(y, x) - actionStartAngle + 2 * .pi)
                .truncatingRemainder(dividingBy: 2 * .pi)
            let actionSpan = 2 * .pi - backSpan
            if normalized >= actionSpan {
                return normalized - actionSpan < backSpan / 2 ? count - 1 : 0
            }
            return min(count - 1, Int(normalized / span(count: count, reservesBack: true)))
        }
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

    func contentWidth(count: Int, maximum: CGFloat, reservesBack: Bool = false) -> CGFloat {
        contentWidth(span: span(count: count, reservesBack: reservesBack), maximum: maximum)
    }

    func contentWidth(span: Double, maximum: CGFloat) -> CGFloat {
        let half = min(.pi / 2, span / 2)
        return min(maximum, 2 * contentRadius * sin(half) * 0.8)
    }
}

nonisolated struct WheelSegment: Shape {
    var angle: Double
    var half: Double
    let layout: WheelLayout

    init(angle: Double, count: Int, reservesBack: Bool = false, layout: WheelLayout = .runtime) {
        self.init(angle: angle, span: layout.span(count: count, reservesBack: reservesBack), layout: layout)
    }

    init(angle: Double, span: Double, layout: WheelLayout = .runtime) {
        self.angle = angle
        half = span / 2
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
    var span: Double
    var layout: WheelLayout = .runtime

    func path(in rect: CGRect) -> Path {
        let radius = layout.outerRadius + layout.progressOffset
        let segmentHalf = span / 2
        let half = segmentHalf - min(0.06, segmentHalf / 4)
        let start = angle - half
        let end = angle + half

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
