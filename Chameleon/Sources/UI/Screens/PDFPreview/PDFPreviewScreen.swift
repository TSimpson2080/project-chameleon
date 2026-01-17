import PDFKit
import SwiftUI

public struct PDFPreviewScreen: View {
    @Environment(\.dismiss) private var dismiss

    private let title: String
    private let pdfData: Data

    @State private var isPresentingShareSheet = false
    @State private var shareURL: URL?

    public init(title: String, pdfData: Data) {
        self.title = title
        self.pdfData = pdfData
    }

    public var body: some View {
        Group {
            if let document {
                PDFKitView(document: document)
            } else {
                ContentUnavailableView("No PDF", systemImage: "doc", description: Text("Could not open PDF preview."))
                    .onAppear {
                        logInvalidPDF()
                    }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareURL = writeTempPDF()
                    isPresentingShareSheet = shareURL != nil
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
                .disabled(document == nil)
            }
        }
        .sheet(isPresented: $isPresentingShareSheet) {
            if let shareURL {
                ShareSheet(activityItems: [shareURL])
            }
        }
    }

    private var document: PDFDocument? {
        PDFDocument(data: pdfData)
    }

    private func writeTempPDF() -> URL? {
        do {
            let filename = "Chameleon-Draft-\(UUID().uuidString).pdf"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try pdfData.write(to: url, options: [.atomic])
            return url
        } catch {
            assertionFailure("Failed to write temp PDF: \(error)")
            return nil
        }
    }

    private func logInvalidPDF() {
        let header = String(bytes: pdfData.prefix(8), encoding: .ascii) ?? "<non-ascii>"
        print("PDFDocument init failed: bytes=\(pdfData.count) header=\(header)")
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayDirection = .vertical
        view.displayMode = .singlePageContinuous
        view.usePageViewController(true, withViewOptions: nil)
        view.backgroundColor = .systemBackground
        view.document = document
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = document
    }
}
