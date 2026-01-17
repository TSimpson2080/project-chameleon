import Foundation
import SwiftData

@Model
public final class AttachmentModel {
    @Attribute(.unique)
    public var id: UUID
    public var changeOrder: ChangeOrderModel?

    public var type: AttachmentType
    public var filePath: String
    public var thumbnailPath: String?
    public var caption: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        changeOrder: ChangeOrderModel? = nil,
        type: AttachmentType,
        filePath: String,
        thumbnailPath: String? = nil,
        caption: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.changeOrder = changeOrder
        self.type = type
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.caption = caption
        self.createdAt = createdAt
    }
}
