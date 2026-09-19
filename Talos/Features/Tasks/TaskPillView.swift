import AppKit
import Observation
import SwiftUI

struct TaskPillView: View {
    @Bindable var model: TaskPillModel
    let visibilityChanged: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let presentation = model.presentation {
                TaskPillContent(presentation: presentation)
                    .id(presentation.id)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .offset(y: 14).combined(with: .scale(scale: 0.82)).combined(with: .opacity),
                        removal: .offset(y: 8).combined(with: .scale(scale: 0.92)).combined(with: .opacity)
                    ))
            }
        }
        .frame(width: 460, height: 84)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.4, dampingFraction: 0.78),
                   value: model.presentation?.id)
        .onChange(of: model.presentation != nil, initial: true) { _, visible in
            visibilityChanged(visible)
        }
    }
}

private struct TaskPillContent: View {
    let presentation: TaskPillPresentation
    @State private var revealsText = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: revealsText ? 10 : 0) {
            icon
                .frame(width: 20, height: 20)
                .contentTransition(.symbolEffect(.replace))

            if revealsText {
                Text(presentation.message)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .frame(height: 46)
        .fixedSize(horizontal: true, vertical: false)
        .background {
            if reduceTransparency {
                Capsule().fill(.regularMaterial)
            }
        }
        .glassEffect(reduceTransparency ? .identity : .regular, in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .smooth(duration: 0.28), value: revealsText)
        .animation(.easeInOut(duration: 0.18), value: presentation.phase)
        .task {
            if !reduceMotion {
                try? await Task.sleep(for: .milliseconds(170))
            }
            withAnimation { revealsText = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch presentation.phase {
        case .running:
            ProgressView()
                .controlSize(.small)
                .accessibilityHidden(true)
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.red)
        }
    }

    private var accessibilityLabel: String {
        switch presentation.phase {
        case .running: "\(presentation.title), \(presentation.message), \(Int(presentation.progress * 100)) percent"
        case .completed: "\(presentation.title) completed"
        case .failed: "\(presentation.title) failed: \(presentation.message)"
        }
    }
}
