import SwiftUI
import SwiftData

@main
struct ChameleonApp: App {
    init() {
        HangDiagnostics.shared.startIfEnabled()
    }

    var body: some Scene {
        WindowGroup {
            ModelContainerBootstrapView()
        }
    }
}
