import SwiftUI
import UIKit

public struct SignatureCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[CGPoint]] = []
    @State private var signatureName: String
    @State private var errorMessage: String?

    let title: String
    let onSave: (String, UIImage) throws -> Void

    public init(title: String, initialName: String, onSave: @escaping (String, UIImage) throws -> Void) {
        self.title = title
        self._signatureName = State(initialValue: initialName)
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Name", text: $signatureName)
                        .textInputAutocapitalization(.words)
                }

                Section("Signature") {
                    SignaturePad(strokes: $strokes)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 1)
                        }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { strokes.removeAll() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaveDisabled)
                }
            }
        }
    }

    private var isSaveDisabled: Bool {
        signatureName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || strokes.isEmpty
    }

    private func save() {
        errorMessage = nil

        let trimmed = signatureName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Name is required."
            return
        }

        guard let image = SignaturePad.renderImage(strokes: strokes, size: CGSize(width: 900, height: 300)) else {
            errorMessage = "Could not render signature."
            return
        }

        do {
            try onSave(trimmed, image)
            dismiss()
        } catch {
            errorMessage = "Could not save signature."
        }
    }
}

private struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]
    @State private var currentStroke: [CGPoint] = []

    var body: some View {
        Canvas { context, size in
            let background = Path(CGRect(origin: .zero, size: size))
            context.fill(background, with: .color(.white))

            for stroke in strokes {
                draw(stroke: stroke, in: &context)
            }
            draw(stroke: currentStroke, in: &context)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    currentStroke.append(value.location)
                }
                .onEnded { _ in
                    if !currentStroke.isEmpty {
                        strokes.append(currentStroke)
                        currentStroke = []
                    }
                }
        )
    }

    private func draw(stroke: [CGPoint], in context: inout GraphicsContext) {
        guard stroke.count > 1 else { return }
        var path = Path()
        path.addLines(stroke)
        context.stroke(path, with: .color(.black), lineWidth: 2)
    }

    static func renderImage(strokes: [[CGPoint]], size: CGSize) -> UIImage? {
        let view = SignaturePadSnapshot(strokes: strokes)
            .frame(width: size.width, height: size.height)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage
    }
}

private struct SignaturePadSnapshot: View {
    let strokes: [[CGPoint]]

    var body: some View {
        Canvas { context, size in
            let background = Path(CGRect(origin: .zero, size: size))
            context.fill(background, with: .color(.white))

            for stroke in strokes {
                guard stroke.count > 1 else { continue }
                var path = Path()
                path.addLines(stroke)
                context.stroke(path, with: .color(.black), lineWidth: 2)
            }
        }
    }
}
