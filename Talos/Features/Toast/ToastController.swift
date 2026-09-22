import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
private final class ToastModel {
    var request = TalosToastRequest(message: "", kind: .information)
    var isVisible = false
}

@MainActor
final class ToastController {
    private let model = ToastModel()
    private let panel: NSPanel
    private var dismissalTask: Task<Void, Never>?

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 72),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isExcludedFromWindowsMenu = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle,
        ]
        panel.contentView = NSHostingView(rootView: ToastView(model: model))
    }

    func show(_ request: TalosToastRequest) {
        dismissalTask?.cancel()
        model.request = request
        model.isVisible = true
        positionPanel()
        panel.orderFrontRegardless()

        guard request.kind != .loading else { return }
        scheduleDismissal()
    }

    func dismiss() {
        dismissalTask?.cancel()
        model.isVisible = false
        dismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(220))
            } catch {
                return
            }
            self?.panel.orderOut(nil)
        }
    }

    private func scheduleDismissal() {
        dismissalTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(2.4))
            } catch {
                return
            }
            guard let self else { return }
            model.isVisible = false
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            panel.orderOut(nil)
        }
    }

    func stop() {
        dismissalTask?.cancel()
        model.isVisible = false
        panel.orderOut(nil)
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        panel.setFrameOrigin(
            CGPoint(
                x: visibleFrame.midX - panel.frame.width / 2,
                y: visibleFrame.minY + 18
            )
        )
    }
}

private struct ToastView: View {
    let model: ToastModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            if model.isVisible {
                HStack(spacing: 9) {
                    ToastStatusIcon(kind: model.request.kind)

                    Text(model.request.message)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .contentTransition(.numericText())
                        .animation(
                            reduceMotion ? nil : .snappy(duration: 0.32),
                            value: model.request.message
                        )
                }
                .padding(.horizontal, 15)
                .frame(height: 42)
                .fixedSize(horizontal: true, vertical: false)
                .background {
                    if reduceTransparency {
                        Capsule().fill(.regularMaterial)
                    }
                }
                .modifier(ToastGlass(isEnabled: !reduceTransparency))
                .shadow(color: .black.opacity(0.14), radius: 16, y: 6)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .offset(y: 12).combined(with: .scale(scale: 0.88)).combined(with: .opacity)
                )
            }
        }
        .frame(width: 460, height: 72)
        .animation(
            reduceMotion
                ? .easeOut(duration: 0.12)
                : .spring(response: 0.36, dampingFraction: 0.8),
            value: model.isVisible
        )
        .accessibilityElement(children: .combine)
    }
}

private struct ToastStatusIcon: View {
    let kind: TalosToastRequest.Kind

    var body: some View {
        Group {
            switch kind {
            case .loading:
                ProgressView()
                    .controlSize(.small)
            case .information:
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(.blue)
            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failure:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .frame(width: 16, height: 16)
        .contentTransition(.symbolEffect(.replace))
        .accessibilityHidden(true)
    }
}

private struct ToastGlass: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            if #available(macOS 26, *) {
                content.glassEffect(.regular, in: Capsule())
            } else {
                content
            }
        } else {
            content
        }
    }
}
