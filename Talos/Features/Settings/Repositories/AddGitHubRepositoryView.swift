import SwiftUI

struct AddGitHubRepositoryView: View {
    let onAdd: (String, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var repositoryURL = ""
    @State private var token = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var submission: Task<Void, Never>?

    private var trimmedURL: String {
        repositoryURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Repository URL") {
                        TextField(
                            "Repository URL",
                            text: $repositoryURL,
                            prompt: Text(verbatim: "https://github.com/owner/repository")
                        )
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("repository.url")
                    }

                    SecureField("Personal access token", text: $token, prompt: Text("Optional"))
                        .accessibilityIdentifier("repository.token")
                        .multilineTextAlignment(.trailing)
                } footer: {
                    Text("For private repositories, use a fine-grained token with Contents: Read permission for this repository. The token is stored in Keychain.")
                }
                .disabled(isAdding)

                if isAdding {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Downloading and installing the latest release…")
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add GitHub Repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        submission?.cancel()
                        token = ""
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        isAdding = true
                        errorMessage = nil
                        submission = Task {
                            defer { isAdding = false }
                            do {
                                try await onAdd(trimmedURL, token)
                                token = ""
                                dismiss()
                            } catch is CancellationError {
                                // Cancelling the sheet also cancels network and extraction work.
                            } catch {
                                errorMessage = (error as? GitHubRepositoryError)?.localizedDescription
                                    ?? "Couldn’t add this repository. Please try again."
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isAdding || (try? GitHubRepositoryReference(trimmedURL)) == nil)
                }
            }
        }
        .frame(minWidth: 540, minHeight: 290)
        .interactiveDismissDisabled(isAdding)
        .onDisappear {
            submission?.cancel()
            token = ""
        }
    }
}
