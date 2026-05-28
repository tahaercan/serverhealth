import Foundation
import SwiftData

@Model
final class Server {
    @Attribute(.unique) var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    /// Keychain'deki private key referansı (UUID string).
    var keychainKeyId: String
    var isActive: Bool
    var lastCheckedAt: Date?
    var lastError: String?
    var createdAt: Date

    /// SHA-256 fingerprint of the server's SSH host key, in the format
    /// `SHA256:<base64-no-padding>` — same shape as `ssh-keygen -l` output.
    ///
    /// Captured on the first successful connection (TOFU — Trust On First
    /// Use). On every subsequent connection, SSHService verifies the live
    /// host key against this value; a mismatch throws
    /// `SSHServiceError.hostKeyMismatch` instead of letting the user
    /// unknowingly talk to a different host.
    ///
    /// Nil means "we haven't seen this server's key yet" — the next
    /// successful connection will populate it. Existing servers from before
    /// this field existed will be in the nil state and will fingerprint on
    /// their next monitoring cycle (lenient TOFU).
    ///
    /// **Inline default is required for SwiftData lightweight migration** —
    /// existing rows in the store don't have this column.
    var hostKeyFingerprint: String? = nil

    @Relationship(deleteRule: .cascade, inverse: \MonitoringRule.server)
    var rules: [MonitoringRule] = []

    @Relationship(deleteRule: .cascade, inverse: \MetricSnapshot.server)
    var snapshots: [MetricSnapshot] = []

    @Relationship(deleteRule: .cascade, inverse: \LogEntry.server)
    var logs: [LogEntry] = []

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int = 22,
        username: String,
        keychainKeyId: String,
        isActive: Bool = true,
        lastCheckedAt: Date? = nil,
        lastError: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.keychainKeyId = keychainKeyId
        self.isActive = isActive
        self.lastCheckedAt = lastCheckedAt
        self.lastError = lastError
        self.createdAt = createdAt
    }
}
