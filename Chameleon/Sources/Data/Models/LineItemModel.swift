import Foundation
import SwiftData

@Model
public final class LineItemModel {
    @Attribute(.unique)
    public var id: UUID
    public var changeOrder: ChangeOrderModel?

    public var createdAt: Date
    public var updatedAt: Date

    public var name: String
    public var details: String?
    public var category: LineItemCategory
    public var quantity: Decimal
    public var unitPrice: Decimal
    public var unit: String?
    public var sortIndex: Int

    public init(
        id: UUID = UUID(),
        changeOrder: ChangeOrderModel? = nil,
        name: String,
        details: String? = nil,
        category: LineItemCategory = .other,
        quantity: Decimal = 1,
        unitPrice: Decimal = 0,
        unit: String? = nil,
        sortIndex: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.changeOrder = changeOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.name = name
        self.details = details
        self.category = category
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.unit = unit
        self.sortIndex = sortIndex
    }

    public func touchUpdatedAt(now: Date = Date()) {
        updatedAt = now
    }

    public var lineTotal: Decimal {
        quantity * unitPrice
    }
}

extension LineItemModel: Identifiable {}
