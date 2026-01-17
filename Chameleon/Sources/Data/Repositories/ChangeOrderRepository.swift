import Foundation
import SwiftData
import UIKit

@MainActor
public final class ChangeOrderRepository {
    public enum RepositoryError: LocalizedError, Equatable {
        case missingJob
        case lockedRecordImmutable
        case alreadyLocked
        case invalidTitle
        case invalidDetails
        case missingClientSignatureName
        case missingClientSignatureImage

        public var errorDescription: String? {
            switch self {
            case .missingJob:
                "This change order is missing its job."
            case .lockedRecordImmutable:
                "This change order is locked and cannot be edited."
            case .alreadyLocked:
                "This change order is already locked."
            case .invalidTitle:
                "Title is required."
            case .invalidDetails:
                "Description is required."
            case .missingClientSignatureName:
                "Client signature name is required to lock."
            case .missingClientSignatureImage:
                "Client signature is required to lock."
            }
        }
    }

    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    @MainActor
    public func createChangeOrder(
        job: JobModel,
        number: Int,
        title: String,
        details: String,
        taxRate: Decimal = 0
    ) throws -> ChangeOrderModel {
        let safeNumber = max(number, 1)
        job.nextChangeOrderNumber = max(job.nextChangeOrderNumber, safeNumber + 1)
        job.touchUpdatedAt()

        let now = Date()
        let changeOrder = ChangeOrderModel(
            job: job,
            number: safeNumber,
            revisionNumber: 0,
            title: title,
            details: details,
            taxRate: taxRate,
            createdAt: now,
            updatedAt: now,
            deviceTimeZoneId: TimeZone.current.identifier
        )

        modelContext.insert(changeOrder)
        try save()
        return changeOrder
    }

    @discardableResult
    @MainActor
    public func createChangeOrder(
        job: JobModel,
        title: String,
        description: String
    ) throws -> ChangeOrderModel {
        let number = max(job.nextChangeOrderNumber, 1)
        return try createChangeOrder(
            job: job,
            number: number,
            title: title,
            details: description,
            taxRate: 0
        )
    }

    @MainActor
    public func deleteChangeOrder(_ changeOrder: ChangeOrderModel) throws {
        modelContext.delete(changeOrder)
        try save()
    }

    @MainActor
    public func updateDraft(_ changeOrder: ChangeOrderModel, mutate: (ChangeOrderModel) -> Void) throws {
        guard !changeOrder.isLocked else { throw RepositoryError.lockedRecordImmutable }
        mutate(changeOrder)
        changeOrder.updatedAt = Date()
        changeOrder.job?.touchUpdatedAt()
        try save()
    }

    @discardableResult
    @MainActor
    public func createRevision(from lockedChangeOrder: ChangeOrderModel) throws -> ChangeOrderModel {
        guard lockedChangeOrder.isLocked else { throw RepositoryError.lockedRecordImmutable }
        guard let job = lockedChangeOrder.job else { throw RepositoryError.missingJob }

        let jobId = job.persistentModelID
        let number = lockedChangeOrder.number
        var descriptor = FetchDescriptor<ChangeOrderModel>(
            predicate: #Predicate<ChangeOrderModel> { changeOrder in
                changeOrder.job?.persistentModelID == jobId && changeOrder.number == number
            },
            sortBy: [SortDescriptor(\.revisionNumber, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        let latest = try modelContext.fetch(descriptor).first
        let nextRevisionNumber = (latest?.revisionNumber ?? 0) + 1

        let root = lockedChangeOrder.revisionOf ?? lockedChangeOrder
        let now = Date()

        let revision = ChangeOrderModel(
            job: job,
            number: number,
            revisionNumber: nextRevisionNumber,
            revisionOf: root,
            title: lockedChangeOrder.title,
            details: lockedChangeOrder.details,
            changeType: lockedChangeOrder.changeType,
            category: lockedChangeOrder.category,
            reason: lockedChangeOrder.reason,
            pricingMode: lockedChangeOrder.pricingMode,
            fixedSubtotal: lockedChangeOrder.fixedSubtotal,
            tmLaborHours: lockedChangeOrder.tmLaborHours,
            tmLaborRate: lockedChangeOrder.tmLaborRate,
            tmMaterialsCost: lockedChangeOrder.tmMaterialsCost,
            estimateLow: lockedChangeOrder.estimateLow,
            estimateHigh: lockedChangeOrder.estimateHigh,
            subtotal: lockedChangeOrder.subtotal,
            taxRate: lockedChangeOrder.taxRate,
            total: lockedChangeOrder.total,
            scheduleDays: lockedChangeOrder.scheduleDays,
            status: .draft,
            createdAt: now,
            updatedAt: now,
            deviceTimeZoneId: TimeZone.current.identifier,
            signedPdfPath: nil,
            signedPdfHash: nil
        )

        modelContext.insert(revision)

        let lockedId = lockedChangeOrder.persistentModelID
        let lineItems = try modelContext.fetch(FetchDescriptor<LineItemModel>(
            predicate: #Predicate<LineItemModel> { item in
                item.changeOrder?.persistentModelID == lockedId
            }
        ))
        for item in lineItems {
            let copied = LineItemModel(
                changeOrder: revision,
                name: item.name,
                quantity: item.quantity,
                unitPrice: item.unitPrice
            )
            revision.lineItems.append(copied)
        }

        let attachments = try modelContext.fetch(FetchDescriptor<AttachmentModel>(
            predicate: #Predicate<AttachmentModel> { attachment in
                attachment.changeOrder?.persistentModelID == lockedId
            }
        ))
        for attachment in attachments where attachment.type == .photo {
            let copied = AttachmentModel(
                changeOrder: revision,
                type: attachment.type,
                filePath: attachment.filePath,
                thumbnailPath: attachment.thumbnailPath,
                caption: attachment.caption,
                createdAt: attachment.createdAt
            )
            revision.attachments.append(copied)
        }

        job.touchUpdatedAt()
        try save()
        return revision
    }

