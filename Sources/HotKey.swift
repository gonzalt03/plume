import Carbon
import Foundation

/// Raccourci clavier global (API Carbon : aucune autorisation supplémentaire nécessaire).
final class HotKey {
    static let shared = HotKey()

    struct Preset { let id: String; let label: String; let keyCode: Int; let modifiers: Int }

    static let presets: [Preset] = [
        Preset(id: "ctrlOptC", label: "⌃⌥C", keyCode: kVK_ANSI_C, modifiers: controlKey | optionKey),
        Preset(id: "ctrlOptP", label: "⌃⌥P", keyCode: kVK_ANSI_P, modifiers: controlKey | optionKey),
        Preset(id: "optCmdJ", label: "⌥⌘J", keyCode: kVK_ANSI_J, modifiers: optionKey | cmdKey),
        Preset(id: "ctrlShiftSpace", label: "⌃⇧Espace", keyCode: kVK_Space, modifiers: controlKey | shiftKey),
    ]

    static func label(for id: String) -> String? { presets.first { $0.id == id }?.label }

    var action: () -> Void = {}
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    func register(_ presetID: String) {
        unregister()
        guard let preset = Self.presets.first(where: { $0.id == presetID }) else { return }
        if !handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.shared.action() }
                return noErr
            }, 1, &spec, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x504C_554D), id: 1) // "PLUM"
        let status = RegisterEventHotKey(UInt32(preset.keyCode), UInt32(preset.modifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr { plumeLog("raccourci \(preset.label) indisponible (code \(status))") }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
