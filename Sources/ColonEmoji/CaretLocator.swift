import AppKit
import ApplicationServices

/// Where on screen the popup should anchor, in Cocoa (bottom-left origin) coordinates.
struct PopupAnchor {
    enum Source: String {
        case caret
        case textField
        case mouse
    }

    /// Popup hangs below this rect, or flips above it when there is no room below.
    let rect: NSRect
    let source: Source
}

final class CaretLocator {
    /// Text fields taller than this are documents/editors, where the field's corner is far from the caret.
    private let maxTextFieldHeightForAnchoring: CGFloat = 120
    /// Messages' whole window is ~160 elements; this bounds the cost in apps with huge trees.
    private let maxDescendantsToSearch = 1500
    private let maxAncestorsToClimb = 60
    private var pidsWithAccessibilityEnabled: Set<pid_t> = []

    func locate() -> PopupAnchor {
        if let reportedFocusedElement = focusedElement() {
            let focusedElement = hasSelectedTextRange(reportedFocusedElement)
                ? reportedFocusedElement
                : focusedTextDescendant(of: reportedFocusedElement) ?? reportedFocusedElement
            if let caretRect = caretRect(in: focusedElement) {
                return PopupAnchor(rect: Self.cocoaRect(fromAccessibilityRect: caretRect), source: .caret)
            }
            if let fieldRect = frame(of: focusedElement), fieldRect.height <= maxTextFieldHeightForAnchoring {
                let leftEdgeOfField = CGRect(x: fieldRect.minX + 8, y: fieldRect.minY, width: 1, height: fieldRect.height)
                return PopupAnchor(rect: Self.cocoaRect(fromAccessibilityRect: leftEdgeOfField), source: .textField)
            }
        }
        let mouseLocation = NSEvent.mouseLocation
        return PopupAnchor(rect: NSRect(x: mouseLocation.x, y: mouseLocation.y - 10, width: 1, height: 20), source: .mouse)
    }

