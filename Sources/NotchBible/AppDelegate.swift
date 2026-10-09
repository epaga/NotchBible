import AppKit
import BibleCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model: LookupModel
    private var panel: LookupPanel!
    private var statusItem: NSStatusItem!
    private var shortcut: GlobalShortcut?
    private var triggers: [NotchTriggerPanel] = []
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var activeScreen: NSScreen?
    private var isOpen = false
    private var lastNotchClick: TimeInterval?
    private let preview: Bool

    init(library: BibleLibrary, preview: Bool) {
        self.model = LookupModel(library: library)
        self.preview = preview
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpMainMenu()
        panel = LookupPanel(model: model)
        model.onDismiss = { [weak self] in self?.hide() }
        model.onLayoutChange = { [weak self] in self?.resize() }
        panel.onDismiss = model.onDismiss
        panel.onCopy = { [weak self] in self?.model.copy() }
        panel.onFocus = { [weak self] in self?.model.focus() }
        panel.onResize = { [weak self] size in
            guard let self, let screen = self.activeScreen else { return }
            self.model.setPanelSize(self.clampedPanelSize(size, on: screen))
        }
        panel.onResizeEnd = { [weak self] in self?.model.savePanelSize() }
        shortcut = GlobalShortcut { [weak self] in self?.toggle(on: ScreenGeometry.underPointer()) }
        setUpStatusItem()
        rebuildTriggers()
        watchClicks()
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rebuildTriggers()
                self.activeScreen = ScreenGeometry.underPointer()
                self.resize()
            }
        })
        if preview || !UserDefaults.standard.bool(forKey: "hasOpenedNotchBible") {
            UserDefaults.standard.set(true, forKey: "hasOpenedNotchBible")
            // A first-launch introduction stays passive until clicked.
            show(on: ScreenGeometry.underPointer(), focus: false)
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        monitors.forEach(NSEvent.removeMonitor)
        observers.forEach(NotificationCenter.default.removeObserver)
        triggers.forEach { $0.orderOut(nil) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        show(on: ScreenGeometry.underPointer(), focus: true)
        return false
    }
    private func toggle(on screen: NSScreen?) {
        if isOpen, activeScreen == screen { hide() }
        else { show(on: screen, focus: true) }
    }
    private func show(on screen: NSScreen?, focus: Bool) {
        guard let screen else { return }
        activeScreen = screen
        isOpen = true
        resize()
        panel.alphaValue = 1
        if focus {
            panel.makeKeyAndOrderFront(nil)
            model.focus()
        } else { panel.orderFrontRegardless() }
    }
    private func hide() {
        guard isOpen else { return }
        isOpen = false
        panel.orderOut(nil)
    }
    private func resize() {
        guard isOpen, let screen = activeScreen else { return }
        let top = ScreenGeometry.panelTop(on: screen)
        model.availableBodyHeight = max(120, min(370, top - screen.visibleFrame.minY - 190))
        let preferredSize = model.preferredPanelSize.map { clampedPanelSize($0, on: screen) }
        if model.resizedPanelHeight != preferredSize?.height { model.resizedPanelHeight = preferredSize?.height }
        let width = preferredSize?.width ?? min(580, screen.frame.width - 24)
        let notchWidth = ScreenGeometry.notchRect(on: screen)?.width ?? 0
        if model.notchWidth != notchWidth { model.notchWidth = notchWidth }
        let frame = NSRect(x: screen.frame.midX - width / 2, y: top - model.panelHeight,
                           width: width, height: model.panelHeight)
        guard panel.frame != frame else { return }
        // SwiftUI updates the results in the same turn as the field editor.
        // Animating the window leaves that new layout inside the old bounds,
        // briefly clipping the field above the screen on the first character.
        panel.setFrame(frame, display: true, animate: false)
    }
    private func clampedPanelSize(_ size: NSSize, on screen: NSScreen) -> NSSize {
        let maxWidth = max(1, screen.frame.width - 24)
        let maxHeight = max(1, ScreenGeometry.panelTop(on: screen) - screen.visibleFrame.minY - 12)
        return NSSize(width: min(max(size.width, 360), maxWidth),
                      height: min(max(size.height, 260), maxHeight))
    }
    private func rebuildTriggers() {
        triggers.forEach { $0.orderOut(nil) }
        triggers = NSScreen.screens.compactMap { screen in
            guard let rect = ScreenGeometry.notchRect(on: screen) else { return nil }
            let trigger = NotchTriggerPanel(rect: rect) { [weak self] in self?.toggle(on: screen) }
            trigger.orderFrontRegardless()
            return trigger
        }
    }
    private func watchClicks() {
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.handleClick(event)
            }
        }) { monitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
            let handledNotch = MainActor.assumeIsolated {
                self?.handleClick(event) ?? false
            }
            // A notch click is handled here, before dispatch to the view. This
            // also covers menu-bar events with no associated NSWindow.
            return handledNotch ? nil : event
        }) { monitors.append(local) }
    }
    @discardableResult
    private func handleClick(_ event: NSEvent) -> Bool {
        let point = ScreenGeometry.location(of: event)
        if event.type == .leftMouseDown,
           let screen = NSScreen.screens.first(where: { ScreenGeometry.notchRect(on: $0)?.contains(point) == true }) {
            // A redirected event must never open and immediately close the
            // panel if it reaches both monitor paths.
            if lastNotchClick != event.timestamp {
                lastNotchClick = event.timestamp
                toggle(on: screen)
            }
            return true
        }
        if event.window == panel || triggers.contains(where: { $0 == event.window }) { return false }
        if event.window == statusItem.button?.window { return false }
        if isOpen, !panel.frame.contains(point) { hide() }
        return false
    }
    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "book.closed", accessibilityDescription: "NotchBible")
        image?.isTemplate = true
        button.image = image
        button.toolTip = "NotchBible · Click the notch or press ⌃⌥B"
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            hide()
            let menu = NSMenu()
            menu.addItem(withTitle: "Open NotchBible", action: #selector(openFromMenu), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "About NotchBible", action: #selector(about), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Quit NotchBible", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
        } else { toggle(on: ScreenGeometry.underPointer()) }
    }
    @objc private func openFromMenu() { show(on: ScreenGeometry.underPointer(), focus: true) }
    @objc private func about() {
        let alert = NSAlert()
        alert.messageText = "NotchBible"
        alert.informativeText = "A little space for the Word.\n\nLocal translations: \(model.library.translations.map(\.translation).joined(separator: ", ")). Click your notch, the menu bar book, or press ⌃⌥B. Type a reference; press Return or click Copy.\n\nNET Bible text: ©1996–2016 Biblical Studies Press, L.L.C., sourced from eBible.org.\n\n" + BibleStore.copyright + "\n\nThe app code is MIT licensed. Bible texts retain their own copyrights. Native panel architecture inspired by Alejandro Buján’s Tendedero."
        alert.addButton(withTitle: "Done")
        alert.runModal()
    }
    private func setUpMainMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About NotchBible", action: #selector(about), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit NotchBible", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        app.submenu = appMenu
        menu.addItem(app)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [
            ("Undo", #selector(UndoManager.undo), "z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a")
        ] { editMenu.addItem(withTitle: title, action: action, keyEquivalent: key) }
        edit.submenu = editMenu
        menu.addItem(edit)
        NSApp.mainMenu = menu
    }
}
