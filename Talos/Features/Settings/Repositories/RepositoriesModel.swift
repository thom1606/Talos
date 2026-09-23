import Foundation
import Observation

@MainActor
@Observable
final class RepositoriesModel {
    private(set) var repositories: [RepositoryPresentation] = []
    private(set) var tiles: [WheelTilePresentation] = []
    var presentedError: RepositoryPresentationError?
    var showsPackageImporter = false
    var showsProjectImporter = false
    var showsGitHubForm = false

    @ObservationIgnored let updateMonitor: RepositoryUpdateMonitor
    @ObservationIgnored private let githubStore: GitHubRepositoryStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let extensionsDidChange: () -> Void
    @ObservationIgnored private var localProjects: [LocalProjectLink]

    convenience init(notifications: NotificationService, extensionsDidChange: @escaping () -> Void = {}) {
        self.init(
            defaults: TalosPreferences.defaults,
            notifications: notifications,
            extensionsDidChange: extensionsDidChange
        )
    }

    init(
        defaults: UserDefaults,
        notifications: NotificationService,
        extensionsDidChange: @escaping () -> Void = {}
    ) {
        self.defaults = defaults
        let store = GitHubRepositoryStore(defaults: defaults)
        githubStore = store
        updateMonitor = RepositoryUpdateMonitor(defaults: defaults,
            installed: { GitHubRepositoryStore.installed(in: defaults) },
            fetch: { try await store.latestRelease(for: $0) },
            notify: { try await notifications.postRepositoryUpdate($0) },
            dismissNotification: { notifications.dismissRepositoryUpdate($0) })
        self.extensionsDidChange = extensionsDidChange
        localProjects = LocalProjectLinkStore.load(from: defaults)
        reloadPresentations()
        updateMonitor.willCheck = { [weak self] id in self?.setStatus(.fetching, for: id) }
        updateMonitor.didCheck = { [weak self] id, result, manually in
            guard let self, repositories.first(where: { $0.id == id })?.status != .installing else { return }
            switch result {
            case .success:
                setStatus(.running, for: id)
                reloadPresentations(preservingOperations: true)
            case let .failure(error):
                if manually {
                    setStatus(.running, for: id)
                    reloadPresentations(preservingOperations: true)
                    presentGitHubError(error)
                }
            }
        }
    }

    func refreshRepositories() {
        reloadPresentations(preservingOperations: true)
        extensionsDidChange()
        for link in GitHubRepositoryStore.installed(in: defaults) {
            refreshRepository(id: link.id)
        }
    }

    private var bundledTiles: [WheelTilePresentation] = []
    func updateBundledExtensions(_ extensions: [LoadedExtension]) {
        bundledTiles = extensions.filter(\.isBundled).flatMap { loaded in
            guard let package = try? LocalProjectPackage.read(from: loaded.directory) else { return [WheelTilePresentation]() }
            return package.wheelTiles(extensionName: package.displayName(in: loaded.directory))
        }
        reloadPresentations(preservingOperations: true)
    }

    private func reloadPresentations(preservingOperations: Bool = false) {
        let operations = preservingOperations ? repositories.filter { $0.status.isProgressing } : []
        updateMonitor.reconcile()
        var presentations: [RepositoryPresentation] = []
        var availableTiles: [WheelTilePresentation] = []
        var didRefreshBookmark = false

        for index in localProjects.indices {
            let link = localProjects[index]
            var isStale = false

            guard let projectURL = try? URL(
                resolvingBookmarkData: link.bookmark,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                presentations.append(link.unavailablePresentation)
                continue
            }

            let isAccessing = projectURL.startAccessingSecurityScopedResource()
            defer {
                if isAccessing {
                    projectURL.stopAccessingSecurityScopedResource()
                }
            }

            guard let package = try? LocalProjectPackage.read(from: projectURL) else {
                presentations.append(link.unavailablePresentation)
                continue
            }

            let displayName = package.displayName(in: projectURL)
            localProjects[index] = LocalProjectLink(
                id: package.talos.bundleID,
                bookmark: link.bookmark,
                lastKnownName: displayName,
                lastKnownPath: projectURL.path(percentEncoded: false)
            )

            if isStale,
               let bookmark = try? projectURL.bookmarkData(
                   options: [.withSecurityScope],
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                localProjects[index].bookmark = bookmark
                didRefreshBookmark = true
            }

            let hasBuild = package.hasBuild(in: projectURL)
            presentations.append(
                .init(
                    id: package.talos.bundleID,
                    name: displayName,
                    source: projectURL.path(percentEncoded: false),
                    kind: .localProject,
                    installedVersion: hasBuild ? package.version : nil,
                    status: hasBuild ? .running : .buildRequired
                )
            )
            availableTiles.append(contentsOf: package.wheelTiles(extensionName: displayName))
        }

        for link in GitHubRepositoryStore.installed(in: defaults) {
            let directory = SDKRuntime.defaultExtensionsDirectory.appendingPathComponent(link.extensionID)
            let package = try? LocalProjectPackage.read(from: directory)
            let update = updateMonitor.availableUpdate(for: link)
            presentations.append(.init(
                id: link.id, name: link.repository.fullName,
                source: "https://github.com/\(link.repository.fullName)", kind: .github,
                installedVersion: link.version, availableVersion: update?.version,
                status: package == nil ? .buildRequired : update == nil ? .running : .updateAvailable
            ))
            if let package {
                let localTileIDs = Set(availableTiles.map(\.id))
                availableTiles.append(contentsOf: package.wheelTiles(extensionName: package.displayName(in: directory))
                    .filter { !localTileIDs.contains($0.id) })
            }
        }

        repositories = presentations.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        for operation in operations { setStatus(operation.status, for: operation.id) }
        let existing = Set(availableTiles.map(\.id))
        tiles = (availableTiles + bundledTiles.filter { !existing.contains($0.id) }).sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }

