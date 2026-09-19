import SwiftUI

struct RepositoryEditor: View {
    let model: ModuleLibraryModel
    var source: RepositorySource?
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var token = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(LocalizedStringKey(source == nil ? "Add repository" : "Repository credentials")).font(.title2.weight(.semibold))
            if let source { Text(source.slug).foregroundStyle(.secondary) }
            else {
                TextField("https://github.com/owner/repository", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("repository.url")
            }
            SecureField("GitHub token (optional for public repositories)", text: $token)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("repository.token")
            Text("For private repositories, use a fine-grained token with read access to repository Contents. Tokens are stored in Keychain. Leave blank to use public access.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = model.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("repository.cancel")
                Spacer()
                Button(LocalizedStringKey(source == nil ? "Add" : "Save")) {
                    Task {
                        if let source { await model.setToken(token, source: source) }
                        else { await model.addRepository(url: url, token: token) }
                        if model.error == nil { token = ""; dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(model.isBusy || source == nil && url.isEmpty)
                .accessibilityIdentifier("repository.save")
            }
        }.padding(24).frame(width: 440)
    }
}
