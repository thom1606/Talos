import SwiftUI

struct OnboardingIntroView: View {
    let onNext: () -> Void

    var body: some View {
        OnboardingPage(
            title: "Welcome to Talos",
            subtitle: "A faster way to use the actions you already rely on, right where your files are.",
            revealsIcon: true
        ) {
            VStack(alignment: .leading, spacing: TalosOnboarding.contentGap) {
                OnboardingFeature(
                    symbolName: "cursorarrow.and.square.on.square.dashed",
                    title: "Built around your files",
                    detail: "Drag one or more files in Finder and hold Shift to open a wheel of actions that match them."
                )
                OnboardingFeature(
                    symbolName: "circle.hexagongrid",
                    title: "Your actions, your order",
                    detail: "Add actions from the repositories you trust, then arrange them into the wheel that works for you."
                )
                OnboardingFeature(
                    symbolName: "lock.shield",
                    title: "Ready on your Mac",
                    detail: "Everyday actions are included. Add JavaScript extensions without installing developer tools."
                )
            }
        } actions: {
            Spacer()
            OnboardingButton(title: "Next", prominent: true, action: onNext)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("onboarding.next")
        }
    }
}

#Preview {
    OnboardingIntroView {}
        .tint(.accentColor)
}
