import SwiftUI
import UniformTypeIdentifiers

struct RepositoriesView: View {
    @Bindable var model: RepositoriesModel

    var body: some View {
        Group {
            if model.repositories.isEmpty {
                ContentUnavailableView(
                    "No repositories",
                    systemImage: "shippingbox",
                    description: Text(
                        "Import an extension or link a local project to get started."
                    )
                )
            } else {
                Form {
                    Section {
                        ForEach(model.repositories) { repository in
                            repositoryRow(repository)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Refresh repositories", systemImage: "arrow.clockwise") {
                    model.refreshRepositories()
                }

                Menu("Add repository", systemImage: "plus") {
                    Button("Import .talos…", systemImage: "shippingbox") {
                        model.showsPackageImporter = true
                    }
                    Button("Link local project…", systemImage: "folder") {
                        model.showsProjectImporter = true
                    }
                    Button("Add GitHub repository…", systemImage: "network") {
                        model.showsGitHubForm = true
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $model.showsPackageImporter,
            allowedContentTypes: [.talosPackage],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            model.addImportedPackage(url)
        }
        .fileImporter(
            isPresented: $model.showsProjectImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            do {
                try model.addLocalProject(url)
            } catch {
                model.present(error)
            }
        }
        .sheet(isPresented: $model.showsGitHubForm) {
            AddGitHubRepositoryView { url, token in
                try await model.addGitHubRepository(url, token: token)
            }
        }
        .alert(item: $model.presentedError) { error in
            Alert(
                title: Text("Repository operation failed"),
                message: Text(error.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private func repositoryRow(_ repository: RepositoryPresentation) -> some View {
        RepositoryRow(
            repository: repository,
            onRefresh: {
                model.refreshRepository(id: repository.id)
            },
            onUpdate: {
                guard repository.status == .updateAvailable else { return }
                model.updateRepository(id: repository.id)
            },
            onRemove: {
                model.removeRepository(id: repository.id)
            }
        )
    }
}

private extension UTType {
    static let talosPackage = UTType(
        exportedAs: "com.thom1606.talos.extension",
        conformingTo: .zip
    )
}
