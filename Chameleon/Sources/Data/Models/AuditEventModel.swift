import Foundation
import SwiftData

@Model
public final class AuditEventModel {
    @Attribute(.unique)
    public var id: UUID

    public var createdAt: Date
    public var actor: String?

    public var action: AuditAction
    public var entityType: AuditEntityType
    public var entityId: UUID

    public var metadataJSON: String

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        actor: String? = "local",
        action: AuditAction,
        entityType: AuditEntityType,
        entityId: UUID,
        metadataJSON: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.actor = actor
        self.action = action
        self.entityType = entityType
        self.entityId = entityId
        self.metadataJSON = metadataJSON
    }
}

