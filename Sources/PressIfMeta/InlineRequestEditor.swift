import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PressIfCore
import PressIfImaging

@MainActor
final class InlineEditorController: ObservableObject {
    weak var textView: InlineTextView?

    func chooseImage() {
        guard let textView, let window = textView.window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .webP]
        panel.allowsMultipleSelection = true
        panel.message = "Choose an image of the button or icon to find."
        panel.prompt = "Insert image"
        panel.beginSheetModal(for: window) { [weak textView] response in
            guard response == .OK else { return }
            textView?.insertImageFiles(panel.urls)
        }
    }
}

struct InlineRequestEditor: NSViewRepresentable {
    @Binding var document: RequestDocument
    let controller: InlineEditorController
    let onError: (String) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let editor = InlineTextView(frame: .zero)
        editor.isRichText = true
        editor.importsGraphics = true
        editor.isEditable = true
        editor.isSelectable = true
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.font = .systemFont(ofSize: 17)
        editor.textColor = PressPalette.editorText
        editor.insertionPointColor = PressPalette.editorCaret
        editor.selectedTextAttributes = [.backgroundColor: PressPalette.editorSelection, .foregroundColor: PressPalette.editorSelectionText]
        editor.appearance = NSAppearance(named: .aqua)
        editor.textContainerInset = NSSize(width: 5, height: 8)
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        editor.minSize = NSSize(width: 0, height: 150)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.setAccessibilityIdentifier("request-input")
        editor.setAccessibilityLabel("Task and button images")
        editor.onError = onError
        editor.onSubmit = onSubmit
        editor.delegate = context.coordinator
        editor.registerForDraggedTypes([.fileURL, .png, .tiff])
        scroll.documentView = editor
        controller.textView = editor
        editor.render(document)
        context.coordinator.rendered = document
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? InlineTextView else { return }
        editor.onError = onError
        editor.onSubmit = onSubmit
        controller.textView = editor
        if context.coordinator.rendered != document {
            editor.render(document)
            context.coordinator.rendered = document
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InlineRequestEditor
        var rendered = RequestDocument()
        init(_ parent: InlineRequestEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? InlineTextView else { return }
            let value = editor.requestDocument()
            rendered = value
            parent.document = value
        }
    }
}

@MainActor
final class InlineTextView: NSTextView {
    var onError: ((String) -> Void)?
    var onSubmit: (() -> Void)?

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        if let data = board.data(forType: .rtfd), let rich = NSAttributedString(rtfd: data, documentAttributes: nil), rich.containsAttachments {
            do {
                let copy = NSMutableAttributedString(attributedString: rich)
                var replacements: [(NSRange, ReferenceImage)] = []
                copy.enumerateAttribute(.attachment, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
                    guard let attachment = value as? NSTextAttachment,
                          let data = attachment.contents ?? attachment.fileWrapper?.regularFileContents ?? attachment.image?.tiffRepresentation,
                          let reference = try? ImageImport.reference(data: data, name: "Pasted image") else { return }
                    replacements.append((range, reference))
                }
                guard !replacements.isEmpty else { throw PressError.message("Could not read the copied image. Capture the button again.") }
                try checkImageCount(adding: replacements.count)
                for (range, reference) in replacements.reversed() { copy.replaceCharacters(in: range, with: NSAttributedString(attachment: ReferenceAttachment(reference))) }
                insertText(copy, replacementRange: selectedRange())
            } catch { onError?(error.localizedDescription) }
            return
        }
        if let urls = imageURLs(board), !urls.isEmpty { insertImageFiles(urls); return }
        if let image = NSImage(pasteboard: board), let data = image.tiffRepresentation {
            insertImageData(data, name: "Captured button")
            return
        }
        if let text = board.string(forType: .string) {
            insertText(text, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command), event.keyCode == 36 { onSubmit?(); return true }
        return super.performKeyEquivalent(with: event)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canReadImage(sender.draggingPasteboard) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        canReadImage(sender.draggingPasteboard) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard canReadImage(sender.draggingPasteboard) else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        if let urls = imageURLs(sender.draggingPasteboard), !urls.isEmpty {
            insertImageFiles(urls)
            return true
        }
        if let image = NSImage(pasteboard: sender.draggingPasteboard), let data = image.tiffRepresentation {
            insertImageData(data, name: "Dropped button")
            return true
        }
        return false
    }

