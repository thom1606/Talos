import Foundation

nonisolated struct HostPreferencesStatus: Codable, Equatable {
    var loginEnabled = false
    var loginNeedsApproval = false
    var error: String?
}
