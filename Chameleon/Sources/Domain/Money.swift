import Foundation

public enum Money {
    public static let scale: Int = 2

    public static func round(_ value: Decimal, scale: Int = Money.scale) -> Decimal {
        var input = value
        var output = Decimal()
        NSDecimalRound(&output, &input, scale, .plain)
        return output
    }

    public static func nonNegative(_ value: Decimal) -> Decimal {
        max(value, 0)
    }

    public static func clampTaxRate(_ value: Decimal) -> Decimal {
        min(max(value, 0), 1)
    }
}
