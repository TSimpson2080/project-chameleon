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

@MainActor
public enum MoneyFormatting {
    private static let currencyUSDFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    private static let decimalFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        return formatter
    }()

    public static func currencyUSD(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: Money.round(value))
        return currencyUSDFormatter.string(from: number) ?? "\(number)"
    }

    public static func decimal(_ value: Decimal, minFractionDigits: Int = 0, maxFractionDigits: Int = 2) -> String {
        let number = NSDecimalNumber(decimal: Money.round(value))
        decimalFormatter.minimumFractionDigits = minFractionDigits
        decimalFormatter.maximumFractionDigits = maxFractionDigits
        return decimalFormatter.string(from: number) ?? "\(number)"
    }

    /// Formats a tax rate as a percent (e.g. 0.0825 -> "8.25%").
    public static func taxRatePercent(_ rate: Decimal) -> String {
        let percent = Money.round(Money.clampTaxRate(rate) * 100, scale: 2)
        return "\(decimal(percent, minFractionDigits: 0, maxFractionDigits: 2))%"
    }
}
