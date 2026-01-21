import SwiftUI

public struct SettingsView: View {
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
            }
        }
        .navigationTitle("Settings")
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Chameleon"
    }

    private var versionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(version) (\(build))"
    }
}
