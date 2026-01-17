import Foundation
import CoreText
import UIKit

public enum PDFGenerator {
    public struct Input {
        public struct LineItem {
            public var name: String
            public var quantity: Decimal
            public var unitPrice: Decimal
            public var lineTotal: Decimal
            public var unit: String?

            public init(name: String, quantity: Decimal, unitPrice: Decimal, lineTotal: Decimal, unit: String? = nil) {
                self.name = name
                self.quantity = quantity
                self.unitPrice = unitPrice
                self.lineTotal = lineTotal
                self.unit = unit
            }
        }

        public var changeOrderNumberText: String
        public var title: String
        public var details: String
        public var createdAt: Date
        public var subtotal: Decimal
        public var tax: Decimal
        public var taxRate: Decimal
        public var total: Decimal
        public var lineItems: [LineItem]
        public var companyName: String?
        public var companyLogoImage: UIImage?
        public var jobClientName: String
        public var jobProjectName: String?
        public var jobAddress: String?
        public var terms: String?
        public var signatureName: String?
        public var signatureDate: Date?
        public var signatureImage: UIImage?
        public var photoURLs: [URL]
        public var photoCaptions: [String?]

        public init(
            changeOrderNumberText: String,
            title: String,
            details: String,
            createdAt: Date,
            subtotal: Decimal,
            tax: Decimal,
            taxRate: Decimal,
            total: Decimal,
            lineItems: [LineItem] = [],
            companyName: String?,
            companyLogoImage: UIImage? = nil,
            jobClientName: String,
            jobProjectName: String?,
            jobAddress: String?,
            terms: String?,
            signatureName: String?,
            signatureDate: Date?,
            signatureImage: UIImage?,
            photoURLs: [URL],
            photoCaptions: [String?]
        ) {
            self.changeOrderNumberText = changeOrderNumberText
            self.title = title
            self.details = details
            self.createdAt = createdAt
            self.subtotal = subtotal
            self.tax = tax
            self.taxRate = taxRate
            self.total = total
            self.lineItems = lineItems
            self.companyName = companyName
            self.companyLogoImage = companyLogoImage
            self.jobClientName = jobClientName
            self.jobProjectName = jobProjectName
            self.jobAddress = jobAddress
            self.terms = terms
            self.signatureName = signatureName
            self.signatureDate = signatureDate
            self.signatureImage = signatureImage
            self.photoURLs = photoURLs
            self.photoCaptions = photoCaptions
        }
    }

    public static func generateDraftPDFData(input: Input) -> Data {
        generatePDFData(input: input, mode: .draft)
    }

    public static func generateSignedPDFData(input: Input) -> Data {
        generatePDFData(input: input, mode: .signed)
    }

    private enum Mode {
        case draft
        case signed
    }

    private static func generatePDFData(input: Input, mode: Mode) -> Data {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter @ 72 DPI
        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: format)

