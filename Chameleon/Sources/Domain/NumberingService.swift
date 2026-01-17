import Foundation

public enum NumberingService {
    public static func nextChangeOrderNumber(for job: JobModel, using existingChangeOrders: [ChangeOrderModel]) -> String {
        nextChangeOrderNumber(for: job.id, using: existingChangeOrders)
    }

    public static func nextChangeOrderNumber(for jobId: UUID, using existingChangeOrders: [ChangeOrderModel]) -> String {
        let maxExisting = existingChangeOrders
            .filter { $0.job?.id == jobId }
            .compactMap { $0.number >= 1 ? $0.number : nil }
            .max() ?? 0

        return formatChangeOrderNumber(maxExisting + 1)
    }

    public static func formatChangeOrderNumber(_ value: Int) -> String {
        "CO-" + String(format: "%04d", max(value, 0))
    }

    public static func parseChangeOrderNumber(_ text: String) -> Int? {
        guard text.hasPrefix("CO-") else { return nil }
        let suffix = text.dropFirst(3)
        let digits = suffix.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        return value >= 1 ? value : nil
    }
}

