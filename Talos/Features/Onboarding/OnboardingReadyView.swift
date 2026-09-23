import SwiftUI

struct OnboardingReadyView: View {
    let onFinish: () -> Void

    var body: some View {
        OnboardingPage(
            title: "It’s ready in Finder",
            subtitle: "Start dragging files in Finder, hold Shift, then drop them on the Talos action you want to run.",
            fillsContent: true
        ) {
            finderDragPreview
                .frame(maxHeight: .infinity)
        } actions: {
            Spacer()
            OnboardingButton(title: "Let’s go!", prominent: true, action: onFinish)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.finish")
        }
    }

    private var finderDragPreview: some View {
        HStack(spacing: 18) {
            VStack(spacing: 7) {
                Image(systemName: "doc.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Files")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "arrow.right")
                .font(.title3.weight(.medium))
                .foregroundStyle(WheelAppearance.red)
            ZStack {
                Circle()
                    .fill(WheelAppearance.red.opacity(0.13))
                    .frame(width: 70, height: 70)
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(WheelAppearance.red)
            }
            Image(systemName: "arrow.right")
                .font(.title3.weight(.medium))
                .foregroundStyle(WheelAppearance.red)
            VStack(spacing: 7) {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text("Action")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(nsColor: .quaternarySystemFill),
                    in: .rect(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

#Preview {
    OnboardingReadyView {}
        .tint(.accentColor)
}
