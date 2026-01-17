import Foundation
import UIKit

public final class PDFGenerator {
    public enum PDFError: Error {
        case missingJob
        case failedToLoadImage
    }

    private let storage: FileStorageManager

    public init(storage: FileStorageManager = .shared) {
        self.storage = storage
    }

    public func generateDraftPDFData(
        changeOrder: ChangeOrderModel,
        job: JobModel,
        companyProfile: CompanyProfileModel?,
        photoAttachments: [AttachmentModel]
    ) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72dpi
        let margins = UIEdgeInsets(top: 36, left: 36, bottom: 36, right: 36)
        let contentWidth = pageRect.width - margins.left - margins.right

        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextCreator as String: "Project Chameleon",
            kCGPDFContextTitle as String: "Draft Change Order",
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        let sortedPhotos = photoAttachments
            .filter { $0.type == .photo }
            .sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let dateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd HH:mm 'UTC'"
            return formatter
        }()

        let companyName = companyProfile?.companyName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = (job.termsOverride?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? (companyProfile?.defaultTerms?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }

        let pricing = PricingCalculator.calculate(lineItems: changeOrder.lineItems, taxRate: changeOrder.taxRate)

        return renderer.pdfData { context in
            var pages: [(title: String, lines: [String])] = []

            let headerNumber = NumberingService.formatChangeOrderNumber(changeOrder.number)
            pages.append((
                title: "Draft Change Order",
                lines: [
                    companyName.map { "Company: \($0)" } ?? "Company: —",
                    "Client: \(job.clientName)",
                    "Project: \(job.projectName?.isEmpty == false ? job.projectName! : "—")",
                    "Address: \(job.address?.isEmpty == false ? job.address! : "—")",
                    "",
                    "Change Order: \(headerNumber)",
                    "Title: \(changeOrder.title)",
                    "",
                    "Details:",
                    changeOrder.details,
                    "",
                    "Created: \(dateFormatter.string(from: changeOrder.createdAt))",
                    "",
                    "Subtotal: \(Money.round(pricing.subtotal))",
                    "Tax: \(Money.round(pricing.tax))",
                    "Total: \(Money.round(pricing.total))",
                    "",
                ] + (terms.map { ["Terms:", $0] } ?? [])
            ))

            if pages.isEmpty {
                context.beginPage()
                NSAttributedString(
                    string: "DRAFT",
                    attributes: [
                        .font: UIFont.boldSystemFont(ofSize: 24),
                        .foregroundColor: UIColor.red,
                    ]
                )
                .draw(in: CGRect(x: margins.left, y: margins.top, width: contentWidth, height: 30))
                return
            }

            for page in pages {
                context.beginPage()
                drawDraftWatermark(in: context.cgContext, pageRect: pageRect)

                var y = margins.top

                let titleAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.black,
                ]

                let titleString = NSAttributedString(string: page.title, attributes: titleAttributes)
                let titleRect = CGRect(x: margins.left, y: y, width: contentWidth, height: 28)
                titleString.draw(in: titleRect)
                y += 34

                let draftLabelAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 14),
                    .foregroundColor: UIColor.red,
                ]
                let draftLabel = NSAttributedString(string: "DRAFT", attributes: draftLabelAttributes)
                draftLabel.draw(in: CGRect(x: pageRect.width - margins.right - 60, y: margins.top, width: 60, height: 18))

                let bodyAttributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.black,
                ]

                for line in page.lines {
                    if line.isEmpty {
                        y += 10
                        continue
                    }

                    let paragraph = NSAttributedString(string: line, attributes: bodyAttributes)
                    let measured = paragraph.boundingRect(
                        with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )

                    let rect = CGRect(x: margins.left, y: y, width: contentWidth, height: ceil(measured.height))
                    paragraph.draw(in: rect)
                    y += rect.height + 6

                    if y > pageRect.height - margins.bottom - 40 {
                        context.beginPage()
                        drawDraftWatermark(in: context.cgContext, pageRect: pageRect)
                        y = margins.top
                    }
                }
            }

            if !sortedPhotos.isEmpty {
                renderPhotoAppendix(
                    photos: sortedPhotos,
                    context: context,
                    pageRect: pageRect,
                    margins: margins
                )
            }
        }
    }

    public func writeDraftPDFToTemporaryFile(
        changeOrder: ChangeOrderModel,
        job: JobModel,
        companyProfile: CompanyProfileModel?,
        photoAttachments: [AttachmentModel]
    ) throws -> URL {
        let data = try generateDraftPDFData(
            changeOrder: changeOrder,
            job: job,
            companyProfile: companyProfile,
            photoAttachments: photoAttachments
        )

        let filename = "Chameleon-Draft-\(UUID().uuidString).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: [.atomic])
        return url
    }

    private func drawDraftWatermark(in context: CGContext, pageRect: CGRect) {
        context.saveGState()
        context.setAlpha(0.12)
        context.translateBy(x: pageRect.midX, y: pageRect.midY)
        context.rotate(by: -CGFloat.pi / 6)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: 96),
            .foregroundColor: UIColor.red,
        ]
        let text = NSAttributedString(string: "DRAFT", attributes: attributes)
        let size = text.size()
        let rect = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
        text.draw(in: rect)

        context.restoreGState()
    }

    private func renderPhotoAppendix(
        photos: [AttachmentModel],
        context: UIGraphicsPDFRendererContext,
        pageRect: CGRect,
        margins: UIEdgeInsets
    ) {
        let renderable = photos.compactMap { attachment -> (attachment: AttachmentModel, image: UIImage)? in
            guard let image = storage.loadImage(at: attachment.filePath) else { return nil }
            return (attachment: attachment, image: image)
        }
        guard !renderable.isEmpty else { return }

        let contentWidth = pageRect.width - margins.left - margins.right
        let availableHeight = pageRect.height - margins.top - margins.bottom
        let blockSpacing: CGFloat = 18
        let captionHeight: CGFloat = 18

        let blocksPerPage = 2
        let blockHeight = (availableHeight - blockSpacing) / CGFloat(blocksPerPage)
        let imageHeight = blockHeight - captionHeight

        let captionAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11),
            .foregroundColor: UIColor.black,
        ]

        for chunkStart in stride(from: 0, to: renderable.count, by: blocksPerPage) {
            context.beginPage()
            let cgContext = context.cgContext
            drawDraftWatermark(in: cgContext, pageRect: pageRect)

            for indexInPage in 0..<blocksPerPage {
                let photoIndex = chunkStart + indexInPage
                guard photoIndex < renderable.count else { continue }
                let entry = renderable[photoIndex]

                let topY = margins.top + CGFloat(indexInPage) * (blockHeight + blockSpacing)
                let imageRect = CGRect(x: margins.left, y: topY, width: contentWidth, height: imageHeight)
                let captionRect = CGRect(x: margins.left, y: topY + imageHeight + 4, width: contentWidth, height: captionHeight)

                drawImage(entry.image, in: imageRect, context: cgContext)

                let caption = entry.attachment.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
                let captionText = (caption?.isEmpty == false) ? caption! : "Photo \(photoIndex + 1)"
                NSAttributedString(string: captionText, attributes: captionAttributes).draw(in: captionRect)
            }
        }
    }

    private func drawImage(_ image: UIImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.setFillColor(UIColor.black.cgColor)
        context.fill(rect)

        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else {
            context.restoreGState()
            return
        }

        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let targetSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(
            x: rect.midX - targetSize.width / 2,
            y: rect.midY - targetSize.height / 2
        )
        image.draw(in: CGRect(origin: origin, size: targetSize))
        context.restoreGState()
    }
}
