import AppKit
import SwiftUI

/// Explicit widths prevent a segment from widening under the pointer on its first selection.
struct SteadySegmentedPicker<Value: Hashable>: NSViewRepresentable {
    @Environment(\.metrics) private var metrics

    struct Option {
        let value: Value
        let title: String
    }

    let title: String
    let options: [Option]
    @Binding var selection: Value

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map(\.title), trackingMode: .selectOne,
            target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.setAccessibilityLabel(title)
        applyFont(to: control, force: true)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        applyFont(to: control)
        control.selectedSegment = options.firstIndex { $0.value == selection } ?? -1
    }

    private func applyFont(to control: NSSegmentedControl, force: Bool = false) {
        let font = metrics.typography.controlNSFont
        guard force || control.font != font else { return }
        control.font = font
        for (index, option) in options.enumerated() {
            let label = (option.title as NSString).size(withAttributes: [.font: font]).width
            control.setWidth(
                (label + Theme.Size.segmentLabelInset * 2).rounded(.up), forSegment: index)
        }
    }

    /// The control's own idea of its width also shrinks after the first switch, so it is not asked.
    func sizeThatFits(
        _ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context
    ) -> CGSize? {
        let width = (0..<nsView.segmentCount).reduce(0) { $0 + nsView.width(forSegment: $1) }
        return CGSize(width: width, height: nsView.intrinsicContentSize.height)
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SteadySegmentedPicker

        init(_ parent: SteadySegmentedPicker) {
            self.parent = parent
        }

        @objc func changed(_ sender: NSSegmentedControl) {
            guard parent.options.indices.contains(sender.selectedSegment) else { return }
            parent.selection = parent.options[sender.selectedSegment].value
        }
    }
}
