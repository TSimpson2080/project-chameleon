import SwiftUI

public struct SettingsView: View {
    private struct SharePayload: Identifiable {
        let id = UUID()
        let url: URL
    }

    @AppStorage("DiagnosticsToolsUnlocked") private var diagnosticsToolsUnlocked = false
    @AppStorage("EnableHangDiagnostics") private var enableHangDiagnostics = false

    @State private var sharePayload: SharePayload?
    @State private var alertMessage: String?

    public init() {}

    public var body: some View {
        List {
            Section("Company") {
                NavigationLink("Company Profile") {
                    CompanyProfileEditView()
                }
            }

            Section("About") {
                LabeledContent("App") {
                    Text(appName)
                }

                LabeledContent("Version") {
                    Text(versionString)
                        .monospacedDigit()
                }
                .onLongPressGesture(minimumDuration: 1.0) {
                    diagnosticsToolsUnlocked.toggle()
                }
            }

            if diagnosticsToolsUnlocked || HangDiagnostics.isEnabled() {
                Section("Diagnostics") {
                    Toggle("Enable Hang Diagnostics", isOn: $enableHangDiagnostics)
                        .onChange(of: enableHangDiagnostics) { _, _ in
                            HangDiagnostics.shared.refreshEnabledState()
                        }

                    Button("Export Hang Reports") { exportHangReports() }

                    #if DEBUG
                    Button("Simulate Hang (3s)") {
                        Task { @MainActor in
                            HangDiagnostics.shared.simulateHang(seconds: 3.0)
                        }
                    }
                    #endif
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            Task { @MainActor in
                HangDiagnostics.shared.setCurrentScreen("Settings")
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: [payload.url])
        }
        .alert("Diagnostics", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "ReScope"
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }

    private func exportHangReports() {
        do {
            let url = try HangDiagnostics.shared.exportHangReportsZip()
            guard let url else {
                alertMessage = "No hang reports found."
                return
            }
            sharePayload = SharePayload(url: url)
        } catch {
            alertMessage = "Could not export hang reports."
        }
    }
}
