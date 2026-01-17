import SwiftUI
import UIKit

public struct ShareSheet: UIViewControllerRepresentable {
    public let activityItems: [Any]
    public let applicationActivities: [UIActivity]?

    public init(activityItems: [Any], applicationActivities: [UIActivity]? = nil) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
    }

    public func makeUIViewController(context: Context) -> UIActivityViewController {
        precondition(!activityItems.isEmpty, "ShareSheet requires at least one activity item.")

        let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)

        DispatchQueue.main.async {
            if let popover = controller.popoverPresentationController {
                popover.sourceView = controller.view
                popover.sourceRect = CGRect(
                    x: controller.view.bounds.midX,
                    y: controller.view.bounds.midY,
                    width: 0,
                    height: 0
                )
                popover.permittedArrowDirections = []
            }
        }

        return controller
    }

    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