    @MainActor
    public func lockChangeOrder(_ changeOrder: ChangeOrderModel, fileStorage: FileStorageManager) throws {
        guard !changeOrder.isLocked else { throw RepositoryError.alreadyLocked }
        guard let job = changeOrder.job else { throw RepositoryError.missingJob }

        let trimmedTitle = changeOrder.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw RepositoryError.invalidTitle }

        let trimmedDetails = changeOrder.details.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDetails.isEmpty else { throw RepositoryError.invalidDetails }

        let trimmedSignatureName = (changeOrder.clientSignatureName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSignatureName.isEmpty else { throw RepositoryError.missingClientSignatureName }

        let signaturePath = changeOrder.attachments.first(where: { $0.type == .signatureClient })?.filePath
        guard let signaturePath else { throw RepositoryError.missingClientSignatureImage }

        let signatureURL = fileStorage.url(forRelativePath: signaturePath)
        guard let signatureImage = UIImage(contentsOfFile: signatureURL.path) else {
            throw RepositoryError.missingClientSignatureImage
        }

        let now = Date()
        let pricing = PricingCalculator.calculate(lineItems: changeOrder.lineItems, taxRate: Money.clampTaxRate(changeOrder.taxRate))
        changeOrder.subtotal = pricing.subtotal
        changeOrder.total = pricing.total

        let company = fetchCompanyProfile()
        let photoAttachments = changeOrder.attachments.filter { $0.type == .photo }
        let photoURLs = photoAttachments.map { fileStorage.url(forRelativePath: $0.filePath) }
        let photoCaptions = photoAttachments.map(\.caption)

        let input = PDFGenerator.Input(
            changeOrderNumberText: NumberingService.formatDisplayNumber(number: changeOrder.number, revisionNumber: changeOrder.revisionNumber),
            title: changeOrder.title,
            details: changeOrder.details,
            createdAt: changeOrder.createdAt,
            subtotal: changeOrder.subtotal,
            taxRate: changeOrder.taxRate,
            total: changeOrder.total,
            companyName: company?.companyName,
            jobClientName: job.clientName,
            jobProjectName: job.projectName,
            jobAddress: job.address,
            terms: job.termsOverride ?? company?.defaultTerms,
            signatureName: trimmedSignatureName,
            signatureDate: now,
            signatureImage: signatureImage,
            photoURLs: photoURLs,
            photoCaptions: photoCaptions
        )

        let pdfData = PDFGenerator.generateSignedPDFData(input: input)

        let fileName = "\(NumberingService.formatChangeOrderNumber(changeOrder.number))\(changeOrder.revisionNumber > 0 ? "-Rev\(changeOrder.revisionNumber)" : "")-\(UUID().uuidString)"
        let signedPath = try fileStorage.saveSignedPDF(data: pdfData, fileName: fileName)
        let hash = SHA256Hasher.sha256Hex(data: pdfData)

        changeOrder.lockedAt = now
        changeOrder.clientSignatureSignedAt = now
        changeOrder.status = .approved
        changeOrder.approvedAt = now
        changeOrder.signedPdfPath = signedPath
        changeOrder.signedPdfHash = hash
        changeOrder.updatedAt = now

        job.touchUpdatedAt(now: now)
        try save()
    }

    public func fetchChangeOrders(for job: JobModel, search: String? = nil) throws -> [ChangeOrderModel] {
        let jobId = job.persistentModelID
        let predicate = #Predicate<ChangeOrderModel> { changeOrder in
            changeOrder.job?.persistentModelID == jobId
        }
        let descriptor = FetchDescriptor<ChangeOrderModel>(
            predicate: predicate,
            sortBy: [
                SortDescriptor(\.updatedAt, order: .reverse),
                SortDescriptor(\.number, order: .reverse),
                SortDescriptor(\.revisionNumber, order: .reverse),
            ]
        )

        let changeOrders = try modelContext.fetch(descriptor)

        guard let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return changeOrders
        }

        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return changeOrders.filter { changeOrder in
            if changeOrder.title.lowercased().contains(query) { return true }
            if changeOrder.details.lowercased().contains(query) { return true }
            return false
        }
    }

    public func save() throws {
        try modelContext.save()
    }

    private func fetchCompanyProfile() -> CompanyProfileModel? {
        var descriptor = FetchDescriptor<CompanyProfileModel>()
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
