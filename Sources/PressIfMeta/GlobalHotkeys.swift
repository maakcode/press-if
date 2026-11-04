import AppKit
import Carbon

final class GlobalHotkeys {
    var onOpen: (() -> Void)?
    var onStop: (() -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return noErr }
            var hotkey = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            let owner = Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue()
            if hotkey.id == 1 { owner.onOpen?() }
            if hotkey.id == 2 { owner.onStop?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        for (id, key) in [(UInt32(1), UInt32(kVK_Space)), (UInt32(2), UInt32(kVK_Escape))] {
            var ref: EventHotKeyRef?
            let hotkey = EventHotKeyID(signature: 0x50494D54, id: id)
            if RegisterEventHotKey(key, UInt32(controlKey | optionKey), hotkey, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
        }
    }

    deinit {
        refs.forEach { UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }
}
