import Foundation
import OSLog

nonisolated struct RepositoryUpdate: Codable, Sendable, Equatable {
    let repositoryID: String
    let repositoryName: String
    let installedReleaseID: Int64
    let installedAssetID: Int64
    let releaseID: Int64
    let assetID: Int64
    let version: String?

    var fingerprint: String { "\(releaseID):\(assetID)" }
    func applies(to link: InstalledGitHubRepository) -> Bool {
        repositoryID == link.id && installedReleaseID == link.releaseID && installedAssetID == link.assetID
            && (releaseID != link.releaseID || assetID != link.assetID)
    }
}

/// One metadata request per remote per hour. Installed packages continue to run from disk.
@MainActor
final class RepositoryUpdateMonitor {
    private struct Check: Codable {
        var attemptedAt: Date?
        var update: RepositoryUpdate?
        var notified: [String] = []
    }
    private static let storageKey = "repositoryReleaseChecks"
    static let interval: TimeInterval = 60 * 60
    var didCheck: ((String, Result<RepositoryUpdate?, Error>, Bool) -> Void)?
    var willCheck: ((String) -> Void)?
    private let defaults: UserDefaults
    private let installed: () -> [InstalledGitHubRepository]
    private let fetch: (InstalledGitHubRepository) async throws -> GitHubRelease
    private let notify: (RepositoryUpdate) async throws -> Bool
    private let dismissNotification: (String) -> Void
    private let now: () -> Date
    private var checks: [String: Check]
    private var tasks: [String: Task<Void, Never>] = [:]
    private var timer: Timer?
    private var running = false

    init(defaults: UserDefaults,
         installed: @escaping () -> [InstalledGitHubRepository],
         fetch: @escaping (InstalledGitHubRepository) async throws -> GitHubRelease,
         notify: @escaping (RepositoryUpdate) async throws -> Bool,
         dismissNotification: @escaping (String) -> Void = { _ in },
         now: @escaping () -> Date = { .now }) {
        self.defaults = defaults
        self.installed = installed
        self.fetch = fetch
        self.notify = notify
        self.dismissNotification = dismissNotification
        self.now = now
        checks = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: Check].self, from: $0) } ?? [:]
    }

    func availableUpdate(for link: InstalledGitHubRepository) -> RepositoryUpdate? {
        guard let update = checks[link.id]?.update, update.applies(to: link) else { return nil }
        return update
    }

    func start() {
        guard !running else { return }
        running = true
        checkIfDue()
    }

    func cancelCheck(for id: String) { tasks[id]?.cancel() }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    /// Also called after wake and repository changes; the hourly check is always enabled.
    func checkIfDue() {
        reconcile()
        check()
        scheduleNextCheck()
    }

    func check(repositoryID: String? = nil, manually: Bool = false) {
        for link in installed() where repositoryID == nil || repositoryID == link.id {
            guard tasks[link.id] == nil else { continue }
            if !manually, let last = checks[link.id]?.attemptedAt,
               now().timeIntervalSince(last) >= 0, now().timeIntervalSince(last) < Self.interval { continue }
            checks[link.id, default: Check()].attemptedAt = now()
            persist()
            if manually { willCheck?(link.id) }
            tasks[link.id] = Task { [weak self] in
                guard let self else { return }
                defer { tasks[link.id] = nil; scheduleNextCheck() }
                do {
                    let release = try await fetch(link)
                    let asset = try release.packageAsset()
                    try Task.checkCancellation()
                    // Ignore results from a repository removed or updated while the request was in flight.
                    guard isCurrent(link) else { return }
                    let candidate = RepositoryUpdate(repositoryID: link.id, repositoryName: link.repository.fullName,
                        installedReleaseID: link.releaseID, installedAssetID: link.assetID,
                        releaseID: release.id, assetID: asset.id, version: release.tagName)
                    let update = candidate.applies(to: link) ? candidate : nil
                    checks[link.id, default: Check()].update = update
                    persist()
                    didCheck?(link.id, .success(update), manually)
                    if let update, checks[link.id]?.notified.contains(update.fingerprint) != true {
                        do {
                            let accepted = try await notify(update)
                            guard isCurrent(link), !Task.isCancelled else {
                                dismissNotification(link.id)
                                return
                            }
                            if accepted {
                                checks[link.id, default: Check()].notified.append(update.fingerprint)
                                let notified = Array((checks[link.id]?.notified ?? []).suffix(32))
                                checks[link.id]?.notified = notified
                                persist()
                            }
                        } catch {
                            Logger(subsystem: "com.thom1606.Talos", category: "RepositoryUpdates")
                                .error("Could not deliver repository notification: \(error.localizedDescription, privacy: .public)")
                        }
                    } else if update == nil { dismissNotification(link.id) }
                } catch is CancellationError {
                    // Shutdown or repository removal cancelled the request.
                } catch {
                    guard !Task.isCancelled, isCurrent(link) else { return }
                    Logger(subsystem: "com.thom1606.Talos", category: "RepositoryUpdates")
                        .error("Repository update check failed: \(error.localizedDescription, privacy: .public)")
                    didCheck?(link.id, .failure(error), manually)
                }
            }
        }
        scheduleNextCheck()
    }

    /// Forget removed sources and invalidate cached availability after a successful installation.
    func reconcile() {
        let links = installed()
        let ids = Set(links.map(\.id))
        for id in Array(checks.keys) where !ids.contains(id) {
            tasks[id]?.cancel()
            checks[id] = nil
            dismissNotification(id)
        }
        for link in links {
            if let update = checks[link.id]?.update, !update.applies(to: link) {
                checks[link.id]?.update = nil
                dismissNotification(link.id)
            }
        }
        persist()
    }

    private func isCurrent(_ link: InstalledGitHubRepository) -> Bool {
        installed().contains { $0.id == link.id && $0.releaseID == link.releaseID && $0.assetID == link.assetID }
    }

    private func scheduleNextCheck() {
        timer?.invalidate()
        timer = nil
        guard running else { return }
        let dates = installed().filter { tasks[$0.id] == nil }.map {
            (checks[$0.id]?.attemptedAt ?? .distantPast).addingTimeInterval(Self.interval)
        }
        guard let next = dates.min() else { return }
        let timer = Timer(timeInterval: max(1, next.timeIntervalSince(now())), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkIfDue() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(checks) { defaults.set(data, forKey: Self.storageKey) }
    }
}
