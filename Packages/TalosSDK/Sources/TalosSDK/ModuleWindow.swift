import SwiftUI

/// A module supplies the label, availability and behavior of its footer action.
public struct ModuleWindowAction {
    public let title: String
    public var isEnabled: Bool
    public let perform: @MainActor () -> Void

    public init(_ title: String, isEnabled: Bool = true, perform: @escaping @MainActor () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.perform = perform
    }
}

/// Shared compact chrome; modules supply arbitrary native SwiftUI content inside it.
public struct ModuleWindow<Content: View>: View {
    private let title: String
    private let close: @MainActor () -> Void
    private let primaryAction: ModuleWindowAction?
    private let secondaryAction: ModuleWindowAction?
    private let content: Content
    private let accent = Color(red: 236 / 255, green: 48 / 255, blue: 19 / 255)

    public init(_ title: String, close: @escaping @MainActor () -> Void,
                primaryAction: ModuleWindowAction? = nil, secondaryAction: ModuleWindowAction? = nil,
                @ViewBuilder content: () -> Content) {
        self.title = title
        self.close = close
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    .padding(.horizontal, 48)
                HStack {
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 24, height: 24)
                            .background(.primary.opacity(0.06), in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain).accessibilityLabel("Close")
                    .help("Close")
                    Spacer()
                }.padding(.horizontal, 12)
            }.frame(height: 40)
            Divider()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollContentBackground(.hidden)
            if primaryAction != nil || secondaryAction != nil {
                Divider()
                HStack(spacing: 10) {
                    if let secondaryAction {
                        Button(secondaryAction.title, action: secondaryAction.perform)
                            .buttonStyle(.bordered).tint(.secondary)
                            .disabled(!secondaryAction.isEnabled)
                    }
                    Spacer()
                    if let primaryAction {
                        Button(primaryAction.title, action: primaryAction.perform)
                            .buttonStyle(.borderedProminent).tint(accent)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!primaryAction.isEnabled)
                    }
                }
                .controlSize(.regular)
                .padding(.horizontal, 16).frame(height: 52)
            }
        }
        .tint(accent)
        .background(.regularMaterial)
        .ignoresSafeArea(.container, edges: .top)
    }
}
