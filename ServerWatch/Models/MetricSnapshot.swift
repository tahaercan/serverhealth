import Foundation
import SwiftData

@Model
final class MetricSnapshot {
    @Attribute(.unique) var id: UUID
    var server: Server?
    var checkTypeRaw: String
    var value: Double
    var recordedAt: Date

    var checkType: CheckType {
        get { CheckType(rawValue: checkTypeRaw) ?? .custom }
        set { checkTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        server: Server,
        checkType: CheckType,
        value: Double,
        recordedAt: Date = .now
    ) {
        self.id = id
        self.server = server
        self.checkTypeRaw = checkType.rawValue
        self.value = value
        self.recordedAt = recordedAt
    }
}