    func insertImageFiles(_ urls: [URL]) {
        do {
            try checkImageCount(adding: urls.count)
            let images = try urls.map { url in
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 30_000_000 else { throw PressError.message("The image is too large. Crop it to the button.") }
                return try ImageImport.reference(data: Data(contentsOf: url), name: url.lastPathComponent)
            }
            insert(images)
        } catch { onError?(error.localizedDescription) }
    }

    func render(_ document: RequestDocument) {
        let value = NSMutableAttributedString()
        for part in document.parts {
            switch part {
            case .text(let text): value.append(NSAttributedString(string: text, attributes: Self.textAttributes))
            case .image(let image): value.append(NSAttributedString(attachment: ReferenceAttachment(image)))
            }
        }
        textStorage?.setAttributedString(value)
        typingAttributes = Self.textAttributes
        setSelectedRange(NSRange(location: value.length, length: 0))
    }

    func requestDocument() -> RequestDocument {
        guard let storage = textStorage else { return RequestDocument() }
        var parts: [RequestPart] = []
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if let attachment = value as? ReferenceAttachment {
                parts.append(.image(attachment.reference))
            } else {
                let text = (storage.string as NSString).substring(with: range)
                if !text.isEmpty {
                    if case .text(let preceding) = parts.last { parts[parts.count - 1] = .text(preceding + text) }
                    else { parts.append(.text(text)) }
                }
            }
        }
        return RequestDocument(parts: parts)
    }

    private func insertImageData(_ data: Data, name: String) {
        do {
            try checkImageCount(adding: 1)
            insert([try ImageImport.reference(data: data, name: name)])
        } catch { onError?(error.localizedDescription) }
    }

    private func insert(_ images: [ReferenceImage]) {
        let content = NSMutableAttributedString()
        for image in images { content.append(NSAttributedString(attachment: ReferenceAttachment(image))) }
        window?.makeFirstResponder(self)
        insertText(content, replacementRange: selectedRange())
        typingAttributes = Self.textAttributes
    }

    private func checkImageCount(adding count: Int) throws {
        var replacing = 0
        textStorage?.enumerateAttribute(.attachment, in: selectedRange()) { value, _, _ in
            if value is ReferenceAttachment { replacing += 1 }
        }
        guard requestDocument().images.count - replacing + count <= 8 else { throw PressError.message("You can add up to 8 images per request.") }
    }

    private func imageURLs(_ board: NSPasteboard) -> [URL]? {
        (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.filter { url in
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true
        }
    }

    private func canReadImage(_ board: NSPasteboard) -> Bool {
        board.availableType(from: [.png, .tiff]) != nil || !(imageURLs(board) ?? []).isEmpty
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: PressPalette.editorText]
    }
}

final class ReferenceAttachment: NSTextAttachment {
    let reference: ReferenceImage

    init(_ reference: ReferenceImage) {
        self.reference = reference
        super.init(data: reference.png, ofType: UTType.png.identifier)
        image = NSImage(data: reference.png)
        let size = image?.size ?? NSSize(width: 80, height: 50)
        let ratio = min(1, min(140 / max(1, size.width), 60 / max(1, size.height)))
        bounds = CGRect(x: 0, y: -12, width: size.width * ratio, height: size.height * ratio)
    }

    required init?(coder: NSCoder) {
        guard let data = coder.decodeObject(of: NSData.self, forKey: "reference") as Data?, let reference = try? JSONDecoder().decode(ReferenceImage.self, from: data) else { return nil }
        self.reference = reference
        super.init(coder: coder)
    }

    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        if let data = try? JSONEncoder().encode(reference) { coder.encode(data as NSData, forKey: "reference") }
    }
}
