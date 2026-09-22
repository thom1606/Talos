import AppKit
import SwiftUI

/// The shared first-run layout, matching the Settings experience used across
/// Thom's macOS apps: a 400-point column and fixed capsule actions.
struct OnboardingPage<Content: View, Actions: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var revealsIcon = false
    var fillsContent = false
    @ViewBuilder var content: () -> Content
    @ViewBuilder var actions: () -> Actions

    @State private var iconVisible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            wrapper
                .frame(width: TalosOnboarding.wrapperWidth, alignment: .leading)
                .padding(.top, TalosOnboarding.wrapperTopPadding)
                .frame(maxHeight: fillsContent ? .infinity : nil, alignment: .top)
                .layoutPriority(fillsContent ? 1 : 0)

            Spacer(minLength: TalosOnboarding.wrapperToButtons)

            HStack(spacing: TalosOnboarding.buttonGap) {
                actions()
            }
            .padding(.horizontal, TalosOnboarding.margin)
            .padding(.bottom, TalosOnboarding.bottomMargin)
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var wrapper: some View {
        VStack(alignment: .leading, spacing: TalosOnboarding.iconGap) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: TalosOnboarding.iconSize, height: TalosOnboarding.iconSize)
                .opacity(revealsIcon ? (iconVisible ? 1 : 0) : 1)
                .scaleEffect(!reduceMotion && revealsIcon && !iconVisible ? 0.88 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: iconVisible)
                .task {
                    guard revealsIcon else { return }
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                    iconVisible = true
                }

            VStack(alignment: .leading, spacing: TalosOnboarding.contentGap) {
                VStack(alignment: .leading, spacing: TalosOnboarding.titleGap) {
                    Text(title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(.primary)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
        }
    }
}

enum TalosOnboarding {
    static let windowWidth: CGFloat = 600
    static let windowHeight: CGFloat = 600
    static let titleBarInset: CGFloat = 32
    static var contentHeight: CGFloat {
        windowHeight - titleBarInset
    }

    static let wrapperWidth: CGFloat = 400
    static let wrapperTop: CGFloat = 64
    static var wrapperTopPadding: CGFloat {
        wrapperTop - titleBarInset
    }

    static let iconGap: CGFloat = 32
    static let titleGap: CGFloat = 1
    static let contentGap: CGFloat = 18
    static let wrapperToButtons: CGFloat = 16
    static let iconSize: CGFloat = 64
    static let margin: CGFloat = 21
    static let bottomMargin: CGFloat = 19
    static let buttonWidth: CGFloat = 132
    static let buttonHeight: CGFloat = 38
    static let buttonGap: CGFloat = 8
    static let featureIconBox: CGFloat = 32
    static let featureGap: CGFloat = 16
}
