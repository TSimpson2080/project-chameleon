import Foundation
import SwiftData

@MainActor
public final class AuditLogger {
    public enum AuditError: Error {
        case invalidMetadata
    }

    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    public func record(
        action: AuditAction,
        entityType: AuditEntityType,
        entityId: UUID,
        actor: String? = "local",
        metadata: [String: Any] = [:],
        now: Date = Date(),
        save: Bool = true
    ) throws -> AuditEventModel {
        let normalized = normalize(metadata)
        guard JSONSerialization.isValidJSONObject(normalized) else { throw AuditError.invalidMetadata }

        let data = try JSONSerialization.data(withJSONObject: normalized, options: [.sortedKeys])
        let json = String(data: data, encoding: .utf8) ?? "{}"

        let event = AuditEventModel(
            createdAt: now,
            actor: actor,
            action: action,
            entityType: entityType,
            entityId: entityId,
            metadataJSON: json
        )

        modelContext.insert(event)
        if save {
            try modelContext.save()
        }
        return event
    }

    private func normalize(_ value: Any) -> Any {
        switch value {
        case let uuid as UUID:
            return uuid.uuidString
        case let date as Date:
            return AuditLogger.iso8601.string(from: date)
        case let decimal as Decimal:
            return NSDecimalNumber(decimal: decimal).stringValue
        case let number as NSNumber:
            return number
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case let array as [Any]:
            return array.map(normalize(_:))
        case let dict as [String: Any]:
            var normalized: [String: Any] = [:]
            normalized.reserveCapacity(dict.count)
            for (key, val) in dict {
                normalized[key] = normalize(val)
            }
            return normalized
        default:
            return String(describing: value)
        }
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}
