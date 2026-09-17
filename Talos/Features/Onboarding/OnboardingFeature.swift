import SwiftUI

struct OnboardingFeature: View {
    let symbolName: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: TalosOnboarding.featureGap) {
            Image(systemName: symbolName)
                .font(.title)
                .foregroundStyle(.tint)
                .frame(width: TalosOnboarding.featureIconBox, height: TalosOnboarding.featureIconBox)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
