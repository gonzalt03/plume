import Cocoa
import SwiftUI
import ApplicationServices

// MARK: - Lecture de la sélection / remplacement

enum Keyboard {
    static let keyC: CGKeyCode = 8
    static let keyV: CGKeyCode = 9

    static func pressCommand(_ key: CGKeyCode) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

enum PasteboardSnapshot {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    static func save(_ pb: NSPasteboard = .general) -> Snapshot {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    static func restore(_ snapshot: Snapshot, _ pb: NSPasteboard = .general) {
        pb.clearContents()
        let items: [NSPasteboardItem] = snapshot.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pb.writeObjects(items) }
    }
}

enum SelectionReader {
    private static var webAXEnabledPIDs = Set<pid_t>()

    /// Rôles AX sur lesquels un glisser n'est jamais une sélection de texte.
    static let nonTextRoles: Set<String> = [
        "AXWindow", "AXButton", "AXToolbar", "AXScrollBar", "AXSplitter", "AXMenuBar",
        "AXMenuBarItem", "AXTabGroup", "AXRadioButton", "AXCheckBox", "AXSlider", "AXImage",
        "AXPopUpButton", "AXRow", "AXCell", "AXOutline", "AXDockItem", "AXDisclosureTriangle",
    ]

    static func roleAt(_ point: NSPoint) -> String? {
        guard let screen = NSScreen.screens.first else { return nil }
        // Coordonnées AX : origine en haut à gauche de l'écran principal.
        let y = Float(screen.frame.maxY - point.y)
        var element: AXUIElement?
        let system = AXUIElementCreateSystemWide()
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), y, &element) == .success,
              let el = element else { return nil }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
        return role as? String
    }

    /// Active l'arbre d'accessibilité des apps Chromium / Electron (Chrome, Slack, VS Code...).
    static func enableWebAccessibility(_ pid: pid_t) {
        guard !webAXEnabledPIDs.contains(pid) else { return }
        webAXEnabledPIDs.insert(pid)
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    static func axSelectedText() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let f = focused, CFGetTypeID(f) == AXUIElementGetTypeID() else { return nil }
        let element = f as! AXUIElement
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success else { return nil }
        return selected as? String
    }

    /// Repli : Cmd+C puis restauration du presse-papiers.
    static func copySelection(completion: @escaping (String?) -> Void) {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.save(pb)
        let before = pb.changeCount
        Keyboard.pressCommand(Keyboard.keyC)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard pb.changeCount != before else { completion(nil); return }
            let text = pb.string(forType: .string)
            PasteboardSnapshot.restore(snapshot, pb)
            completion(text)
        }
    }

    static func read(app: NSRunningApplication, completion: @escaping (String?) -> Void) {
        enableWebAccessibility(app.processIdentifier)
        if let text = axSelectedText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completion(text)
            return
        }
        copySelection(completion: completion)
    }

    /// Colle `text` à la place de la sélection dans l'app d'origine.
    static func replace(with text: String, in app: NSRunningApplication?) {
        let pb = NSPasteboard.general
        let snapshot = PasteboardSnapshot.save(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)
        app?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            Keyboard.pressCommand(Keyboard.keyV)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                PasteboardSnapshot.restore(snapshot, pb)
            }
        }
    }
}

