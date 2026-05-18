import AppKit

private final class IndicatorPanel: NSPanel {
    init(size: NSSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class IndicatorView: NSView {
    var text: String = "" { didSet { needsDisplay = true } }
    var background: NSColor = .black { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        background.setFill()
        path.fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 26, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph
        ]
        let attrText = NSAttributedString(string: text, attributes: attrs)
        let textSize = attrText.size()
        let rect = NSRect(
            x: (bounds.width - textSize.width) / 2,
            y: (bounds.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        attrText.draw(in: rect)
    }
}

final class IndicatorOverlay {
    private let panel: IndicatorPanel
    private let view: IndicatorView
    private var hideTimer: Timer?

    private let size = NSSize(width: 64, height: 56)

    init() {
        panel = IndicatorPanel(size: size)
        view = IndicatorView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = view
    }

    func show(text: String, color: NSColor, duration: TimeInterval = 0.6) {
        view.text = text
        view.background = color

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var origin = NSPoint(x: mouse.x + 18, y: mouse.y - size.height - 18)
        if let visible = screen?.visibleFrame {
            origin.x = max(visible.minX, min(origin.x, visible.maxX - size.width))
            origin.y = max(visible.minY, min(origin.y, visible.maxY - size.height))
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.panel.orderOut(nil)
        }
    }
}
