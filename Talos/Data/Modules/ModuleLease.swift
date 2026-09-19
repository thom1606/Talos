import Foundation
import Darwin

// Advisory locks are released by the kernel if either app exits or crashes.
nonisolated final class ModuleLease: Sendable {
    private let descriptor: Int32
    init(_ module: InstalledModule, exclusive: Bool = false) throws {
        let path = module.directory.appendingPathComponent(".talos-lease").path
        let fd = open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw ManifestError.invalid("Cannot access module lease") }
        guard flock(fd, (exclusive ? LOCK_EX : LOCK_SH) | LOCK_NB) == 0 else {
            close(fd)
            throw ManifestError.invalid("This module has a running task")
        }
        descriptor = fd
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
    static func isInUse(_ module: InstalledModule) -> Bool {
        do { let lease = try ModuleLease(module, exclusive: true); withExtendedLifetime(lease) {}; return false }
        catch { return true }
    }
}
