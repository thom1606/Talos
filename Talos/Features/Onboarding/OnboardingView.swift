import SwiftUI

struct OnboardingView: View {
    let model: AdvancedSettingsModel
    let notifications: NotificationService
    let onFinish: () -> Void
    @State private var step = Step.intro
    private enum Step { case intro, experience, ready }

    var body: some View {
        content
            .frame(width: TalosOnboarding.windowWidth, height: TalosOnboarding.contentHeight)
            .tint(.accentColor)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .intro:
            OnboardingIntroView { step = .experience }
        case .experience:
            OnboardingExperienceView(model: model, notifications: notifications) { step = .ready }
        case .ready:
            OnboardingReadyView {
                TalosPreferences.defaults.set(true, forKey: TalosPreferenceKey.completedOnboarding)
                onFinish()
            }
        }
    }
}
