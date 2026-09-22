import SwiftUI

struct RuntimeWheelView: View {
    let model: WheelModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            glassSurfaces
                .allowsHitTesting(false)

            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                actionContent(action, index: index)
            }

            DwellProgress(
                model: model,
                target: WheelModel.backTarget,
                shape: WheelProgressArc(),
                color: .white
            )
            .frame(width: 88, height: 88)

            centerContent
        }
        .frame(width: WheelLayout.runtime.size, height: WheelLayout.runtime.size)
        .scaleEffect(model.isVisible ? 1 : (reduceMotion ? 1 : 0.76))
        .opacity(model.isVisible ? 1 : 0)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.34, dampingFraction: 0.78),
            value: model.isVisible
        )
        .animation(.easeInOut(duration: 0.14), value: model.hoveredID)
    }

    @ViewBuilder
    private var glassSurfaces: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 0) {
                surfaces
            }
        } else {
            surfaces
        }
    }

    private var surfaces: some View {
        ZStack {
            ForEach(Array(model.actions.enumerated()), id: \.element.id) { index, action in
                let shape = WheelSegment(
                    angle: WheelLayout.runtime.angle(index: index, count: model.actions.count),
                    count: model.actions.count
                )
                shape
                    .fill(.clear)
                    .modifier(
                        WheelGlass(
                            shape: shape,
                            isSelected: model.hoveredID == action.id
                        )
                    )
            }

            WheelCenter()
                .fill(.clear)
                .modifier(
                    WheelGlass(
                        shape: WheelCenter(),
                        isSelected: model.dwellTarget == WheelModel.backTarget
                    )
                )
        }
        .id(model.actions.map(\.id))
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private var centerContent: some View {
        VStack(spacing: 5) {
            if let hoveredAction = model.hoveredAction {
                Image(systemName: hoveredAction.symbolName)
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 24, height: 24)

                Text(hoveredAction.title.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 68)
            } else if !model.parents.isEmpty {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 21, weight: .light))
                    .frame(width: 24, height: 24)

                Text("BACK")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(1.2)
            }
        }
        .frame(width: 88, height: 88)
        .foregroundStyle(
            model.dwellTarget == WheelModel.backTarget ? Color.white : Color.primary
        )
        .contentTransition(.opacity)
        .allowsHitTesting(false)
    }

    private func actionContent(_ action: WheelAction, index: Int) -> some View {
        let angle = WheelLayout.runtime.angle(index: index, count: model.actions.count)
        let isSelected = model.hoveredID == action.id

        return WheelSegment(angle: angle, count: model.actions.count)
            .fill(.clear)
            .overlay {
                if action.isFolder {
                    DwellProgress(
                        model: model,
                        target: action.id.uuidString,
                        shape: WheelProgressArc(angle: angle, count: model.actions.count)
                    )
                }
            }
            .overlay {
                WheelTileLabel(
                    title: action.title,
                    symbolName: action.symbolName,
                    layout: .runtime,
                    count: model.actions.count
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .offset(
                    x: cos(angle) * WheelLayout.runtime.contentRadius,
                    y: sin(angle) * WheelLayout.runtime.contentRadius
                )
            }
            .allowsHitTesting(false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(action.title)
    }
}

private struct WheelGlass<S: Shape>: ViewModifier {
    let shape: S
    let isSelected: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(
                isSelected ? WheelAppearance.red : Color(nsColor: .windowBackgroundColor),
                in: shape
            )
        } else if #available(macOS 26, *) {
            content.glassEffect(
                isSelected ? .clear.tint(WheelAppearance.red) : .regular,
                in: shape
            )
        } else {
            content.background(.ultraThinMaterial, in: shape)
                .overlay {
                    if isSelected {
                        shape.fill(WheelAppearance.red.opacity(0.65))
                    }
                }
        }
    }
}

private struct DwellProgress<S: Shape>: View {
    let model: WheelModel
    let target: String
    let shape: S
    var color: Color = WheelAppearance.red

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
