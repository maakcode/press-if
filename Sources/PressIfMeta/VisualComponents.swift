import AppKit
import SwiftUI
import PressIfCore

struct ApplicationIcon: View {
    let appID: String?
    let catalog: DesktopCatalog
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let icon = catalog.icon(for: appID) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed")
                    .resizable().scaledToFit().padding(size * 0.14)
                    .foregroundStyle(PressPalette.neutral400)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct InfoPill: View {
    let title: String
    let symbol: String
    var accented = false

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(accented ? PressPalette.accent : PressPalette.textSecondary)
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(accented ? PressPalette.accentSurface : PressPalette.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct TaskStatusBadge: View {
    let state: TaskState

    var body: some View {
        InfoPill(title: state.label, symbol: state.symbol, accented: state.isAccented)
    }
}

extension TaskState {
    var symbol: String {
        switch self {
        case .scheduled: return "clock"
        case .running: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .needsReview: return "eye"
        case .failed: return "exclamationmark.octagon"
        case .paused: return "pause.circle"
        case .missed: return "clock.badge.exclamationmark"
        }
    }

    var isAccented: Bool { self == .scheduled || self == .running }
}

struct KeyboardKeys: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                Text(Self.label(key))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PressPalette.textSecondary)
                    .frame(minWidth: 22, minHeight: 23)
                    .padding(.horizontal, 3)
                    .background(PressPalette.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(PressPalette.border, lineWidth: 1) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " + "))
    }

    private static func label(_ key: String) -> String {
        switch key.lowercased() {
        case "command": return "⌘"
        case "control": return "⌃"
        case "option": return "⌥"
        case "shift": return "⇧"
        case "return": return "↵"
        case "escape": return "Esc"
        case "space": return "Space"
        case "tab": return "⇥"
        case "delete": return "⌫"
        default: return key.uppercased()
        }
    }
}

struct ReferenceThumbnail: View {
    let reference: ReferenceImage
    @State private var expanded = false

    var body: some View {
        if let image = NSImage(data: reference.png) {
            Button { expanded = true } label: {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: 130, maxHeight: 64)
                    .padding(8)
                    .background(PressPalette.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay { RoundedRectangle(cornerRadius: 8).stroke(PressPalette.border, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .help("Enlarge target image")
            .accessibilityLabel("Button image to click")
            .popover(isPresented: $expanded) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(maxWidth: 420, maxHeight: 320).padding(20)
                    .background(.white).preferredColorScheme(.light)
            }
        }
    }
}

struct RequestReadback: NSViewRepresentable {
    let document: RequestDocument

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let text = NSTextView(frame: .zero)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = false
        text.insertionPointColor = PressPalette.editorCaret
        text.selectedTextAttributes = [.backgroundColor: PressPalette.editorSelection, .foregroundColor: PressPalette.editorSelectionText]
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 0, height: 4)
        text.setAccessibilityLabel("Original request")
        scroll.documentView = text
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView else { return }
        let content = NSMutableAttributedString()
        for part in document.parts {
            switch part {
            case .text(let value):
                content.append(NSAttributedString(string: value, attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: PressPalette.editorText]))
            case .image(let reference):
                content.append(NSAttributedString(attachment: ReferenceAttachment(reference)))
            }
        }
        if text.attributedString() != content { text.textStorage?.setAttributedString(content) }
    }
}
