import Foundation
import UIKit

public final class HangDiagnostics {
    public struct Configuration: Sendable {
        public var stallThresholdSeconds: TimeInterval
        public var pollIntervalSeconds: TimeInterval

        public init(stallThresholdSeconds: TimeInterval = 2.0, pollIntervalSeconds: TimeInterval = 0.25) {
            self.stallThresholdSeconds = stallThresholdSeconds
            self.pollIntervalSeconds = pollIntervalSeconds
        }
    }

    public static let shared = HangDiagnostics()

    private let lock = NSLock()
    private var configuration = Configuration()

    private var pollTimer: DispatchSourceTimer?
    private var isRunning = false
    private var isActive = true

    private var lastMainAck = Date()
    private var lastMainAckSequence: UInt64 = 0
    private var lastProbeSequence: UInt64 = 0

    private var lastHangReportAt: Date?
    private var currentScreen: String?

    private init() {}

    public static func isEnabled() -> Bool {
        #if DEBUG
        return true
        #else
        if UserDefaults.standard.bool(forKey: "EnableHangDiagnostics") { return true }
        if let value = Bundle.main.object(forInfoDictionaryKey: "EnableHangDiagnostics") as? Bool, value { return true }
        return false
        #endif
    }

    public func startIfEnabled(configuration: Configuration = Configuration()) {
        guard Self.isEnabled() else { return }
        start(configuration: configuration)
    }

    public func start(configuration: Configuration) {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return }
        isRunning = true
        self.configuration = configuration
        lastMainAck = Date()
        lastMainAckSequence = 0
        lastProbeSequence = 0

        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        isActive = (UIApplication.shared.applicationState == .active)

        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.tsimpson.chameleon.hangwatchdog", qos: .utility))
        timer.schedule(deadline: .now() + configuration.pollIntervalSeconds, repeating: configuration.pollIntervalSeconds)
        timer.setEventHandler { [weak self] in
            self?.tick()
        }
        timer.resume()
        pollTimer = timer

        AppLog.shared.log("HangDiagnostics started threshold=\(configuration.stallThresholdSeconds)s poll=\(configuration.pollIntervalSeconds)s")
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        isRunning = false

        pollTimer?.cancel()
        pollTimer = nil

        NotificationCenter.default.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)

        AppLog.shared.log("HangDiagnostics stopped")
    }

    public func refreshEnabledState() {
        if Self.isEnabled() {
            startIfEnabled(configuration: configuration)
        } else {
            stop()
        }
    }

    @MainActor
    public func setCurrentScreen(_ name: String) {
        lock.lock()
        currentScreen = name
        lock.unlock()
    }

    private func tick() {
        let (shouldCheck, threshold) = lock.withLock {
            (isActive, configuration.stallThresholdSeconds)
        }
        guard shouldCheck else { return }

        let sequence = lock.withLock {
            lastProbeSequence &+= 1
            return lastProbeSequence
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.withLock {
                self.lastMainAck = Date()
                self.lastMainAckSequence = sequence
            }
        }

        let (lastAck, lastHangAt) = lock.withLock { (lastMainAck, lastHangReportAt) }
        let stall = Date().timeIntervalSince(lastAck)

        guard stall >= threshold else { return }
        if let lastHangAt, Date().timeIntervalSince(lastHangAt) < max(5.0, threshold) { return }

        generateHangReport(stallSeconds: stall)
    }

    private func generateHangReport(stallSeconds: TimeInterval) {
        let now = Date()
        let (screen, ackSeq, probeSeq) = lock.withLock {
            lastHangReportAt = now
            return (currentScreen, lastMainAckSequence, lastProbeSequence)
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let bundleId = Bundle.main.bundleIdentifier ?? "?"

        var report: [String] = []
        report.append("Chameleon Hang Report")
        report.append("Timestamp: \(Self.fileTimestampFormatter.string(from: now))")
        report.append("Bundle: \(bundleId)")
        report.append("Version: \(version) (\(build))")
        report.append("StallSeconds: \(String(format: "%.3f", stallSeconds))")
        report.append("MainAckSequence: \(ackSeq) LastProbeSequence: \(probeSeq)")
        report.append("Screen: \(screen ?? "<unknown>")")
        report.append("")
        report.append("WatchdogThread CallStack:")
        report.append(contentsOf: Thread.callStackSymbols)
        report.append("")
        report.append("Notes: Full thread backtraces are not available without a crash reporter dependency. Use Scripts/capture_sim_hang.sh for simulator sampling.")
        report.append("")

        let logs = AppLog.shared.tail(200)
        if !logs.isEmpty {
            report.append("Last 200 AppLog lines:")
            report.append(contentsOf: logs)
            report.append("")
        }

        let text = report.joined(separator: "\n")
        AppLog.shared.log("HangDiagnostics detected stall \(String(format: "%.3f", stallSeconds))s screen=\(screen ?? "<unknown>")")

        do {
            let hangURL = try hangReportURL(date: now)
            try FileManager.default.createDirectory(at: hangURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try text.write(to: hangURL, atomically: true, encoding: .utf8)
            AppLog.shared.log("HangDiagnostics wrote report: \(hangURL.path)")
        } catch {
            AppLog.shared.log("HangDiagnostics failed to write report: \(error)")
        }
    }

    public func exportHangReportsZip() throws -> URL? {
        let fileManager = FileManager.default
        let hangsDir = try hangsDirectoryURL(fileManager: fileManager)
        guard fileManager.fileExists(atPath: hangsDir.path) else { return nil }

        let tmpZip = fileManager.temporaryDirectory.appendingPathComponent("hang-reports-\(Self.fileTimestampFormatter.string(from: Date())).zip")
        if fileManager.fileExists(atPath: tmpZip.path) {
            try fileManager.removeItem(at: tmpZip)
        }
        try ZipWriter.createZip(fromDirectory: hangsDir, to: tmpZip)
        return tmpZip
    }

    #if DEBUG
    @MainActor
    public func simulateHang(seconds: TimeInterval = 3.0) {
        AppLog.shared.log("SimulateHang starting \(seconds)s on main thread")
        Thread.sleep(forTimeInterval: seconds)
        AppLog.shared.log("SimulateHang finished")
    }
    #endif

    @objc private func didBecomeActive() {
        lock.withLock { isActive = true }
    }

    @objc private func willResignActive() {
        lock.withLock { isActive = false }
    }

    private func hangsDirectoryURL(fileManager: FileManager) throws -> URL {
        let base = try ApplicationSupportLocator.baseURL(fileManager: fileManager)
        return base.appendingPathComponent("Hangs", isDirectory: true)
    }

    private func hangReportURL(date: Date) throws -> URL {
        let dir = try hangsDirectoryURL(fileManager: .default)
        let name = "hang-\(Self.fileTimestampFormatter.string(from: date)).txt"
        return dir.appendingPathComponent(name)
    }

    private static let fileTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private extension NSLock {
    func withLock<T>(_ work: () -> T) -> T {
        lock()
        defer { unlock() }
        return work()
    }
}
