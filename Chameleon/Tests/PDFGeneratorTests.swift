import Foundation
import PDFKit
import Testing
import UIKit
@testable import Chameleon

@MainActor
struct PDFGeneratorTests {
    @Test func generatesValidPDFDataWithNoPhotos() throws {
        let input = PDFGenerator.Input(
            changeOrderNumberText: "CO-0001",
            title: "Test",
            details: "Details",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            subtotal: 10,
            tax: 0.70,
            taxRate: 0.07,
            total: 10.70,
            companyName: "Test Co",
            jobClientName: "Client",
            jobProjectName: "Project",
            jobAddress: "123 Main",
            terms: "Terms",
            signatureName: nil,
            signatureDate: nil,
            signatureImage: nil,
            photoURLs: [],
            photoCaptions: []
        )

        let data = PDFGenerator.generateDraftPDFData(input: input)

        #expect(data.count > 1000)
        #expect(String(data: data.prefix(5), encoding: .ascii) == "%PDF-")

        let document = PDFDocument(data: data)
        #expect(document != nil)
        #expect((document?.pageCount ?? 0) >= 1)
    }

    @Test func pdfContainsLineItemAndTotalText() throws {
        let input = PDFGenerator.Input(
            changeOrderNumberText: "CO-0001",
            title: "Test",
            details: "Details",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            subtotal: 200,
            tax: 20,
            taxRate: 0.10,
            total: 220,
            lineItems: [
                .init(name: "Paint", quantity: 2, unitPrice: 100, lineTotal: 200, unit: "hrs"),
            ],
            companyName: "Test Co",
            jobClientName: "Client",
            jobProjectName: "Project",
            jobAddress: "123 Main",
            terms: nil,
            signatureName: "Client",
            signatureDate: Date(timeIntervalSince1970: 1_700_000_100),
            signatureImage: nil,
            photoURLs: [],
            photoCaptions: []
        )

        let data = PDFGenerator.generateSignedPDFData(input: input)
        let document = try #require(PDFDocument(data: data))
        let page = try #require(document.page(at: 0))
        let text = page.string ?? ""

        #expect(text.contains("Paint"))
        #expect(text.contains("Total:"))
        #expect(text.contains("220.00"))
    }
}
