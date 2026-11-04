import AppKit
import ApplicationServices
import PressIfCore
import PressIfImaging

struct ElementHandle {
    let description: ScreenElement
    let accessibility: AXUIElement?
    let bounds: CGRect
}

struct DesktopSnapshot {
    let observation: ScreenObservation
    let handles: [ElementHandle]
    let image: Data?
    let windowTitle: String
    let window: AXUIElement
}

@MainActor
final class DesktopScreen {
    func observe(application: NSRunningApplication, includeImage: Bool, reference: ReferenceImage? = nil) async throws -> DesktopSnapshot {
        try ensureForeground(application)
        let root = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 2)
        guard let rawWindow = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            throw PressError.message("Could not read the active window. Check Accessibility permission.")
        }
        let window = rawWindow as! AXUIElement
        let title = string(window, kAXTitleAttribute)
        let identity = WindowIdentity(title: title, bounds: frame(window))
        var handles = accessibilityElements(root: window)
        var image: Data?
        if includeImage && CGPreflightScreenCaptureAccess() {
            let capture = try await WindowCapture.capture(pid: application.processIdentifier, expected: identity)
            image = capture.png
            if let reference {
                handles = try await imageHandles(reference, capture: capture, accessibility: handles)
            } else {
                for (text, bounds) in try WindowCapture.textElements(in: capture) {
                    let duplicate = handles.contains { $0.description.label == text && $0.bounds.intersects(bounds) }
                    guard !duplicate else { continue }
                    let element = ScreenElement(id: "ocr-\(handles.count)", role: "OCRText", label: text, context: title, actionable: true)
                    handles.append(ElementHandle(description: element, accessibility: nil, bounds: bounds))
                }
            }
        }
        if reference != nil && image == nil { throw PressError.message("Image search requires window image analysis and Screen Recording permission.") }
        try ensureForeground(application)
        guard let focusedWindow = attribute(root, kAXFocusedWindowAttribute), CFEqual(window, focusedWindow),
              WindowIdentity(title: string(window, kAXTitleAttribute), bounds: frame(window)) == identity else {
            throw PressError.message("Stopped because the active window changed during capture.")
        }
        guard !handles.isEmpty else { throw PressError.message("Could not read screen controls. Enable Screen Recording to search by image.") }
        let observation = ScreenObservation(app: application.bundleIdentifier ?? "", elements: handles.map(\.description))
        return DesktopSnapshot(observation: observation, handles: handles, image: image, windowTitle: title, window: window)
    }

    func revalidated(_ selected: ElementHandle, previous: DesktopSnapshot, application: NSRunningApplication, includeImage: Bool, reference: ReferenceImage? = nil, requireUnchangedValue: Bool = false) async throws -> ElementHandle {
        let current = try await observe(application: application, includeImage: includeImage, reference: reference)
        guard CFEqual(current.window, previous.window), current.windowTitle == previous.windowTitle else { throw PressError.message("Stopped because the window changed during analysis.") }
        let handle = try matching(selected, in: current)
        if requireUnchangedValue && handle.description.numericControl?.value != selected.description.numericControl?.value {
            throw PressError.message("Stopped because the numeric value changed during analysis.")
        }
        return handle
    }

    private func matching(_ selected: ElementHandle, in current: DesktopSnapshot) throws -> ElementHandle {
        let matches = current.handles.filter { handle in
            handle.description.role == selected.description.role && handle.description.label == selected.description.label &&
            (selected.description.numericControl == nil || handle.description.context == selected.description.context) &&
            handle.description.actionable && abs(handle.bounds.midX - selected.bounds.midX) < 5 && abs(handle.bounds.midY - selected.bounds.midY) < 5 &&
            abs(handle.bounds.width - selected.bounds.width) < 5 && abs(handle.bounds.height - selected.bounds.height) < 5
        }
        guard matches.count == 1, let handle = matches.first else {
            throw PressError.message("Stopped because the target changed or became ambiguous.")
        }
        return handle
    }

    func setNumber(_ number: Double, on handle: ElementHandle, previous: DesktopSnapshot, application: NSRunningApplication) async throws {
        try ensureForeground(application)
        try NumericControlPolicy.validate(number, on: handle.description)
        guard let element = handle.accessibility else { throw PressError.message("Could not read accessibility data for the numeric control.") }
        if handle.description.numericControl?.value != number {
            if try !DesktopNumericControl.writeNumber(number, to: element) {
                try click(handle, application: application)
                try await Task.sleep(for: .milliseconds(150))
                for digit in String(Int(number)) {
                    try ensureForeground(application)
                    try DesktopKeyboard.press([String(digit)])
                    try await Task.sleep(for: .milliseconds(60))
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        let current = try await revalidated(handle, previous: previous, application: application, includeImage: false)
        try NumericControlPolicy.verify(number, on: current.description)
    }

    func verifyNumbers(_ values: [(handle: ElementHandle, number: Double)], windowTitle: String, application: NSRunningApplication) async throws {
        guard !values.isEmpty else { return }
        let snapshot = try await observe(application: application, includeImage: false)
        guard snapshot.windowTitle == windowTitle else { throw PressError.message("Stopped because the window containing the numeric control changed.") }
        for value in values {
            let handle = try matching(value.handle, in: snapshot)
            try NumericControlPolicy.verify(value.number, on: handle.description)
        }
    }

    private func imageHandles(_ reference: ReferenceImage, capture: CapturedWindow, accessibility: [ElementHandle]) async throws -> [ElementHandle] {
        let template = try ImageImport.decode(reference.png)
        let search = Task.detached(priority: .userInitiated) { try ImageSearch.matches(reference: template, screen: capture.image) }
        let matches = try await withTaskCancellationHandler(operation: { try await search.value }, onCancel: { search.cancel() })
        guard !matches.isEmpty else { throw PressError.message("Could not find the button image in this window. Check that it is visible or capture it again.") }
        guard matches.count == 1 else { throw PressError.message("Multiple matching images found. Capture the button with more surrounding context.") }
        return matches.enumerated().compactMap { index, match in
            let normalized = match.normalizedRect
            let bounds = CGRect(x: capture.bounds.minX + normalized.minX * capture.bounds.width,
                                y: capture.bounds.minY + normalized.minY * capture.bounds.height,
                                width: normalized.width * capture.bounds.width, height: normalized.height * capture.bounds.height)
            let containing = accessibility.filter { $0.description.actionable && $0.bounds.contains(CGPoint(x: bounds.midX, y: bounds.midY)) }
            let disabled = accessibility.contains { !$0.description.actionable && [kAXButtonRole, kAXRadioButtonRole, kAXCheckBoxRole, kAXPopUpButtonRole].contains($0.description.role) && $0.bounds.contains(CGPoint(x: bounds.midX, y: bounds.midY)) }
            guard !disabled else { return nil }
            let element = containing.count == 1 ? containing.first?.accessibility : nil
            let context = String(format: "normalized top-left x=%.4f y=%.4f width=%.4f height=%.4f; visual score=%.3f", normalized.minX, normalized.minY, normalized.width, normalized.height, match.score)
            let description = ScreenElement(id: "image-match-\(index)", role: "ImageMatch", label: "Area matching the reference image", context: context, actionable: true)
            return ElementHandle(description: description, accessibility: element, bounds: bounds)
        }
    }

    func click(_ handle: ElementHandle, application: NSRunningApplication) throws {
        try ensureForeground(application)
        if let element = handle.accessibility {
            var actions: CFArray?
            AXUIElementCopyActionNames(element, &actions)
            if (actions as? [String] ?? []).contains(kAXPressAction) {
                guard AXUIElementPerformAction(element, kAXPressAction as CFString) == .success else {
                    throw PressError.message("Could not deliver the click. Stopped without retrying.")
                }
                return
            }
        }
        guard !handle.bounds.isEmpty, handle.bounds.width.isFinite, handle.bounds.height.isFinite else {
            throw PressError.message("The click location is invalid.")
        }
        let point = CGPoint(x: handle.bounds.midX, y: handle.bounds.midY)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            throw PressError.message("Could not create a mouse input event.")
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    func ensureForeground(_ application: NSRunningApplication) throws {
        try Task.checkCancellation()
        guard !application.isTerminated, NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            throw PressError.message("Stopped because another app became active.")
        }
        if let session = CGSessionCopyCurrentDictionary() as? [String: Any], session["CGSSessionScreenIsLocked"] as? Bool == true {
            throw PressError.message("Stopped because the screen is locked.")
        }
    }

    func ensureTextInput(_ application: NSRunningApplication) throws {
        try ensureForeground(application)
        let root = AXUIElementCreateApplication(application.processIdentifier)
        guard let raw = attribute(root, kAXFocusedUIElementAttribute), CFGetTypeID(raw) == AXUIElementGetTypeID() else {
            throw PressError.message("No text field is focused.")
        }
        let focused = raw as! AXUIElement
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(string(focused, kAXRoleAttribute)),
              string(focused, kAXSubroleAttribute) != kAXSecureTextFieldSubrole else {
            throw PressError.message("Typing requires a focused, editable text field.")
        }
    }

    private func accessibilityElements(root: AXUIElement) -> [ElementHandle] {
        var pending: [(AXUIElement, String, Int)] = [(root, "", 0)]
        var result: [ElementHandle] = []
        var visited = 0
        let windowBounds = frame(root)
        while let (element, parent, depth) = pending.popLast(), visited < 1400, result.count < 350 {
            visited += 1
            let role = string(element, kAXRoleAttribute)
            if string(element, kAXSubroleAttribute) == kAXSecureTextFieldSubrole { continue }
            let title = string(element, kAXTitleAttribute)
            let description = string(element, kAXDescriptionAttribute)
            let help = string(element, kAXHelpAttribute)
            let label = [title, description, help].first { !$0.isEmpty } ?? ""
            let value = string(element, kAXValueAttribute)
            let bounds = frame(element)
            let enabled = attribute(element, kAXEnabledAttribute) as? Bool ?? true
            let hidden = attribute(element, "AXHidden") as? Bool ?? false
            let numericControl = NumericControlPolicy.roles.contains(role) ? DesktopNumericControl.state(of: element) : nil
            let actionableRoles: Set<String> = [kAXButtonRole, kAXRadioButtonRole, kAXCheckBoxRole, kAXTextFieldRole, kAXTextAreaRole, kAXPopUpButtonRole, kAXMenuItemRole, kAXMenuButtonRole, "AXLink", "AXTab", "AXCell", "AXRow"]
            let visible = !bounds.isEmpty && windowBounds.intersects(bounds)
            if !hidden, visible, !label.isEmpty || !value.isEmpty {
                let actionable = enabled && windowBounds.contains(CGPoint(x: bounds.midX, y: bounds.midY)) && (actionableRoles.contains(role) || numericControl?.settable == true)
                let description = ScreenElement(id: "ax-\(result.count)", role: role, label: String(label.prefix(300)), value: String(value.prefix(700)), context: String(parent.suffix(300)), actionable: actionable, numericControl: numericControl)
                result.append(ElementHandle(description: description, accessibility: element, bounds: bounds))
            }
            guard depth < 16, !hidden else { continue }
            let context = label.isEmpty ? parent : String((parent + " / " + label).suffix(300))
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            pending.append(contentsOf: children.reversed().map { ($0, context, depth + 1) })
        }
        return result
    }

    private func attribute(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }

    private func string(_ element: AXUIElement, _ key: String) -> String {
        let value = attribute(element, key)
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return number.stringValue }
        return ""
    }

    private func frame(_ element: AXUIElement) -> CGRect {
        guard let rawPosition = attribute(element, kAXPositionAttribute), let rawSize = attribute(element, kAXSizeAttribute),
              CFGetTypeID(rawPosition) == AXValueGetTypeID(), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return .zero }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &point), AXValueGetValue(rawSize as! AXValue, .cgSize, &size) else { return .zero }
        return CGRect(origin: point, size: size)
    }
}
