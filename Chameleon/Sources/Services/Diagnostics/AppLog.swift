import Foundation

public final class AppLog {
    public static let shared = AppLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private let maxLines = 2000

    private init() {}

    public func log(_ message: String) {
        let timestamp = AppLog.timestampFormatter.string(from: Date())
        let line = "\(timestamp) \(message)"
        print(line)

        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    public func tail(_ count: Int) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        guard count > 0 else { return [] }
        return Array(lines.suffix(count))
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}

