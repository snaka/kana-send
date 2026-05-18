import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let keyTap = KeyTapManager()
    private let overlay = IndicatorOverlay()
    private let settings = SettingsStore()

    private let thresholdOptions = [200, 300, 500, 700, 1000]

    private let alphaColor = NSColor(srgbRed: 0.20, green: 0.50, blue: 0.90, alpha: 0.88)
    private let kanaColor  = NSColor(srgbRed: 0.90, green: 0.30, blue: 0.30, alpha: 0.88)
    private let cmdColor   = NSColor(srgbRed: 0.15, green: 0.15, blue: 0.15, alpha: 0.88)

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        wireKeyTap()
        if settings.isEnabled {
            launchKeyTap()
        }
    }

    // MARK: - Status item / menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "あ"
        statusItem.button?.toolTip = "kana-send"

        let menu = NSMenu()

        let enabledItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled(_:)),
            keyEquivalent: ""
        )
        enabledItem.target = self
        enabledItem.state = settings.isEnabled ? .on : .off
        menu.addItem(enabledItem)

        let indicatorItem = NSMenuItem(
            title: "Show indicator",
            action: #selector(toggleIndicator(_:)),
            keyEquivalent: ""
        )
        indicatorItem.target = self
        indicatorItem.state = settings.showIndicator ? .on : .off
        menu.addItem(indicatorItem)

        menu.addItem(NSMenuItem.separator())

        let thresholdItem = NSMenuItem(title: "Hold threshold", action: nil, keyEquivalent: "")
        let thresholdSubmenu = NSMenu()
        for ms in thresholdOptions {
            let item = NSMenuItem(
                title: "\(ms) ms",
                action: #selector(selectThreshold(_:)),
                keyEquivalent: ""
            )
            item.tag = ms
            item.target = self
            item.state = (ms == settings.holdThresholdMs) ? .on : .off
            thresholdSubmenu.addItem(item)
        }
        thresholdItem.submenu = thresholdSubmenu
        menu.addItem(thresholdItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit kana-send",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Key tap wiring

    private func wireKeyTap() {
        keyTap.holdThresholdMs = settings.holdThresholdMs
        keyTap.onAlphaTriggered = { [weak self] in
            guard let self = self, self.settings.showIndicator else { return }
            self.overlay.show(text: "A", color: self.alphaColor)
        }
        keyTap.onKanaTriggered = { [weak self] in
            guard let self = self, self.settings.showIndicator else { return }
            self.overlay.show(text: "あ", color: self.kanaColor)
        }
        keyTap.onCmdActivated = { [weak self] in
            guard let self = self, self.settings.showIndicator else { return }
            self.overlay.show(text: "⌘", color: self.cmdColor)
        }
    }

    private func launchKeyTap() {
        if !keyTap.start() {
            promptAccessibilityPermission()
        }
    }

    // MARK: - Menu actions

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        settings.isEnabled.toggle()
        sender.state = settings.isEnabled ? .on : .off
        if settings.isEnabled {
            launchKeyTap()
        } else {
            keyTap.stop()
        }
    }

    @objc private func toggleIndicator(_ sender: NSMenuItem) {
        settings.showIndicator.toggle()
        sender.state = settings.showIndicator ? .on : .off
    }

    @objc private func selectThreshold(_ sender: NSMenuItem) {
        let ms = sender.tag
        settings.holdThresholdMs = ms
        keyTap.holdThresholdMs = ms
        sender.menu?.items.forEach { $0.state = ($0.tag == ms) ? .on : .off }
    }

    // MARK: - Accessibility prompt

    private func promptAccessibilityPermission() {
        let alert = NSAlert()
        alert.messageText = "Accessibility permission required"
        alert.informativeText = """
        kana-send needs Accessibility permission to intercept the Command keys.

        Open System Settings → Privacy & Security → Accessibility,
        enable kana-send, then restart this app.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
