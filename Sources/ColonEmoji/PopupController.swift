import AppKit
import SwiftUI

final class PopupModel: ObservableObject {
    @Published var query = ""
    @Published var results: [Emoji] = []
    @Published var selectedIndex = 0
    var onPick: (Emoji) -> Void = { _ in }
}

struct PopupView: View {
    @ObservedObject var model: PopupModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, emoji in
                PopupRow(emoji: emoji, isSelected: index == model.selectedIndex)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.onPick(emoji)
                    }
            }
        }
        .padding(PopupController.padding)
        .frame(width: PopupController.width, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5))
    }
}

struct PopupRow: View {
    let emoji: Emoji
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(emoji.native)
                .font(.system(size: 18))
            Text(":\(emoji.id):")
                .font(.system(size: 13))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: PopupController.rowHeight)
        .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

final class PopupController {
    static let width: CGFloat = 260
    static let rowHeight: CGFloat = 28
    static let maxResults = 8
    static let padding: CGFloat = 4
    private static let gapFromCaret: CGFloat = 4
    private static let tallestHeight = CGFloat(maxResults) * rowHeight + padding * 2

    let model = PopupModel()
    private let panel: NSPanel
    private let hostingView: NSHostingView<PopupView>

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        hostingView = NSHostingView(rootView: PopupView(model: model))
        panel.contentView = hostingView
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var frame: NSRect {
        panel.frame
    }

    func show(results: [Emoji], anchor: PopupAnchor) {
        currentAnchor = anchor
        model.results = results
        model.selectedIndex = 0
        reposition()
        panel.orderFrontRegardless()
    }

    func update(results: [Emoji]) {
        model.results = results
        model.selectedIndex = 0
        reposition()
    }

    func hide() {
        panel.orderOut(nil)
        model.results = []
    }

    func moveSelection(by delta: Int) {
        let count = model.results.count
        if count == 0 {
            return
        }
        model.selectedIndex = (model.selectedIndex + delta + count) % count
    }

    var selectedEmoji: Emoji? {
        model.results.indices.contains(model.selectedIndex) ? model.results[model.selectedIndex] : nil
    }

    private var currentAnchor: PopupAnchor?

    private func reposition() {
        guard let currentAnchor else {
            return
        }
        panel.setFrame(Self.placement(size: hostingView.fittingSize, anchorRect: currentAnchor.rect), display: true)
    }

    /// Picks a direction from the tallest possible list, so the popup doesn't flip sides as results change while typing.
    static func placement(size: NSSize, anchorRect: NSRect) -> NSRect {
        let visible = visibleFrame(nearest: anchorRect)

        let roomBelow = anchorRect.minY - gapFromCaret - visible.minY
        let roomAbove = visible.maxY - (anchorRect.maxY + gapFromCaret)
        let opensDownward = roomBelow >= tallestHeight || roomBelow >= roomAbove
        let y = opensDownward ? anchorRect.minY - gapFromCaret - size.height : anchorRect.maxY + gapFromCaret

        let opensRightward = anchorRect.minX + size.width <= visible.maxX
        let x = opensRightward ? anchorRect.minX : anchorRect.maxX - size.width

        return NSRect(
            x: clamp(x, lower: visible.minX, upper: visible.maxX - size.width),
            y: clamp(y, lower: visible.minY, upper: visible.maxY - size.height),
            width: size.width,
            height: size.height
        )
    }

    /// Uses the screen under the caret, or the closest one when the caret rect sits just off every screen.
    private static func visibleFrame(nearest anchorRect: NSRect) -> NSRect {
        let caretPoint = NSPoint(x: anchorRect.midX, y: anchorRect.midY)
        if let containingScreen = NSScreen.screens.first(where: { $0.frame.contains(caretPoint) }) {
            return containingScreen.visibleFrame
        }
        let nearestScreen = NSScreen.screens.min { left, right in
            distance(from: caretPoint, to: left.frame) < distance(from: caretPoint, to: right.frame)
        }
        return (nearestScreen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private static func distance(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let deltaX = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let deltaY = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return (deltaX * deltaX + deltaY * deltaY).squareRoot()
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
