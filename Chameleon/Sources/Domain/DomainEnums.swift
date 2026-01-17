import Foundation

public enum ChangeType: String, Codable, CaseIterable, Identifiable {
    case add = "Add"
    case modify = "Modify"
    case remove = "Remove"
    case repair = "Repair"

    public var id: String { rawValue }
}

public enum ChangeOrderCategory: String, Codable, CaseIterable, Identifiable {
    case labor = "Labor"
    case materials = "Materials"
    case equipment = "Equipment"
    case subcontractor = "Subcontractor"
    case permit = "Permit"
    case disposal = "Disposal"
    case design = "Design"
    case other = "Other"

    public var id: String { rawValue }
}

public enum ChangeOrderReason: String, Codable, CaseIterable, Identifiable {
    case clientRequest = "ClientRequest"
    case unforeseenCondition = "UnforeseenCondition"
    case codeRequirement = "CodeRequirement"
    case designChange = "DesignChange"
    case scopeClarification = "ScopeClarification"
    case repair = "Repair"
    case accessIssue = "AccessIssue"
    case weatherDelay = "WeatherDelay"
    case other = "Other"

    public var id: String { rawValue }
}

public enum PricingMode: String, Codable, CaseIterable, Identifiable {
    case fixed = "Fixed"
    case timeMaterials = "TimeMaterials"
    case estimateRange = "EstimateRange"

    public var id: String { rawValue }
}

public enum ChangeOrderStatus: String, Codable, CaseIterable, Identifiable {
    case draft = "Draft"
    case sent = "Sent"
    case approved = "Approved"
    case rejected = "Rejected"
    case cancelled = "Cancelled"

    public var id: String { rawValue }
}

public enum AttachmentType: String, Codable, CaseIterable, Identifiable {
    case photo = "Photo"
    case signatureClient = "SignatureClient"
    case signatureContractor = "SignatureContractor"
    case pdfDraft = "PdfDraft"
    case pdfSigned = "PdfSigned"

    public var id: String { rawValue }
}

public enum AuditAction: String, Codable, CaseIterable, Identifiable {
    case jobCreated = "job_created"
    case jobUpdated = "job_updated"
    case changeOrderCreated = "co_created"
    case changeOrderUpdated = "co_updated"
    case photoAdded = "photo_added"
    case signatureCaptured = "signature_captured"
    case pdfPreviewed = "pdf_previewed"
    case changeOrderLocked = "co_locked"
    case revisionCreated = "revision_created"
    case exportCreated = "export_created"

    public var id: String { rawValue }
}

public enum AuditEntityType: String, Codable, CaseIterable, Identifiable {
    case job = "job"
    case changeOrder = "changeOrder"
    case attachment = "attachment"
    case export = "export"

    public var id: String { rawValue }
}
