import Foundation
import Testing
@testable import Chameleon

struct PricingCalculatorTests {
    private func decimal(_ text: String) -> Decimal {
        Decimal(string: text)!
    }

    @Test func basicLineItemsSubtotalMath() {
        let items = [
            LineItemModel(name: "A", quantity: decimal("2"), unitPrice: decimal("100")),
            LineItemModel(name: "B", quantity: decimal("1"), unitPrice: decimal("50")),
        ]

        let result = PricingCalculator.calculate(lineItems: items, taxRate: 0)
        #expect(result.subtotal == decimal("250.00"))
        #expect(result.total == decimal("250.00"))
    }

    @Test func taxMath() {
        let items = [
            LineItemModel(name: "A", quantity: decimal("1"), unitPrice: decimal("200")),
        ]

        let result = PricingCalculator.calculate(lineItems: items, taxRate: decimal("0.07"))
        #expect(result.subtotal == decimal("200.00"))
        #expect(result.tax == decimal("14.00"))
        #expect(result.total == decimal("214.00"))
    }

    @Test func roundingBehaviorHalfUpToTwoDecimals() {
        let items = [
            LineItemModel(name: "A", quantity: decimal("1"), unitPrice: decimal("0.105")),
        ]

        let result = PricingCalculator.calculate(lineItems: items, taxRate: decimal("0.075"))
        #expect(result.subtotal == decimal("0.11"))
        #expect(result.tax == decimal("0.01"))
        #expect(result.total == decimal("0.12"))
    }
}

