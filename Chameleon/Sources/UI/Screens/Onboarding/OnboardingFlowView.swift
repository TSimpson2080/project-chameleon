import PhotosUI
import Foundation
import SwiftUI
import SwiftData
import UIKit

public struct OnboardingFlowView: View {
    private enum Step: Int, CaseIterable {
        case welcome
        case basics
        case logo
        case terms
        case review

        var title: String {
            switch self {
            case .welcome: "Welcome"
            case .basics: "Company"
            case .logo: "Logo"
            case .terms: "Terms"
            case .review: "Review"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("didSkipCompanyOnboarding") private var didSkipCompanyOnboarding = false

    @State private var step: Step = .welcome
    @State private var companyName: String = ""
    @State private var defaultTaxRateText: String = ""
    @State private var defaultTerms: String = ""

    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var selectedLogoImage: UIImage?
    @State private var shouldRemoveLogo: Bool = false

    @State private var isSaving: Bool = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                switch step {
                case .welcome:
                    welcomeStep
                case .basics:
                    basicsStep
                case .logo:
                    logoStep
                case .terms:
                    termsStep
                case .review:
                    reviewStep
                }
            }
            .navigationTitle(step.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if step != .welcome {
                        Button("Back") { goBack() }
                            .disabled(isSaving)
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip for now") {
                        didSkipCompanyOnboarding = true
                        dismiss()
                    }
                    .disabled(isSaving)
                }

                ToolbarItem(placement: .bottomBar) {
                    VStack(spacing: 12) {
                        ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                            .frame(maxWidth: .infinity, alignment: .center)

                        if step == .review {
                            Button(action: save) {
                                Text(isSaving ? "Saving..." : "Save")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .disabled(isSaving || companyNameTrimmed.isEmpty)
                        } else {
                            Button(action: goNext) {
                                Text("Next")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .frame(maxWidth: .infinity)
                            .disabled(isSaving)
                        }
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .task { loadExistingProfileIfPresent() }
            .onChange(of: selectedLogoItem) { _, _ in loadSelectedLogo() }
            .alert(
                "Setup Error",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
    }

    private var welcomeStep: some View {
        Section {
            Text("Set up your company profile to brand PDFs and set defaults like tax rate and terms.")
        }
    }

    private var basicsStep: some View {
        Section("Company") {
            TextField("Company name", text: $companyName)
                .textInputAutocapitalization(.words)

            TextField("Default tax rate (optional)", text: $defaultTaxRateText)
                .keyboardType(.decimalPad)

            Text("Example: 8.25%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var logoStep: some View {
        Section {
            PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                Label("Choose Logo", systemImage: "photo")
            }

            if let image = selectedLogoImage {
                HStack {
                    Spacer()
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 120)
                    Spacer()
                }
            } else {
                Text("Logo is optional.")
                    .foregroundStyle(.secondary)
            }

            if selectedLogoImage != nil || shouldRemoveLogo {
                Button("Remove Logo", role: .destructive) {
                    selectedLogoItem = nil
                    selectedLogoImage = nil
                    shouldRemoveLogo = true
                }
            }
        }
    }

    private var termsStep: some View {
        Section("Default terms / notes") {
            TextEditor(text: $defaultTerms)
                .frame(minHeight: 160)
        }
    }

    private var reviewStep: some View {
        Section("Review") {
            LabeledContent("Company", value: companyNameTrimmed.isEmpty ? "Not set" : companyNameTrimmed)
            LabeledContent("Tax rate", value: formattedTaxRateForReview())
            LabeledContent("Logo", value: selectedLogoImage == nil && !shouldRemoveLogo ? "Not set" : (selectedLogoImage == nil ? "Removed" : "Selected"))

            if defaultTermsTrimmed.isEmpty {
                Text("Terms: Not set")
                    .foregroundStyle(.secondary)
            } else {
                Text("Terms:")
                    .font(.subheadline.weight(.semibold))
                Text(defaultTermsTrimmed)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var companyNameTrimmed: String {
        companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var defaultTermsTrimmed: String {
        defaultTerms.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
    }

    private func goNext() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        step = next
    }

    private func formattedTaxRateForReview() -> String {
        guard let rate = parseTaxRate(defaultTaxRateText) else { return "Not set" }
        let clamped = Money.clampTaxRate(rate)
        return "\(formatDecimal(clamped * 100))%"
    }

    private func parseTaxRate(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let stripped = trimmed.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Decimal(string: stripped, locale: Locale(identifier: "en_US_POSIX")) else { return nil }

        if raw <= 1 {
            return Money.clampTaxRate(raw)
        }

        return Money.clampTaxRate(raw / 100)
    }

    private func formatDecimal(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 4
        return formatter.string(from: number) ?? "\(number)"
    }

    private func loadExistingProfileIfPresent() {
        let repository = CompanyProfileRepository(modelContext: modelContext)
        guard let profile = try? repository.fetchCompanyProfile() else { return }

        companyName = profile.companyName
        if let rate = profile.defaultTaxRate {
            defaultTaxRateText = formatDecimal(rate * 100)
        } else {
            defaultTaxRateText = ""
        }
        defaultTerms = profile.defaultTerms ?? ""

        if let logoPath = profile.logoPath, !logoPath.isEmpty {
            if let storage = try? FileStorageManager() {
                selectedLogoImage = try? storage.loadImage(atRelativePath: logoPath)
                shouldRemoveLogo = false
            }
        }
    }

    private func loadSelectedLogo() {
        shouldRemoveLogo = false
        guard let item = selectedLogoItem else { return }

        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data)
                else {
                    throw CocoaError(.fileReadCorruptFile)
                }

                await MainActor.run {
                    selectedLogoImage = image
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Could not load selected logo image."
                }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        guard !companyNameTrimmed.isEmpty else {
            errorMessage = "Company name is required to save."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let repository = CompanyProfileRepository(modelContext: modelContext)
            let existing = try repository.fetchCompanyProfile()

            let storage = try FileStorageManager()
            var logoPath = existing?.logoPath

            if shouldRemoveLogo, let oldPath = existing?.logoPath {
                try? storage.deleteLogo(atRelativePath: oldPath)
                logoPath = nil
            }

            if let image = selectedLogoImage {
                if let oldPath = existing?.logoPath {
                    try? storage.deleteLogo(atRelativePath: oldPath)
                }
                logoPath = try storage.saveLogoImage(original: image)
            }

            let taxRate = parseTaxRate(defaultTaxRateText)
            _ = try repository.upsertCompanyProfile(
                companyName: companyNameTrimmed,
                defaultTaxRate: taxRate,
                clearDefaultTaxRate: false,
                defaultTerms: defaultTermsTrimmed.isEmpty ? nil : defaultTermsTrimmed,
                logoPath: logoPath
            )

            didSkipCompanyOnboarding = false
            dismiss()
        } catch {
            errorMessage = "Could not save company profile."
        }
    }
}
