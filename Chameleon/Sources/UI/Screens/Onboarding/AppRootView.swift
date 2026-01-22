import SwiftUI
import SwiftData

public struct AppRootView: View {
    @AppStorage("didSkipCompanyOnboarding") private var didSkipCompanyOnboarding = false

    @Query private var companyProfiles: [CompanyProfileModel]
    @State private var isPresentingOnboarding = false

    public init() {}

    public var body: some View {
        JobListView()
            .safeAreaInset(edge: .top) {
                if needsCompanyProfile, !isPresentingOnboarding {
                    CompanyProfileSetupBanner(
                        onSetUpNow: {
                            didSkipCompanyOnboarding = false
                            isPresentingOnboarding = true
                        },
                        onDismiss: {
                            didSkipCompanyOnboarding = true
                        }
                    )
                }
            }
            .fullScreenCover(isPresented: $isPresentingOnboarding) {
                OnboardingFlowView()
            }
            .onAppear {
                HangDiagnostics.shared.startIfEnabled()
                updatePresentation()
            }
            .onChange(of: needsCompanyProfile) { _, _ in updatePresentation() }
            .onChange(of: didSkipCompanyOnboarding) { _, _ in updatePresentation() }
    }

    private var needsCompanyProfile: Bool {
        guard let profile = companyProfiles.first else { return true }
        return profile.companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func updatePresentation() {
        isPresentingOnboarding = needsCompanyProfile && !didSkipCompanyOnboarding
    }
}

private struct CompanyProfileSetupBanner: View {
    let onSetUpNow: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "building.2")
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text("Finish company setup")
                    .font(.subheadline.weight(.semibold))
                Text("Add company name and defaults for PDFs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Set Up") { onSetUpNow() }
                .buttonStyle(.borderedProminent)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
