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
    private let auditLogger: AuditLogger

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.auditLogger = AuditLogger(modelContext: modelContext)
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
        try auditLogger.record(
            action: .changeOrderCreated,
            entityType: .changeOrder,
            entityId: changeOrder.id,
            metadata: [
                "jobId": job.id,
                "number": safeNumber,
                "revisionNumber": 0,
            ],
            now: now,
            save: false
        )
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
        let beforeTitle = changeOrder.title
        let beforeDetails = changeOrder.details
        let beforeTaxRate = changeOrder.taxRate

        mutate(changeOrder)
        changeOrder.updatedAt = Date()
        changeOrder.job?.touchUpdatedAt()
        let now = changeOrder.updatedAt

        var changedFields: [String] = []
        if changeOrder.title != beforeTitle { changedFields.append("title") }
        if changeOrder.details != beforeDetails { changedFields.append("details") }
        if changeOrder.taxRate != beforeTaxRate { changedFields.append("taxRate") }

        if !changedFields.isEmpty {
            try auditLogger.record(
                action: .changeOrderUpdated,
                entityType: .changeOrder,
                entityId: changeOrder.id,
                metadata: [
                    "jobId": changeOrder.job?.id as Any,
                    "number": changeOrder.number,
                    "revisionNumber": changeOrder.revisionNumber,
                    "fields": changedFields,
                ],
                now: now,
                save: false
            )
        }
        try save()
    }

    @discardableResult
    public func addLineItem(
        changeOrder: ChangeOrderModel,
        name: String,
        details: String? = nil,
        quantity: Decimal,
        unitPrice: Decimal,
        unit: String? = nil,
        now: Date = Date()
    ) throws -> LineItemModel {
        guard !changeOrder.isLocked else { throw RepositoryError.lockedRecordImmutable }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxIndex = changeOrder.lineItems.map(\.sortIndex).max() ?? -1

        let item = LineItemModel(
            changeOrder: changeOrder,
            name: trimmedName.isEmpty ? "Untitled" : trimmedName,
            details: details?.trimmingCharacters(in: .whitespacesAndNewlines),
            category: .other,
            quantity: quantity,
            unitPrice: unitPrice,
            unit: unit?.trimmingCharacters(in: .whitespacesAndNewlines),
            sortIndex: maxIndex + 1,
            createdAt: now
        )
        changeOrder.lineItems.append(item)

        try recalculateTotals(changeOrder: changeOrder, now: now, recordAudit: true)
        return item
    }

    public func updateLineItem(
        lineItem: LineItemModel,
        name: String,
        details: String? = nil,
        quantity: Decimal,
        unitPrice: Decimal,
        unit: String? = nil,
        now: Date = Date()
    ) throws {
        guard let changeOrder = lineItem.changeOrder else { return }
        guard !changeOrder.isLocked else { throw RepositoryError.lockedRecordImmutable }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        lineItem.name = trimmedName.isEmpty ? "Untitled" : trimmedName
        lineItem.details = details?.trimmingCharacters(in: .whitespacesAndNewlines)
        lineItem.quantity = quantity
        lineItem.unitPrice = unitPrice
        lineItem.unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        lineItem.touchUpdatedAt(now: now)

        try recalculateTotals(changeOrder: changeOrder, now: now, recordAudit: true)
    }

    public func deleteLineItem(_ lineItem: LineItemModel, now: Date = Date()) throws {
        guard let changeOrder = lineItem.changeOrder else { return }
        guard !changeOrder.isLocked else { throw RepositoryError.lockedRecordImmutable }

        changeOrder.lineItems.removeAll { $0.id == lineItem.id }
        modelContext.delete(lineItem)
        try reindexLineItems(changeOrder: changeOrder)
        try recalculateTotals(changeOrder: changeOrder, now: now, recordAudit: true)
    }

    @discardableResult
    public func addPhotoAttachment(
        to changeOrder: ChangeOrderModel,
        filePath: String,
        thumbnailPath: String?,
        caption: String? = nil,
        now: Date = Date()
    ) throws -> AttachmentModel {
        guard !changeOrder.isLocked else { throw RepositoryError.lockedRecordImmutable }

        let attachment = AttachmentModel(
            changeOrder: changeOrder,
            type: .photo,
            filePath: filePath,
            thumbnailPath: thumbnailPath,
            caption: caption,
            createdAt: now
        )
        changeOrder.attachments.append(attachment)
        changeOrder.updatedAt = now
        changeOrder.job?.touchUpdatedAt(now: now)

        let totalPhotos = changeOrder.attachments.filter { $0.type == .photo }.count
        try auditLogger.record(
            action: .photoAdded,
            entityType: .attachment,
            entityId: attachment.id,
            metadata: [
                "changeOrderId": changeOrder.id,
                "jobId": changeOrder.job?.id as Any,
                "filePath": filePath,
                "thumbnailPath": thumbnailPath as Any,
                "totalPhotos": totalPhotos,
            ],
            now: now,
            save: false
        )

        try save()
        return attachment
    }

    public func captureClientSignature(
        for changeOrder: ChangeOrderModel,
        name: String,
        signatureFilePath: String,
        now: Date = Date()
    ) throws {
        guard !changeOrder.isLocked else { throw RepositoryError.lockedRecordImmutable }

        changeOrder.clientSignatureName = name
        changeOrder.updatedAt = now
        changeOrder.job?.touchUpdatedAt(now: now)

        if let existing = changeOrder.attachments.first(where: { $0.type == .signatureClient }) {
            existing.filePath = signatureFilePath
        } else {
            let attachment = AttachmentModel(
                changeOrder: changeOrder,
                type: .signatureClient,
                filePath: signatureFilePath,
                createdAt: now
            )
            changeOrder.attachments.append(attachment)
        }

        try auditLogger.record(
            action: .signatureCaptured,
            entityType: .changeOrder,
            entityId: changeOrder.id,
            metadata: [
                "jobId": changeOrder.job?.id as Any,
                "number": changeOrder.number,
                "revisionNumber": changeOrder.revisionNumber,
                "signatureFilePath": signatureFilePath,
                "hasName": !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            ],
            now: now,
            save: false
        )

        try save()
    }

    public func recordPDFPreviewed(
        changeOrder: ChangeOrderModel,
        pdfByteCount: Int,
        pdfHeader: String,
        now: Date = Date()
    ) throws {
        try auditLogger.record(
            action: .pdfPreviewed,
            entityType: .changeOrder,
            entityId: changeOrder.id,
            metadata: [
                "jobId": changeOrder.job?.id as Any,
                "locked": changeOrder.isLocked,
                "byteCount": pdfByteCount,
                "header": pdfHeader,
            ],
            now: now,
            save: true
        )
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
        try auditLogger.record(
            action: .revisionCreated,
            entityType: .changeOrder,
            entityId: revision.id,
            metadata: [
                "jobId": job.id,
                "number": number,
                "revisionNumber": nextRevisionNumber,
                "sourceChangeOrderId": lockedChangeOrder.id,
            ],
            now: now,
            save: false
        )

        let lockedId = lockedChangeOrder.persistentModelID
        let lineItems = try modelContext.fetch(FetchDescriptor<LineItemModel>(
            predicate: #Predicate<LineItemModel> { item in
                item.changeOrder?.persistentModelID == lockedId
            }
        ))
        for item in lineItems.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            let copied = LineItemModel(
                changeOrder: revision,
                name: item.name,
                details: item.details,
                category: item.category,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                unit: item.unit,
                sortIndex: item.sortIndex,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
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
        let companyName = company?.companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        let companyLogoImage = company?.logoPath.flatMap { logoPath in
            UIImage(contentsOfFile: fileStorage.url(forRelativePath: logoPath).path)
        }
        let photoAttachments = changeOrder.attachments.filter { $0.type == .photo }
        let photoURLs = photoAttachments.map { fileStorage.url(forRelativePath: $0.filePath) }
        let photoCaptions = photoAttachments.map(\.caption)

        let sortedLineItems = changeOrder.lineItems.sorted { $0.sortIndex < $1.sortIndex }
        let pdfLineItems = sortedLineItems.map { item in
            let quantity = Money.nonNegative(item.quantity)
            let unitPrice = Money.nonNegative(item.unitPrice)
            let lineTotal = Money.round(quantity * unitPrice)
            return PDFGenerator.Input.LineItem(
                name: item.name,
                quantity: quantity,
                unitPrice: unitPrice,
                lineTotal: lineTotal,
                unit: item.unit
            )
        }

        let input = PDFGenerator.Input(
            changeOrderNumberText: NumberingService.formatDisplayNumber(number: changeOrder.number, revisionNumber: changeOrder.revisionNumber),
            title: changeOrder.title,
            details: changeOrder.details,
            createdAt: changeOrder.createdAt,
            subtotal: changeOrder.subtotal,
            tax: pricing.tax,
            taxRate: changeOrder.taxRate,
            total: changeOrder.total,
            lineItems: pdfLineItems,
            companyName: (companyName?.isEmpty ?? true) ? nil : companyName,
            companyLogoImage: companyLogoImage,
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

        try auditLogger.record(
            action: .changeOrderLocked,
            entityType: .changeOrder,
            entityId: changeOrder.id,
            metadata: [
                "jobId": job.id,
                "number": changeOrder.number,
                "revisionNumber": changeOrder.revisionNumber,
                "signedPdfPath": signedPath,
                "signedPdfHash": hash,
            ],
            now: now,
            save: false
        )

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

    private func reindexLineItems(changeOrder: ChangeOrderModel) throws {
        let sorted = changeOrder.lineItems.sorted { lhs, rhs in
            if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
            return lhs.createdAt < rhs.createdAt
        }
        for (index, item) in sorted.enumerated() {
            item.sortIndex = index
        }
    }

    private func recalculateTotals(changeOrder: ChangeOrderModel, now: Date, recordAudit: Bool) throws {
        let breakdown = PricingCalculator.calculate(lineItems: changeOrder.lineItems, taxRate: Money.clampTaxRate(changeOrder.taxRate))
        changeOrder.subtotal = breakdown.subtotal
        changeOrder.total = breakdown.total
        changeOrder.updatedAt = now
        changeOrder.job?.touchUpdatedAt(now: now)

        if recordAudit {
            let categoryCounts = Dictionary(grouping: changeOrder.lineItems, by: { $0.category.rawValue })
                .mapValues { $0.count }
            try auditLogger.record(
                action: .changeOrderUpdated,
                entityType: .changeOrder,
                entityId: changeOrder.id,
                metadata: [
                    "jobId": changeOrder.job?.id as Any,
                    "number": changeOrder.number,
                    "revisionNumber": changeOrder.revisionNumber,
                    "fields": ["lineItems"],
                    "lineItemCount": changeOrder.lineItems.count,
                    "lineItemCategoryCounts": categoryCounts,
                ],
                now: now,
                save: false
            )
        }

        try save()
    }
}