    private func focusedElement() -> AXUIElement? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.2)
        enableAccessibilityTreeIfNeeded(appElement: appElement, pid: frontmostApp.processIdentifier)

        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focused)
        guard result == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        // CFGetTypeID check above guarantees this is an AXUIElement.
        return unsafeBitCast(focused, to: AXUIElement.self)
    }

    /// The site behind the text field, read from the enclosing web area (browsers, and Electron apps like Slack).
    func currentWebHost() -> String? {
        guard let focusedElement = focusedElement() else {
            return nil
        }
        var ancestor: AXUIElement? = focusedElement
        for _ in 0..<maxAncestorsToClimb {
            guard let element = ancestor else {
                break
            }
            if role(of: element) == "AXWebArea" {
                return host(ofWebArea: element)
            }
            ancestor = parent(of: element)
        }
        // Focus is outside the page (e.g. the address bar); fall back to the window's first web area.
        guard let window = parent(of: focusedElement, attribute: kAXWindowAttribute) else {
            return nil
        }
        var queue = [window]
        var visitedCount = 0
        while !queue.isEmpty, visitedCount < maxDescendantsToSearch {
            let element = queue.removeFirst()
            visitedCount += 1
            if role(of: element) == "AXWebArea" {
                return host(ofWebArea: element)
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let childElements = children as? [AXUIElement] {
                queue.append(contentsOf: childElements)
            }
        }
        return nil
    }

    private func host(ofWebArea webArea: AXUIElement) -> String? {
        var urlValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(webArea, kAXURLAttribute as CFString, &urlValue) == .success else {
            return nil
        }
        return (urlValue as? URL)?.host()
    }

    private func role(of element: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success else {
            return nil
        }
        return roleValue as? String
    }

    private func parent(of element: AXUIElement, attribute: String = kAXParentAttribute) -> AXUIElement? {
        var parentValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, attribute as CFString, &parentValue) == .success,
            let parentValue,
            CFGetTypeID(parentValue) == AXUIElementGetTypeID()
        else {
            return nil
        }
        return unsafeBitCast(parentValue, to: AXUIElement.self)
    }

    /// Catalyst apps like Messages report the whole window's content group as focused; the real text field is inside it.
    private func focusedTextDescendant(of root: AXUIElement) -> AXUIElement? {
        var queue = [root]
        var visitedCount = 0
        while !queue.isEmpty, visitedCount < maxDescendantsToSearch {
            let element = queue.removeFirst()
            visitedCount += 1
            if element != root, isFocused(element), hasSelectedTextRange(element) {
                return element
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success,
               let childElements = children as? [AXUIElement] {
                queue.append(contentsOf: childElements)
            }
        }
        return nil
    }

    private func isFocused(_ element: AXUIElement) -> Bool {
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focused) == .success else {
            return false
        }
        return (focused as? Bool) == true
    }

    private func hasSelectedTextRange(_ element: AXUIElement) -> Bool {
        var rangeValue: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success
    }

    /// Chromium and Electron apps only build their accessibility tree once a client asks for it.
    private func enableAccessibilityTreeIfNeeded(appElement: AXUIElement, pid: pid_t) {
        if pidsWithAccessibilityEnabled.contains(pid) {
            return
        }
        pidsWithAccessibilityEnabled.insert(pid)
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    private func caretRect(in element: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        var selectedRange = CFRange()
        guard AXValueGetValue(unsafeBitCast(rangeValue, to: AXValue.self), .cfRange, &selectedRange) else {
            return nil
        }

        if let rect = bounds(of: CFRange(location: selectedRange.location, length: 0), in: element) {
            return rect
        }
        // Many apps return an empty rect for a zero-length range; measure the character before the caret instead.
        if selectedRange.location > 0,
           let previousCharacterRect = bounds(of: CFRange(location: selectedRange.location - 1, length: 1), in: element) {
            return CGRect(x: previousCharacterRect.maxX, y: previousCharacterRect.minY, width: 1, height: previousCharacterRect.height)
        }
        return nil
    }

    private func bounds(of range: CFRange, in element: AXUIElement) -> CGRect? {
        var mutableRange = range
        guard let rangeParameter = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }
        var boundsValue: CFTypeRef?
        guard
            AXUIElementCopyParameterizedAttributeValue(
                element,
                kAXBoundsForRangeParameterizedAttribute as CFString,
                rangeParameter,
                &boundsValue
            ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID()
        else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(unsafeBitCast(boundsValue, to: AXValue.self), .cgRect, &rect) else {
            return nil
        }
        return Self.isPlausibleOnScreen(rect) ? rect : nil
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
            let positionValue,
            let sizeValue,
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else {
            return nil
        }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard
            AXValueGetValue(unsafeBitCast(positionValue, to: AXValue.self), .cgPoint, &position),
            AXValueGetValue(unsafeBitCast(sizeValue, to: AXValue.self), .cgSize, &size)
        else {
            return nil
        }
        let rect = CGRect(origin: position, size: size)
        return Self.isPlausibleOnScreen(rect) ? rect : nil
    }

    /// Rejects the (0,0) and zero-size rects that broken apps report, which is what puts Rocket in the corner.
    private static func isPlausibleOnScreen(_ accessibilityRect: CGRect) -> Bool {
        if accessibilityRect.height <= 0 {
            return false
        }
        if accessibilityRect.origin == .zero {
            return false
        }
        let cocoaRect = cocoaRect(fromAccessibilityRect: accessibilityRect)
        return NSScreen.screens.contains { $0.frame.intersects(cocoaRect.insetBy(dx: -1, dy: -1)) }
    }

    /// Accessibility uses a top-left origin anchored to the primary screen; Cocoa uses bottom-left.
    static func cocoaRect(fromAccessibilityRect rect: CGRect) -> NSRect {
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }
}
