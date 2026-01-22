import PDFKit
import SwiftUI

public struct PDFPreviewScreen: View {
    private struct SharePayload: Identifiable {
        let id = UUID()
        let url: URL
    }

    public let title: String
    public let pdfData: Data

    @State private var sharePayload: SharePayload?
    @State private var shareErrorMessage: String?

    public init(title: String, pdfData: Data) {
        self.title = title
        self.pdfData = pdfData
    }

    public var body: some View {
        Group {
            if let document = PDFDocument(data: pdfData) {
                PDFKitView(document: document)
            } else {
                ContentUnavailableView("No PDF", systemImage: "doc.richtext", description: Text("Could not generate a preview."))
                    .onAppear { logInvalidPDF() }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Share") { share() }
            }
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: [payload.url])
        }
        .alert("Share Error", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage ?? "Unknown error")
        }
    }

	    private func share() {
	        let header = String(data: pdfData.prefix(8), encoding: .ascii) ?? "<non-ascii>"
	        print("PDFPreviewScreen Share tapped. data.count=\(pdfData.count) header=\(header)")

	        guard pdfData.count >= 1000, header.hasPrefix("%PDF-") else {
	            shareErrorMessage = "Invalid PDF data (count=\(pdfData.count), header=\(header))."
	            return
	        }

	        let shareURL = writeTempPDF()
	        print("PDF share temp URL: \(shareURL?.path ?? "<nil>")")
	        guard let url = shareURL else {
	            shareErrorMessage = "Could not write a temporary PDF file for sharing."
	            return
	        }

	        print("PDFPreviewScreen temp file: \(url.path)")
	        sharePayload = SharePayload(url: url)
	    }

	    private func writeTempPDF() -> URL? {
	        let directory = FileManager.default.temporaryDirectory
	        let url = directory.appendingPathComponent("ReScope-\(UUID().uuidString).pdf")
	        print("Writing temp PDF to: \(url.path) bytes=\(pdfData.count) header=\(String(bytes: pdfData.prefix(8), encoding: .ascii) ?? "<non-ascii>")")

	        do {
	            try pdfData.write(to: url, options: [.atomic])
	            return url
	        } catch {
            print("PDFPreviewScreen writeTempPDF error: \(error)")
            return nil
        }
    }

    private func logInvalidPDF() {
        let header = String(data: pdfData.prefix(8), encoding: .ascii) ?? "<non-ascii>"
        print("PDFPreviewScreen invalid PDF. data.count=\(pdfData.count) header=\(header)")
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}
