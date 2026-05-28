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
