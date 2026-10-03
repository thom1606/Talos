import SwiftUI

struct RuntimeWheelView: View {
    let model: WheelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            WheelGlassSurface(surface: .center)
                .equatable()
                .allowsHitTesting(false)

            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                RuntimeWheelTile(model: model, action: action, index: index)
                    .transition(.identity)
            }

            if model.canNavigateBack {
                RuntimeWheelTile(model: model, action: nil, index: model.actions.count)
            }

            WheelCenterContent(model: model)
        }
        .frame(width: WheelLayout.runtime.size, height: WheelLayout.runtime.size)
        .compositingGroup()
        .opacity(model.isVisible ? 1 : 0)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.16), value: model.isVisible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wheel.runtime.\(model.activeWheel.rawValue)")
    }
}

/// Back and actions share the whole tile, including its glass and entrance.
private struct RuntimeWheelTile: View {
    let model: WheelModel
    let action: WheelAction?
    let index: Int
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let layout = WheelLayout.runtime
        let count = model.actions.count
        let reservesBack = model.canNavigateBack
        let isBack = action == nil
        let angle = isBack ? layout.backAngle : layout.angle(index: index, count: count, reservesBack: reservesBack)
        let span = isBack ? layout.backSpan : layout.span(count: count, reservesBack: reservesBack)
        let shape = WheelSegment(angle: angle, span: span)
        let isEnabled = action?.isEnabled ?? true
        let isSelected = isBack ? model.dwellTarget == WheelModel.backTarget : model.hoveredID == action?.id
        let title = action?.title ?? String(localized: "Back")
        let target = isBack ? WheelModel.backTarget : (action?.isFolder == true && isEnabled ? action?.id.uuidString : nil)

        return WheelGlassSurface(surface: .segment(angle: angle, span: span))
            .equatable()
            .overlay {
                shape.fill(isSelected && isEnabled ? TalosAppearance.glassHoverTint : .clear)
                    .blendMode(reduceTransparency ? .normal : .multiply)
                    .animation(.easeInOut(duration: 0.14), value: isSelected)
            }
            .overlay {
                if let target {
                    DwellProgress(model: model, target: target, shape: WheelProgressArc(angle: angle, span: span))
                }
            }
            .overlay {
                WheelTileLabel(
                    title: title,
                    symbolName: action?.symbolName ?? "arrow.uturn.backward",
                    layout: layout,
                    count: isBack ? 4 : count,
                    isEditor: false,
                    reservesBack: !isBack && reservesBack
                )
                .foregroundStyle(isSelected && isEnabled ? Color.white : Color.primary)
                .opacity(isEnabled ? 1 : 0.38)
                .offset(x: cos(angle) * layout.contentRadius, y: sin(angle) * layout.contentRadius)
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(action?.title ?? String(localized: "Back to parent folder"))
            .compositingGroup()
            .modifier(WheelTileEntrance(index: index, count: count + (reservesBack ? 1 : 0), isVisible: model.isVisible))
    }
}

private struct WheelCenterContent: View {
    let model: WheelModel

    var body: some View {
        VStack(spacing: 5) {
            if let hoveredAction = model.hoveredAction {
                if !hoveredAction.symbolName.isEmpty {
                    Image(systemName: hoveredAction.symbolName)
                        .font(.system(size: 17, weight: .medium))
                        .frame(width: 24, height: 24)
                }

                Text(hoveredAction.title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 68)
            } else if model.actions.isEmpty {
                Text("No actions")
                    .font(.system(size: 9, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .frame(width: 68)
            }
        }
        .frame(width: 88, height: 88)
        .foregroundStyle(Color.primary)
        .opacity(model.hoveredAction?.isEnabled == false ? 0.45 : 1)
        .contentTransition(.opacity)
        .allowsHitTesting(false)
    }
}

/// Each tile owns its glass container so transforms include the material itself.
/// The material depends only on geometry, never on hover state.
private struct WheelGlassSurface: View, Equatable {
    enum Surface: Equatable {
        case segment(angle: Double, span: Double)
        case center
    }

    let surface: Surface

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 0) {
                glass
            }
        } else {
            glass
        }
    }

    private var glass: some View {
        Group {
            switch surface {
            case let .segment(angle, span):
                let shape = WheelSegment(angle: angle, span: span)
                shape.fill(.clear).modifier(WheelGlass(shape: shape))
            case .center:
                let shape = WheelCenter()
                shape.fill(.clear).modifier(WheelGlass(shape: shape))
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

/// Keep glass, highlight, icon and label moving together around the wheel.
private struct WheelTileEntrance: ViewModifier {
    let index: Int
    let count: Int
    let isVisible: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isVisible || reduceMotion ? 1 : 0.86)
            .rotationEffect(.degrees(isVisible || reduceMotion ? 0 : -6))
            .opacity(isVisible ? 1 : 0)
            .animation(animation, value: isVisible)
    }

    private var animation: Animation {
        if reduceMotion { return .easeOut(duration: 0.12) }
        if !isVisible { return .easeOut(duration: 0.16) }
        // Keep the entire entrance brief, including wheels with many actions.
        let stagger = min(0.03, 0.15 / Double(max(1, count - 1)))
        return .spring(duration: 0.28, bounce: 0.15).delay(Double(index) * stagger)
    }
}

private struct WheelGlass<S: Shape>: ViewModifier {
    let shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
        } else if #available(macOS 26, *) {
            content.glassEffect(.regular, in: shape)
                .glassEffectTransition(.identity)
        } else {
            content.background(.ultraThinMaterial, in: shape)
        }
    }
}

private struct DwellProgress<S: Shape>: View {
    let model: WheelModel
    let target: String
    let shape: S
    var color: Color = TalosAppearance.accent

    var body: some View {
        TimelineView(.animation(paused: model.dwellTarget != target)) { context in
            let isActive = model.dwellTarget == target
            let progress = isActive ? model.dwellProgress(at: context.date) : 0

            ZStack {
                shape.stroke(
                    color.opacity(0.28),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                shape.trim(from: 0, to: progress)
                    .stroke(
                        color,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
            }
            .opacity(isActive ? 1 : 0)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
