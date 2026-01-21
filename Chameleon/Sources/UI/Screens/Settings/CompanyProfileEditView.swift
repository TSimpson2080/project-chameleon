import PhotosUI
import SwiftData
import SwiftUI
import UIKit

public struct CompanyProfileEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var profile: CompanyProfileModel?

    @State private var companyName: String = ""
    @State private var defaultTaxRateText: String = ""
    @State private var defaultTerms: String = ""

    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var selectedLogoImage: UIImage?
    @State private var shouldRemoveLogo = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    public init() {}

    public var body: some View {
        Form {
            Section("Company") {
                TextField("Company name", text: $companyName)
                    .textInputAutocapitalization(.words)

                TextField("Default tax rate (optional)", text: $defaultTaxRateText)
                    .keyboardType(.decimalPad)

                Text("Example: 8.25%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Logo") {
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

            Section("Default terms / notes") {
                TextEditor(text: $defaultTerms)
                    .frame(minHeight: 180)
            }
        }
        .navigationTitle("Company Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(isSaving ? "Saving…" : "Save") { save() }
                    .disabled(isSaving)
            }

            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 60)
        }
        .task { loadOrCreateProfile() }
        .onChange(of: selectedLogoItem) { _, _ in loadSelectedLogo() }
        .alert("Company Profile Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var companyNameTrimmed: String {
        companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var defaultTermsTrimmed: String {
        defaultTerms.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadOrCreateProfile() {
        let repository = CompanyProfileRepository(modelContext: modelContext)
        let existing = try? repository.fetchCompanyProfile()

        if let existing {
            profile = existing
        } else {
            let created = CompanyProfileModel(companyName: "")
            modelContext.insert(created)
            try? modelContext.save()
            profile = created
        }

        guard let profile else { return }
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
                else { throw CocoaError(.fileReadCorruptFile) }

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

            let trimmedTaxInput = defaultTaxRateText.trimmingCharacters(in: .whitespacesAndNewlines)
            let clearDefaultTaxRate = trimmedTaxInput.isEmpty
            let taxRate = parseTaxRate(trimmedTaxInput)

            _ = try repository.upsertCompanyProfile(
                companyName: companyNameTrimmed,
                defaultTaxRate: taxRate,
                clearDefaultTaxRate: clearDefaultTaxRate,
                defaultTerms: defaultTermsTrimmed.isEmpty ? nil : defaultTermsTrimmed,
                logoPath: logoPath
            )
            dismiss()
        } catch {
            errorMessage = "Could not save company profile."
        }
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
}
