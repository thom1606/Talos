import SwiftUI

/// The regular system material follows appearance and accessibility preferences.
struct WheelGlass<S: Shape>: ViewModifier {
    let shape: S
    let selected: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(selected ? Color.accentColor : Color(nsColor: .windowBackgroundColor), in: shape)
        } else {
            content.glassEffect(
                selected ? .clear.tint(Color.accentColor) : .regular,
                in: shape
            )
        }
    }
}

/// A detached arc follows the tile's outer edge; the centre uses an inset ring.
nonisolated struct WheelProgressArc: Shape {
    var angle: Double = -.pi / 2
    var count: Int? = nil

    func path(in rect: CGRect) -> Path {
        let radius = count == nil ? min(rect.width, rect.height) / 2 - 5 : WheelGeometry.outer + 9
        let half = count.map { Double.pi / Double($0) - 0.06 } ?? Double.pi
        let start = count == nil ? angle : angle - half
        let end = count == nil ? angle + 2 * .pi : angle + half
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: radius,
                    startAngle: .radians(start), endAngle: .radians(end), clockwise: false)
        return path
    }
}

/// The same deadline drives the progress stroke and submenu/back navigation.
struct DwellProgress<S: Shape>: View {
    let state: WheelModel
    let target: String
    let shape: S
    var color: Color = .white
    var lineWidth: CGFloat = 3

    var body: some View {
        TimelineView(.animation(paused: state.dwellTarget != target)) { context in
            let active = state.dwellTarget == target
            let progress = active ? state.dwellProgress(at: context.date) : 0
            ZStack {
                shape.stroke(color.opacity(0.25), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                shape.trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            }
            .opacity(active ? 1 : 0)
            .transaction { $0.animation = nil }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Labels follow the same interpolated angle as the segment, along the circle.
struct WheelOrbit: AnimatableModifier {
    var angle: Double
    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        content.offset(x: cos(angle) * 103, y: sin(angle) * 103)
    }
}
