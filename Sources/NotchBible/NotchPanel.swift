import AppKit
import SwiftUI

enum NotchLayout {
    // Bury the window's compositing edge behind the camera area, rather than
    // letting two separately composited black surfaces meet edge to edge.
    static let overlap: CGFloat = 2
    static let shoulder: CGFloat = 14
    static var topInset: CGFloat { overlap + shoulder }
}

@MainActor
final class LookupPanel: NSPanel {
    var onCopy: (() -> Void)?
    var onFocus: (() -> Void)?
    var onDismiss: (() -> Void)?
    init(model: LookupModel) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "NotchBible"
        isOpaque = false
        backgroundColor = .clear
        // AppKit's shadow adds a hairline around the separate window, including
        // across the join. The SwiftUI outline supplies the visible perimeter.
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let host = NSHostingView(rootView: LookupView(model: model))
        host.sizingOptions = []
        contentView = host
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "c" {
            onCopy?(); return true
        }
        if modifiers == .command, ["l", "f"].contains(event.charactersIgnoringModifiers?.lowercased() ?? "") {
            onFocus?(); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A narrow, permission-free hit target exactly over the hardware notch.
/// The small black lip below the camera gives the pointer a visible target too.
@MainActor
final class NotchTriggerPanel: NSPanel {
    init(rect: NSRect, action: @escaping () -> Void) {
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "NotchBible notch"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isMovable = false
        ignoresMouseEvents = false
        contentView = NotchTriggerView(action: action)
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
private final class NotchTriggerView: NSView {
    let action: () -> Void
    private var tracking: NSTrackingArea?
    private var hovered = false
    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        toolTip = "NotchBible · Click to look up a passage · ⌃⌥B"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Open NotchBible")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { action() }
    override func accessibilityPerformPress() -> Bool { action(); return true }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
        super.updateTrackingAreas()
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
        NSColor(calibratedRed: 0.88, green: 0.71, blue: 0.46, alpha: hovered ? 0.9 : 0.32).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 13, y: 2, width: 26, height: 2), xRadius: 1, yRadius: 1).fill()
    }
}

enum ScreenGeometry {
    static func location(of event: NSEvent) -> NSPoint {
        if let window = event.window {
            return window.convertPoint(toScreen: event.locationInWindow)
        }
        // A global event uses Quartz coordinates (origin at the primary
        // screen's top left). Use its recorded location, never a later pointer
        // sample: macOS can relocate the cursor when clicking the camera area.
        if let location = event.cgEvent?.location, let primary = NSScreen.screens.first {
            return NSPoint(x: location.x, y: primary.frame.maxY - location.y)
        }
        return event.locationInWindow
    }
    static func underPointer() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
    }
    static func notchRect(on screen: NSScreen) -> NSRect? {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
              right.minX > left.maxX else { return nil }
        return NSRect(x: left.maxX, y: screen.frame.maxY - screen.safeAreaInsets.top - 6,
                      width: right.minX - left.maxX, height: screen.safeAreaInsets.top + 6)
    }
    static func panelTop(on screen: NSScreen) -> CGFloat {
        if screen.safeAreaInsets.top > 0, notchRect(on: screen) != nil {
            return screen.frame.maxY - screen.safeAreaInsets.top + NotchLayout.overlap
        }
        return min(screen.visibleFrame.maxY, screen.frame.maxY - max(screen.safeAreaInsets.top, NSStatusBar.system.thickness))
    }
}
