import Foundation
import SwiftData

@Model
public final class LineItemModel {
    @Attribute(.unique)
    public var id: UUID
    public var changeOrder: ChangeOrderModel?

    public var name: String
    public var quantity: Decimal
    public var unitPrice: Decimal
    public var total: Decimal

    public init(
        id: UUID = UUID(),
        changeOrder: ChangeOrderModel? = nil,
        name: String,
        quantity: Decimal = 1,
        unitPrice: Decimal = 0,
        total: Decimal? = nil
    ) {
        self.id = id
        self.changeOrder = changeOrder
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.total = total ?? (quantity * unitPrice)
    }

    public func recalculateTotal() {
        total = quantity * unitPrice
    }
}
