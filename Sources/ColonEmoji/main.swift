import AppKit
import ApplicationServices
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = EmojiStore()
    private let popup = PopupController()
    private let locator = CaretLocator()
    private let exclusions = ExclusionList()
    private lazy var keyMonitor = KeyMonitor(
        store: store,
        popup: popup,
        locator: locator,
        isEnabledWhereTyping: { [weak self] in
            guard let self, let context = self.currentTypingContext() else {
                return true
            }
            return !self.exclusions.isDisabled(in: context)
        }
    )
    private var statusItem: NSStatusItem?
    private var permissionPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = ":)"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(promptOptions) {
            startMonitoring()
            return
        }
        // Permission is granted in System Settings while we run; start as soon as it lands.
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else {
                return
            }
            timer.invalidate()
            self?.startMonitoring()
        }
    }

    private func startMonitoring() {
        if !keyMonitor.start() {
            NSLog("ColonEmoji: event tap creation failed even though Accessibility is trusted")
        }
    }

    /// Status-item menus don't activate this app, so the frontmost app is still the one being typed in.
    private func currentTypingContext() -> TypingContext? {
        guard
            let frontmostApp = NSWorkspace.shared.frontmostApplication,
            let bundleId = frontmostApp.bundleIdentifier,
            bundleId != Bundle.main.bundleIdentifier
        else {
            return nil
        }
        return TypingContext(
            appBundleId: bundleId,
            appName: frontmostApp.localizedName ?? ExclusionList.displayName(forBundleId: bundleId),
            host: locator.currentWebHost()
        )
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let statusTitle = keyMonitor.isRunning ? "Active: type :name to search" : "Waiting for Accessibility permission…"
        menu.addItem(disabledItem(statusTitle))
        if !keyMonitor.isRunning {
            menu.addItem(actionItem("Open Accessibility Settings…", action: #selector(openAccessibilitySettings)))
        }

        menu.addItem(.separator())
        if let context = currentTypingContext() {
            let appItem = actionItem("Turn Off in \(context.appName)", action: #selector(toggleApp(_:)))
            appItem.representedObject = context.appBundleId
            appItem.state = exclusions.isAppDisabled(context.appBundleId) ? .on : .off
            menu.addItem(appItem)
            if let host = context.host {
                let hostItem = actionItem("Turn Off on \(host)", action: #selector(toggleHost(_:)))
                hostItem.representedObject = host
                hostItem.state = exclusions.isHostDisabled(host) ? .on : .off
                menu.addItem(hostItem)
            }
        }
        menu.addItem(turnedOffSubmenuItem())

        menu.addItem(.separator())
        let launchAtLogin = actionItem("Launch at Login", action: #selector(toggleLaunchAtLogin))
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLogin)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ColonEmoji", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func turnedOffSubmenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for bundleId in exclusions.disabledBundleIds {
            let item = actionItem(ExclusionList.displayName(forBundleId: bundleId), action: #selector(toggleApp(_:)))
            item.representedObject = bundleId
            item.state = .on
            submenu.addItem(item)
        }
        for host in exclusions.disabledHosts {
            let item = actionItem(host, action: #selector(toggleHost(_:)))
            item.representedObject = host
            item.state = .on
            submenu.addItem(item)
        }
        if submenu.items.isEmpty {
            submenu.addItem(disabledItem("Nothing yet"))
        } else {
            submenu.addItem(.separator())
            submenu.addItem(disabledItem("Click one to turn it back on"))
        }
        let parent = NSMenuItem(title: "Turned Off For", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func actionItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleApp(_ sender: NSMenuItem) {
        guard let bundleId = sender.representedObject as? String else {
            return
        }
        exclusions.setApp(bundleId, disabled: !exclusions.isAppDisabled(bundleId))
    }

    @objc private func toggleHost(_ sender: NSMenuItem) {
        guard let host = sender.representedObject as? String else {
            return
        }
        exclusions.setHost(host, disabled: !exclusions.isHostDisabled(host))
    }

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("ColonEmoji: launch-at-login toggle failed: \(error.localizedDescription)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
