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
        formatChangeOrderNumber(prefix: "CO", number: value)
    }

    public static func customerPrefix(for job: JobModel) -> String {
        let trimmed = job.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
        let last = parts.last.map(String.init) ?? ""

        let allowed = CharacterSet.alphanumerics
        let cleanedScalars = last.unicodeScalars.filter { allowed.contains($0) || $0 == "-" }
        let cleaned = String(String.UnicodeScalarView(cleanedScalars))
        return cleaned.isEmpty ? "CO" : cleaned
    }

    public static func formatChangeOrderNumber(prefix: String, number: Int) -> String {
        let safePrefix = prefix.isEmpty ? "CO" : prefix
        return "\(safePrefix)-" + String(format: "%04d", max(number, 0))
    }

    public static func formatChangeOrderDisplay(job: JobModel, number: Int) -> String {
        let prefix = customerPrefix(for: job)
        return formatChangeOrderNumber(prefix: prefix, number: number)
    }

    public static func formatDisplayNumber(number: Int, revisionNumber: Int) -> String {
        let base = formatChangeOrderNumber(number)
        guard revisionNumber > 0 else { return base }
        return "\(base) Rev \(revisionNumber)"
    }

    public static func formatDisplayNumber(job: JobModel, number: Int, revisionNumber: Int) -> String {
        let base = formatChangeOrderDisplay(job: job, number: number)
        guard revisionNumber > 0 else { return base }
        return "\(base) Rev \(revisionNumber)"
    }

    public static func parseChangeOrderNumber(_ text: String) -> Int? {
        guard text.hasPrefix("CO-") else { return nil }
        let suffix = text.dropFirst(3)
        let digits = suffix.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits) else { return nil }
        return value >= 1 ? value : nil
    }
}