        return renderer.pdfData { context in
            context.beginPage()
            drawPage1(in: context.cgContext, bounds: pageBounds, input: input, mode: mode)

            drawPhotoAppendix(
                in: context,
                bounds: pageBounds,
                photoURLs: input.photoURLs,
                captions: input.photoCaptions
            )
        }
    }

    private static func drawPage1(in cgContext: CGContext, bounds: CGRect, input: Input, mode: Mode) {
        let margin: CGFloat = 36
        var cursorY: CGFloat = margin
        let contentWidth = bounds.width - (margin * 2)

        let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
        let headerFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: 12, weight: .regular)
        let smallFont = UIFont.systemFont(ofSize: 10, weight: .regular)

        let company = (input.companyName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Chameleon"
        let logoSize: CGFloat = 44
        let logoPadding: CGFloat = 10
        if let logo = input.companyLogoImage {
            let logoRect = CGRect(x: margin, y: margin, width: logoSize, height: logoSize)
            drawImage(logo, in: cgContext, rect: logoRect)
            cursorY = drawText(
                company,
                font: titleFont,
                in: cgContext,
                x: margin + logoSize + logoPadding,
                y: cursorY,
                width: contentWidth - (logoSize + logoPadding)
            )
        } else {
            cursorY = drawText(company, font: titleFont, in: cgContext, x: margin, y: cursorY, width: contentWidth)
        }

        let label = (mode == .draft) ? "DRAFT" : "SIGNED"
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .bold),
            .foregroundColor: UIColor.systemRed,
        ]
        let labelSize = (label as NSString).size(withAttributes: labelAttributes)
        (label as NSString).draw(at: CGPoint(x: bounds.width - margin - labelSize.width, y: margin), withAttributes: labelAttributes)

        cursorY += 12
        cursorY = drawText("Change Order: \(input.changeOrderNumberText)", font: headerFont, in: cgContext, x: margin, y: cursorY, width: contentWidth)
        cursorY = drawText("Title: \(input.title)", font: bodyFont, in: cgContext, x: margin, y: cursorY, width: contentWidth)
        cursorY = drawText("Created: \(formatDate(input.createdAt))", font: bodyFont, in: cgContext, x: margin, y: cursorY, width: contentWidth)

        cursorY += 8
        cursorY = drawText("Job: \(input.jobClientName)", font: headerFont, in: cgContext, x: margin, y: cursorY, width: contentWidth)
        if let project = input.jobProjectName, !project.isEmpty {
            cursorY = drawText("Project: \(project)", font: bodyFont, in: cgContext, x: margin, y: cursorY, width: contentWidth)
        }
        if let address = input.jobAddress, !address.isEmpty {
            cursorY = drawText("Address: \(address)", font: bodyFont, in: cgContext, x: margin, y: cursorY, width: contentWidth)
        }

        cursorY += 12
        cursorY = drawText("Details", font: headerFont, in: cgContext, x: margin, y: cursorY, width: contentWidth)
        cursorY = drawText(input.details, font: bodyFont, in: cgContext, x: margin, y: cursorY, width: contentWidth)

        cursorY += 12
        cursorY = drawLineItemsAndTotals(
            in: cgContext,
            bounds: bounds,
            margin: margin,
            cursorY: cursorY,
            contentWidth: contentWidth,
            headerFont: headerFont,
            bodyFont: bodyFont,
            smallFont: smallFont,
            input: input,
            mode: mode
        )

        if mode == .signed {
            let signatureAreaTop = bounds.height - 160
            cgContext.setStrokeColor(UIColor.separator.cgColor)
            cgContext.setLineWidth(1)
            cgContext.stroke(CGRect(x: margin, y: signatureAreaTop, width: contentWidth, height: 120))

            _ = drawText("Signature", font: headerFont, in: cgContext, x: margin + 8, y: signatureAreaTop + 8, width: contentWidth - 16)

            if let name = input.signatureName, !name.isEmpty {
                _ = drawText("Name: \(name)", font: bodyFont, in: cgContext, x: margin + 8, y: signatureAreaTop + 30, width: contentWidth - 16)
            }
            if let date = input.signatureDate {
                _ = drawText("Signed: \(formatDate(date))", font: bodyFont, in: cgContext, x: margin + 8, y: signatureAreaTop + 46, width: contentWidth - 16)
            }

            if let image = input.signatureImage {
                let maxWidth: CGFloat = contentWidth - 16
                let targetRect = CGRect(x: margin + 8, y: signatureAreaTop + 64, width: maxWidth, height: 48)
                drawImage(image, in: cgContext, rect: targetRect)
            }
        }
    }

    private static func drawLineItemsAndTotals(
        in cgContext: CGContext,
        bounds: CGRect,
        margin: CGFloat,
        cursorY: CGFloat,
        contentWidth: CGFloat,
        headerFont: UIFont,
        bodyFont: UIFont,
        smallFont: UIFont,
        input: Input,
        mode: Mode
    ) -> CGFloat {
        var y = cursorY
        let bottomLimit: CGFloat = (mode == .signed) ? (bounds.height - 170) : (bounds.height - margin)

        if !input.lineItems.isEmpty, y + 40 < bottomLimit {
            y = drawText("Line Items", font: headerFont, in: cgContext, x: margin, y: y, width: contentWidth)

            let colName: CGFloat = 260
            let colQty: CGFloat = 60
            let colUnitPrice: CGFloat = 100
            let colTotal: CGFloat = contentWidth - colName - colQty - colUnitPrice

            let headerRowFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
            let rowFont = UIFont.systemFont(ofSize: 10, weight: .regular)

            y += 2
            cgContext.setFillColor(UIColor.secondarySystemBackground.cgColor)
            cgContext.fill(CGRect(x: margin, y: y, width: contentWidth, height: 18))

            _ = drawTextAligned("Name", font: headerRowFont, alignment: .left, in: cgContext, x: margin + 4, y: y + 3, width: colName - 8)
            _ = drawTextAligned("Qty", font: headerRowFont, alignment: .right, in: cgContext, x: margin + colName, y: y + 3, width: colQty - 8)
            _ = drawTextAligned("Unit", font: headerRowFont, alignment: .right, in: cgContext, x: margin + colName + colQty, y: y + 3, width: colUnitPrice - 8)
            _ = drawTextAligned("Total", font: headerRowFont, alignment: .right, in: cgContext, x: margin + colName + colQty + colUnitPrice, y: y + 3, width: colTotal - 8)

            y += 18

            for item in input.lineItems {
                let rowHeight: CGFloat = 18
                guard y + rowHeight < bottomLimit - 70 else { break }

                _ = drawTextAligned(item.name, font: rowFont, alignment: .left, in: cgContext, x: margin + 4, y: y + 3, width: colName - 8)
                _ = drawTextAligned(formatDecimal(item.quantity), font: rowFont, alignment: .right, in: cgContext, x: margin + colName, y: y + 3, width: colQty - 8)
                _ = drawTextAligned(formatMoney(item.unitPrice), font: rowFont, alignment: .right, in: cgContext, x: margin + colName + colQty, y: y + 3, width: colUnitPrice - 8)
                _ = drawTextAligned(formatMoney(item.lineTotal), font: rowFont, alignment: .right, in: cgContext, x: margin + colName + colQty + colUnitPrice, y: y + 3, width: colTotal - 8)

                y += rowHeight
            }

            y += 8
        }

        if y + 60 < bottomLimit {
            y = drawText("Totals", font: headerFont, in: cgContext, x: margin, y: y, width: contentWidth)
            y = drawText("Subtotal: \(formatMoney(input.subtotal))", font: bodyFont, in: cgContext, x: margin, y: y, width: contentWidth)
            y = drawText("Tax (\(formatTaxRate(input.taxRate))): \(formatMoney(input.tax))", font: bodyFont, in: cgContext, x: margin, y: y, width: contentWidth)
            y = drawText("Total: \(formatMoney(input.total))", font: bodyFont, in: cgContext, x: margin, y: y, width: contentWidth)
        }

        if let terms = input.terms?.trimmingCharacters(in: .whitespacesAndNewlines), !terms.isEmpty {
            y += 12
            y = drawText("Terms", font: headerFont, in: cgContext, x: margin, y: y, width: contentWidth)
            y = drawText(terms, font: smallFont, in: cgContext, x: margin, y: y, width: contentWidth)
        }

        return y
    }

    private static func drawTextAligned(
        _ text: String,
        font: UIFont,
        alignment: NSTextAlignment,
        in cgContext: CGContext,
        x: CGFloat,
        y: CGFloat,
        width: CGFloat
    ) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = alignment

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        attributed.draw(in: CGRect(x: x, y: y, width: width, height: 14))
        return y + 14
    }

    private static func drawPhotoAppendix(in context: UIGraphicsPDFRendererContext, bounds: CGRect, photoURLs: [URL], captions: [String?]) {
        guard !photoURLs.isEmpty else { return }

        let margin: CGFloat = 36
        let contentWidth = bounds.width - (margin * 2)
        let contentHeight = bounds.height - (margin * 2)
        let headerFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let captionFont = UIFont.systemFont(ofSize: 10, weight: .regular)

        var index = 0
        while index < photoURLs.count {
            context.beginPage()

            var cursorY: CGFloat = margin
            cursorY = drawText("Photo Appendix", font: headerFont, in: context.cgContext, x: margin, y: cursorY, width: contentWidth)
            cursorY += 8

            let availableHeight = contentHeight - 24
            let perPhotoHeight = (availableHeight - 12) / 2

            for slot in 0..<2 {
                guard index < photoURLs.count else { break }
                let url = photoURLs[index]
                let caption = (index < captions.count) ? captions[index] : nil

                if let image = UIImage(contentsOfFile: url.path) {
                    let imageRect = CGRect(x: margin, y: cursorY, width: contentWidth, height: perPhotoHeight - 18)
                    drawImage(image, in: context.cgContext, rect: imageRect)
                }

                if let caption, !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    _ = drawText(caption, font: captionFont, in: context.cgContext, x: margin, y: cursorY + (perPhotoHeight - 16), width: contentWidth)
                }

                cursorY += perPhotoHeight + (slot == 0 ? 12 : 0)
                index += 1
            }
        }
    }

    private static func drawText(_ text: String, font: UIFont, in cgContext: CGContext, x: CGFloat, y: CGFloat, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.alignment = .left

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph,
        ]

        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let constraint = CGSize(width: width, height: .greatestFiniteMagnitude)
        let fitSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(), nil, constraint, nil)

        let height = ceil(fitSize.height)
        let rect = CGRect(x: x, y: y, width: width, height: height)
        attributed.draw(in: rect)
        return y + height + 4
    }

    private static func drawImage(_ image: UIImage, in cgContext: CGContext, rect: CGRect) {
        let fitted = aspectFitRect(contentSize: image.size, container: rect)
        image.draw(in: fitted)
    }

    private static func aspectFitRect(contentSize: CGSize, container: CGRect) -> CGRect {
        guard contentSize.width > 0, contentSize.height > 0 else { return container }
        let scale = min(container.width / contentSize.width, container.height / contentSize.height)
        let width = contentSize.width * scale
        let height = contentSize.height * scale
        let x = container.minX + (container.width - width) / 2
        let y = container.minY + (container.height - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }

    private static func formatMoney(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(number)"
    }

    private static func formatDecimal(_ value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: number) ?? "\(number)"
    }

    private static func formatTaxRate(_ value: Decimal) -> String {
        let percent = (value as NSDecimalNumber).multiplying(by: 100)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        let text = formatter.string(from: percent) ?? "\(percent)"
        return "\(text)%"
    }
}
