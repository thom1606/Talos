import SwiftUI

struct RepositoryRow: View {
    let repository: RepositoryPresentation
    let onRefresh: () -> Void
    let onUpdate: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(repository.name)
                    .font(.body.weight(.medium))

                Text(repository.status.instruction(for: repository))
                    .font(.callout)
                    .foregroundStyle(repository.status.subtitleTint)
                    .lineLimit(1)
            }

            Spacer(minLength: 16)

            Menu {
                if repository.status == .updateAvailable {
                    Button("Update", systemImage: "arrow.down.circle", action: onUpdate)
                } else {
                    Button("Check for updates", systemImage: "arrow.clockwise", action: onRefresh)
                }
                Divider()
                Button("Remove", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Repository actions")
            .help("Repository actions")
            .fixedSize()
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        if repository.status.isProgressing {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel(repository.status.title)
        } else {
            Image(systemName: repository.status.symbolName(for: repository.kind))
                .foregroundStyle(repository.status.tint)
                .accessibilityLabel(repository.status.title)
        }
    }
}
