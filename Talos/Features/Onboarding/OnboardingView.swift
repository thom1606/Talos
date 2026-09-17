import AppKit
import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step: Step = .intro

    private enum Step {
        case intro
        case experience
        case ready
    }

    var body: some View {
        content
            .frame(width: TalosOnboarding.windowWidth, height: TalosOnboarding.contentHeight)
            .background(HiddenTitleBar(centred: true))
            .navigationTitle("Talos")
            .tint(.accentColor)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .intro:
            OnboardingIntroView { step = .experience }
        case .experience:
            OnboardingExperienceView { step = .ready }
        case .ready:
            OnboardingReadyView(onFinish: finish)
        }
    }

    private func finish() {
        AppPreferences.defaults.set(true, forKey: "completedOnboarding")
        if let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            NSWorkspace.shared.open(downloads)
        }
        onFinish()
    }
}

#Preview {
    OnboardingView {}
}
