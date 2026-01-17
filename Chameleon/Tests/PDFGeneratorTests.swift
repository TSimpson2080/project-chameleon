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
}

