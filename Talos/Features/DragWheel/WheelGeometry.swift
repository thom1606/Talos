import SwiftUI

/// Visual gaps are decorative; drag targets partition the complete ring.
nonisolated enum WheelGeometry {
    static let size: CGFloat = 336
    static let outer: CGFloat = 146
    static let inner: CGFloat = 57
    static let gap: CGFloat = 6

    static func angle(index: Int, count: Int) -> Double {
        -.pi / 2 + Double(index) * 2 * .pi / Double(count)
    }

    static func index(at point: CGPoint, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let x = point.x - size / 2, y = point.y - size / 2
        let radius = hypot(x, y)
        guard radius >= inner, radius <= outer else { return nil }
        let step = 2 * Double.pi / Double(count)
        let normalized = (atan2(y, x) + .pi / 2 + step / 2 + 2 * .pi).truncatingRemainder(dividingBy: 2 * .pi)
        return Int(normalized / step) % count
    }
}

nonisolated struct WheelSegment: Shape {
    var angle: Double
    var half: Double

    init(angle: Double, count: Int) {
        self.angle = angle
        half = .pi / Double(max(1, count))
    }

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(angle, half) }
        set { angle = newValue.first; half = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = WheelGeometry.outer, inner = WheelGeometry.inner
        let rounding: CGFloat = 11
        // Offset each radial boundary by half the gap in points. A constant
        // angular inset would widen with radius instead of making parallel edges.
        func boundary(_ radius: CGFloat, end: Bool) -> Double {
            let inset = asin(WheelGeometry.gap / (2 * radius))
            return angle + (end ? half - inset : -half + inset)
        }
        func point(_ radius: CGFloat, _ a: Double) -> CGPoint {
            CGPoint(x: center.x + radius * cos(a), y: center.y + radius * sin(a))
        }
        let outerStart = boundary(outer, end: false)
        let outerEnd = boundary(outer, end: true)
        let innerStart = boundary(inner, end: false)
        let innerEnd = boundary(inner, end: true)
        var p = Path()
        p.move(to: point(outer, outerStart + rounding / outer))
        p.addArc(center: center, radius: outer, startAngle: .radians(outerStart + rounding / outer), endAngle: .radians(outerEnd - rounding / outer), clockwise: false)
        p.addQuadCurve(to: point(outer - rounding, boundary(outer - rounding, end: true)), control: point(outer, outerEnd))
        p.addLine(to: point(inner + rounding, boundary(inner + rounding, end: true)))
        p.addQuadCurve(to: point(inner, innerEnd - rounding / inner), control: point(inner, innerEnd))
        p.addArc(center: center, radius: inner, startAngle: .radians(innerEnd - rounding / inner), endAngle: .radians(innerStart + rounding / inner), clockwise: true)
        p.addQuadCurve(to: point(inner + rounding, boundary(inner + rounding, end: false)), control: point(inner, innerStart))
        p.addLine(to: point(outer - rounding, boundary(outer - rounding, end: false)))
        p.addQuadCurve(to: point(outer, outerStart + rounding / outer), control: point(outer, outerStart))
        p.closeSubpath()
        return p
    }
}

/// Keep the centre glass on the same canvas as the surrounding glass segments.
nonisolated struct WheelCentre: Shape {
    func path(in rect: CGRect) -> Path {
        Circle().path(in: CGRect(x: rect.midX - 44, y: rect.midY - 44, width: 88, height: 88))
    }
}

