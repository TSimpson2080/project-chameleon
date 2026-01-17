import Foundation

public struct PricingBreakdown: Equatable {
    public let subtotal: Decimal
    public let tax: Decimal
    public let total: Decimal

    public init(subtotal: Decimal, tax: Decimal, total: Decimal) {
        self.subtotal = subtotal
        self.tax = tax
        self.total = total
    }
}

public enum PricingCalculator {
    public static func calculate(
        lineItems: [LineItemModel],
        taxRate: Decimal,
        hourlyRate: Decimal? = nil,
        laborHours: Decimal? = nil
    ) -> PricingBreakdown {
        let clampedTaxRate = Money.clampTaxRate(taxRate)

        let lineItemsSubtotal = lineItems
            .map { item in
                let quantity = Money.nonNegative(item.quantity)
                let unitPrice = Money.nonNegative(item.unitPrice)
                return Money.round(quantity * unitPrice)
            }
            .reduce(0, +)

        let laborSubtotal: Decimal = {
            guard let hourlyRate, let laborHours else { return 0 }
            let safeRate = Money.nonNegative(hourlyRate)
            let safeHours = Money.nonNegative(laborHours)
            return Money.round(safeRate * safeHours)
        }()

        let rawSubtotal = lineItemsSubtotal + laborSubtotal
        let subtotal = Money.round(Money.nonNegative(rawSubtotal))

        let tax = Money.round(subtotal * clampedTaxRate)
        let total = Money.round(subtotal + tax)

        return PricingBreakdown(subtotal: subtotal, tax: tax, total: total)
    }
}

