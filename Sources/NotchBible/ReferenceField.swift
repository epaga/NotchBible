import AppKit
import SwiftUI

/// A real AppKit field editor preserves standard selection, paste, undo, and
/// input methods in a borderless panel. Edits publish in the same event turn.
struct ReferenceField: NSViewRepresentable {
    @ObservedObject var model: LookupModel

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 21, weight: .regular)
        field.textColor = NSColor(calibratedRed: 0.94, green: 0.92, blue: 0.87, alpha: 1)
        field.placeholderAttributedString = NSAttributedString(string: "Genesis 1:1", attributes: [
            .foregroundColor: NSColor(calibratedWhite: 0.48, alpha: 1),
            .font: NSFont.systemFont(ofSize: 21)
        ])
        field.delegate = context.coordinator
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel("Bible reference")
        field.setAccessibilityHelp("Enter a reference, such as Genesis 1:1 or gen1.1-2.3. Results appear as you type.")
        field.lineBreakMode = .byTruncatingHead
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        if field.stringValue != model.query { field.stringValue = model.query }
        if coordinator.lastFocusRequest != model.focusRequest {
            coordinator.lastFocusRequest = model.focusRequest
            DispatchQueue.main.async { [weak field] in
                guard let field, let window = field.window else { return }
                window.makeFirstResponder(field)
                if let editor = field.currentEditor() as? NSTextView {
                    editor.insertionPointColor = NSColor(calibratedRed: 0.89, green: 0.71, blue: 0.43, alpha: 1)
                    editor.selectedTextAttributes = [.backgroundColor: NSColor(calibratedWhite: 1, alpha: 0.17)]
                    editor.selectAll(nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var model: LookupModel
        var lastFocusRequest = 0
        init(model: LookupModel) { self.model = model }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.query = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.cancelOperation(_:)): model.onDismiss?(); return true
            case #selector(NSResponder.insertNewline(_:)): model.submit(); return true
            case #selector(NSResponder.moveDown(_:)):
                guard !model.result.suggestions.isEmpty else { return false }
                model.moveSuggestion(1); return true
            case #selector(NSResponder.moveUp(_:)):
                guard !model.result.suggestions.isEmpty else { return false }
                model.moveSuggestion(-1); return true
            case #selector(NSResponder.insertTab(_:)):
                guard !model.result.suggestions.isEmpty else { return false }
                model.submit(); return true
            default: return false
            }
        }
    }
}
