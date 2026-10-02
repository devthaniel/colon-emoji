import AppKit
import Carbon.HIToolbox

/// Watches every keystroke system-wide, tracks a `:query` being typed, and swaps it for the chosen emoji.
final class KeyMonitor {
    private enum State {
        case idle
        case capturing(query: String)
    }

    /// Tags events we synthesize so the tap ignores its own backspaces and emoji.
    private static let syntheticEventMarker: Int64 = 0x3A_E3_0_71

    private let store: EmojiStore
    private let popup: PopupController
    private let locator: CaretLocator
    private let isEnabledWhereTyping: () -> Bool
    private var eventTap: CFMachPort?
    private var state = State.idle
    /// `:` only starts a search after whitespace or a fresh cursor position, so `10:30` and `https://` don't trigger.
    private var previousCharacterWasBoundary = true
    private var anchor: PopupAnchor?

    init(store: EmojiStore, popup: PopupController, locator: CaretLocator, isEnabledWhereTyping: @escaping () -> Bool) {
        self.store = store
        self.popup = popup
        self.locator = locator
        self.isEnabledWhereTyping = isEnabledWhereTyping
        popup.model.onPick = { [weak self] emoji in
            self?.commit(emoji)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reset(boundary: true)
        }
    }

    var isRunning: Bool {
        eventTap != nil
    }

    func start() -> Bool {
        if eventTap != nil {
            return true
        }
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: { _, type, event, refcon in
                    guard let refcon else {
                        return Unmanaged.passUnretained(event)
                    }
                    let monitor = Unmanaged<KeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    return monitor.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let passThrough = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return passThrough
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticEventMarker {
            return passThrough
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            if popup.isVisible, popup.frame.contains(NSEvent.mouseLocation) {
                return passThrough
            }
            reset(boundary: true)
            return passThrough
        }
        guard type == .keyDown else {
            return passThrough
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) {
            reset(boundary: true)
            return passThrough
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        let typed = Self.characters(of: event)

        switch state {
        case .idle:
            if typed == ":" && previousCharacterWasBoundary {
                previousCharacterWasBoundary = false
                if isEnabledWhereTyping() {
                    state = .capturing(query: "")
                }
                return passThrough
            }
            if keyCode == kVK_Delete {
                return passThrough
            }
            previousCharacterWasBoundary = Self.isBoundary(typed: typed, keyCode: keyCode)
            return passThrough

        case .capturing(let query):
            return handleWhileCapturing(query: query, keyCode: keyCode, typed: typed, passThrough: passThrough)
        }
    }

    private func handleWhileCapturing(
        query: String,
        keyCode: Int,
        typed: String,
        passThrough: Unmanaged<CGEvent>
    ) -> Unmanaged<CGEvent>? {
        let popupHasResults = popup.isVisible && popup.selectedEmoji != nil

        switch keyCode {
        case kVK_DownArrow where popupHasResults:
            popup.moveSelection(by: 1)
            return nil
        case kVK_UpArrow where popupHasResults:
            popup.moveSelection(by: -1)
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab:
            if popupHasResults, let emoji = popup.selectedEmoji {
                commit(emoji)
                return nil
            }
            reset(boundary: true)
            return passThrough
        case kVK_Escape:
            let wasVisible = popup.isVisible
            reset(boundary: false)
            return wasVisible ? nil : passThrough
        case kVK_Delete:
            if query.isEmpty {
                reset(boundary: true)
            } else {
                updateQuery(String(query.dropLast()))
            }
            return passThrough
        default:
            break
        }

        if typed == ":" && !query.isEmpty {
            // Typing the closing colon of an exact shortcode (`:fire:`) converts it immediately.
            if let emoji = store.exactMatch(shortcode: query.lowercased()) {
                commit(emoji)
                return nil
            }
            reset(boundary: false)
            return passThrough
        }

        if typed.count == 1, let character = typed.first, Self.isShortcodeCharacter(character) {
            updateQuery(query + typed)
            return passThrough
        }

        reset(boundary: Self.isBoundary(typed: typed, keyCode: keyCode))
        return passThrough
    }

    private func updateQuery(_ query: String) {
        state = .capturing(query: query)
        popup.model.query = query
        let results = store.search(query, limit: PopupController.maxResults)
        if results.isEmpty {
            popup.hide()
            return
        }
        if popup.isVisible {
            popup.update(results: results)
            return
        }
        let resolvedAnchor = anchor ?? locator.locate()
        anchor = resolvedAnchor
        popup.show(results: results, anchor: resolvedAnchor)
    }

    private func commit(_ emoji: Emoji) {
        guard case .capturing(let query) = state else {
            return
        }
        let charactersToDelete = query.count + 1
        reset(boundary: false)
        store.recordUse(emoji)
        // Post after the tap callback returns so the swallowed keystroke is fully gone first.
        DispatchQueue.main.async {
            Self.typeReplacement(deleting: charactersToDelete, inserting: emoji.native)
        }
    }

    private func reset(boundary: Bool) {
        state = .idle
        anchor = nil
        previousCharacterWasBoundary = boundary
        if popup.isVisible {
            popup.hide()
        }
    }

    private static func typeReplacement(deleting count: Int, inserting text: String) {
        let source = CGEventSource(stateID: .privateState)
        for _ in 0..<count {
            postKey(code: CGKeyCode(kVK_Delete), source: source)
        }
        let utf16 = Array(text.utf16)
        for isKeyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: isKeyDown) else {
                continue
            }
            event.flags = []
            event.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func postKey(code: CGKeyCode, source: CGEventSource?) {
        for isKeyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: isKeyDown) else {
                continue
            }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    private static func characters(of event: CGEvent) -> String {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(maxStringLength: buffer.count, actualStringLength: &length, unicodeString: &buffer)
        return String(utf16CodeUnits: buffer, count: length)
    }

    private static func isShortcodeCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "-" || character == "+"
    }

    private static func isBoundary(typed: String, keyCode: Int) -> Bool {
        let navigationKeys = [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow, kVK_Return, kVK_Tab]
        if navigationKeys.contains(keyCode) {
            return true
        }
        guard let character = typed.first else {
            return false
        }
        return character.isWhitespace || "([{\"'".contains(character)
    }
}
