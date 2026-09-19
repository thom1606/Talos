import SwiftUI

struct OnboardingButton: View {
    let title: LocalizedStringKey
    var prominent = false
    let action: () -> Void

    var body: some View {
        if prominent {
            button.buttonStyle(.glassProminent)
        } else {
            button.buttonStyle(.glass)
        }
    }

    private var button: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonBorderShape(.capsule)
        .tint(.accentColor)
        .frame(width: TalosOnboarding.buttonWidth, height: TalosOnboarding.buttonHeight)
    }
}
