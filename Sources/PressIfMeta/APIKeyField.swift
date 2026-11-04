import AppKit
import SwiftUI

struct APIKeyField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = CyanSecureTextField()
        field.stringValue = text
        field.placeholderString = "API key"
        field.setAccessibilityLabel("API key")
        field.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        field.textColor = PressPalette.editorText
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSSecureTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: APIKeyField
        init(_ parent: APIKeyField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSecureTextField else { return }
            parent.text = field.stringValue
        }
    }
}

private final class CyanSecureTextField: NSSecureTextField {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = PressPalette.editorCaret
            editor.selectedTextAttributes = [.backgroundColor: PressPalette.editorSelection, .foregroundColor: PressPalette.editorSelectionText]
        }
        return accepted
    }
}