        if didRefreshBookmark {
            saveLocalProjects()
        }
    }

    func addLocalProject(_ url: URL) throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let package = try LocalProjectPackage.read(from: url)
        let bookmark: Data

        do {
            bookmark = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw LocalProjectError.cannotCreateBookmark
        }

        let link = LocalProjectLink(
            id: package.talos.bundleID,
            bookmark: bookmark,
            lastKnownName: package.displayName(in: url),
            lastKnownPath: url.path(percentEncoded: false)
        )
        localProjects.removeAll { $0.id == link.id }
        localProjects.append(link)
        saveLocalProjects()
        reloadPresentations()
        extensionsDidChange()
    }

    func refreshRepository(id: String) {
        if GitHubRepositoryStore.installed(in: defaults).contains(where: { $0.id == id }) {
            guard repositories.first(where: { $0.id == id })?.status.isProgressing != true else { return }
            updateMonitor.check(repositoryID: id, manually: true)
        } else if localProjects.contains(where: { $0.id == id }) {
            reloadPresentations()
            extensionsDidChange()
        }
    }

    func setStatus(_ status: RepositoryPresentation.Status, for id: String) {
        guard let index = repositories.firstIndex(where: { $0.id == id }) else { return }
        repositories[index].status = status
    }

    func updateRepository(id: String) {
        guard let link = GitHubRepositoryStore.installed(in: defaults).first(where: { $0.id == id }),
              repositories.first(where: { $0.id == id })?.status.isProgressing != true else { return }
        updateMonitor.cancelCheck(for: id)
        setStatus(.installing, for: id)
        Task {
            do {
                try await githubStore.install(url: "https://github.com/\(link.repository.fullName)", token: "")
                reloadPresentations()
                extensionsDidChange()
                updateMonitor.checkIfDue()
            } catch {
                setStatus(.updateAvailable, for: id)
                presentGitHubError(error)
            }
        }
    }

    func removeRepository(id: String) {
        if let link = GitHubRepositoryStore.installed(in: defaults).first(where: { $0.id == id }) {
            Task {
                do {
                    try await githubStore.remove(link)
                    reloadPresentations()
                    extensionsDidChange()
                    updateMonitor.checkIfDue()
                } catch {
                    presentGitHubError(error)
                }
            }
            return
        }
        localProjects.removeAll { $0.id == id }
        saveLocalProjects()
        reloadPresentations()
        extensionsDidChange()
    }

    func addImportedPackage(_ url: URL) {
        presentedError = .init(
            message: "Importing \(url.lastPathComponent) will be connected in the package installation step."
        )
    }

    func addGitHubRepository(_ url: String, token: String) async throws {
        do {
            try await githubStore.install(url: url, token: token)
            reloadPresentations()
            extensionsDidChange()
            updateMonitor.checkIfDue()
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as GitHubRepositoryError {
            throw error
        } catch {
            throw GitHubRepositoryError.invalidPackage
        }
    }

    private func presentGitHubError(_ error: Error) {
        presentedError = .init(message: (error as? GitHubRepositoryError)?.localizedDescription
            ?? "Couldn’t finish the GitHub repository operation. Please try again.")
    }

    func present(_ error: Error) {
        presentedError = .init(message: error.localizedDescription)
    }

    private func saveLocalProjects() {
        LocalProjectLinkStore.save(localProjects, to: defaults)
    }
}

struct RepositoryPresentationError: Identifiable {
    let id = UUID()
    let message: String
}

private extension LocalProjectLink {
    var unavailablePresentation: RepositoryPresentation {
        .init(
            id: id,
            name: lastKnownName,
            source: lastKnownPath,
            kind: .localProject,
            status: .buildRequired
        )
    }
}
