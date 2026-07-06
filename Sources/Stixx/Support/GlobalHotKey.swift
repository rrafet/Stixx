import AppKit
import Carbon.HIToolbox

/// One system-wide hot key (⌥⌘N) that fires from any app. Carbon's
/// RegisterEventHotKey is the sandbox- and App Store-friendly way to do
/// this: unlike event taps it needs no accessibility permission.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let onPressed: () -> Void

    init(keyCode: UInt32 = UInt32(kVK_ANSI_N),
         modifiers: UInt32 = UInt32(cmdKey | optionKey),
         onPressed: @escaping () -> Void) {
        self.onPressed = onPressed

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { hotKey.onPressed() }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x53545858), id: 1) // "STXX"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
    }
}
