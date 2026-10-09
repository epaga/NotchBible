import AppKit
import Carbon

/// Carbon registers an explicit shortcut without monitoring the keyboard or
/// asking for Accessibility/Input Monitoring access.
@MainActor
final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private(set) var registered = false

    init(action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue().action()
            }
            return noErr
        }, 1, &event, context, &handler)
        guard installed == noErr else { return }
        let id = EventHotKeyID(signature: 0x4E424942, id: 1) // NBIB
        registered = RegisterEventHotKey(UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &hotKey) == noErr
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
