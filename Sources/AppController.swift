import Cocoa
import SwiftUI
import ApplicationServices
import ServiceManagement

@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var toolbarPanel: FloatingPanel?
    private var resultPanel: FloatingPanel?
    private var resultModel: ResultModel?
    private var resultTopLeft: NSPoint = .zero
    private var monitors: [Any] = []

    private var mouseDownPoint: NSPoint = .zero
    private var mouseDownRole: String?
    private var selectionToken = UUID()

    private var currentText = ""
    private var currentApp: NSRunningApplication?
    private var currentPoint: NSPoint = .zero
    private var registeredHotkey = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMover.offerMoveIfNeeded() { return }
        AppMover.terminateOtherInstances()
        setupStatusItem()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        plumeLog("Démarrage \(Updater.shared.currentVersion), accessibilité autorisée : \(trusted)")
        installMonitors()

        HotKey.shared.action = { [weak self] in Task { @MainActor in self?.handleHotkey() } }
        applyHotkey()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.applyHotkey()
                self?.rebuildMenu()
            }
        }

        Updater.shared.onChange = { [weak self] in self?.rebuildMenu() }
        Updater.shared.start()
        installDebugTriggers()

        // Premier lancement sans aucun accès à Claude : ouvrir les réglages.
        if Backend.resolve() == nil { SettingsWindowController.shared.show() }
    }

    // MARK: Menu de la barre des menus

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        rebuildMenu()
    }

    private func statusImage(badge: Bool) -> NSImage? {
        guard let base = Bundle.main.image(forResource: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "Plume") else { return nil }
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            if badge {
                // Pastille : une mise à jour est disponible.
                NSColor.black.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12, y: 12, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    func rebuildMenu() {
        guard statusItem != nil else { return }
        let updater = Updater.shared
        statusItem.button?.image = statusImage(badge: updater.available != nil)
        statusItem.button?.toolTip = updater.available.map { L.t("Plume \($0.version) est disponible", "Plume \($0.version) is available") } ?? "Plume"

        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "Plume \(updater.currentVersion)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        if updater.installing {
            let item = NSMenuItem(title: L.t("Installation de la mise à jour…", "Installing update…"), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if let release = updater.available {
            let item = NSMenuItem(title: L.t("Installer Plume \(release.version)…", "Install Plume \(release.version)…"),
                                  action: #selector(installUpdate), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: L.t("Barre sur sélection", "Bar on selection"), action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = Settings.autoBar ? .on : .off
        menu.addItem(toggle)

        if let label = HotKey.label(for: Settings.hotkey) {
            let hint = NSMenuItem(title: L.t("Raccourci : \(label)", "Shortcut: \(label)"), action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }

        let modelItem = NSMenuItem(title: L.t("Modèle", "Model"), action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for m in Models.all {
            let item = NSMenuItem(title: m.label, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.id
            item.state = Settings.model == m.id ? .on : .off
            modelMenu.addItem(item)
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        let settings = NSMenuItem(title: L.t("Réglages…", "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        if !AXIsProcessTrusted() {
            let ax = NSMenuItem(title: L.t("Autoriser l'accessibilité…", "Allow Accessibility access…"),
                                action: #selector(openAccessibility), keyEquivalent: "")
            ax.target = self
            menu.addItem(ax)
        }
        if Backend.resolve() == nil {
            let warn = NSMenuItem(title: L.t("Configurer l'accès à Claude…", "Set up Claude access…"),
                                  action: #selector(openSettings), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
        }
        let check = NSMenuItem(title: L.t("Rechercher les mises à jour…", "Check for Updates…"), action: #selector(checkUpdates), keyEquivalent: "")
        check.target = self
        menu.addItem(check)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L.t("Quitter Plume", "Quit Plume"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    nonisolated func menuWillOpen(_ menu: NSMenu) {}

    @objc private func toggleEnabled() {
        Settings.autoBar.toggle()
        if !Settings.autoBar { hideToolbar() }
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { Settings.model = id }
    }

    @objc private func openSettings() { SettingsWindowController.shared.show() }

    @objc private func checkUpdates() { Updater.shared.check(interactive: true) }

    @objc private func installUpdate() {
        if let r = Updater.shared.available { Updater.shared.prompt(r) }
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func applyHotkey() {
        let id = Settings.hotkey
        guard id != registeredHotkey else { return }
        registeredHotkey = id
        if id == "none" { HotKey.shared.unregister() } else { HotKey.shared.register(id) }
    }

    // MARK: Surveillance souris / clavier

    private func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] _ in
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.handleMouseDown(at: point) }
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] e in
            let point = NSEvent.mouseLocation
            let clicks = e.clickCount
            let shift = e.modifierFlags.contains(.shift)
            Task { @MainActor in self?.handleMouseUp(at: point, clicks: clicks, shift: shift) }
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .scrollWheel, .rightMouseDown], handler: { [weak self] e in
            // Le ⌘C simulé pour lire la sélection (Google Docs, apps sans accessibilité) ne doit pas fermer la barre.
            if e.type == .keyDown, Keyboard.isSynthetic(e) { return }
            Task { @MainActor in
                self?.selectionToken = UUID()
                self?.hideToolbar()
            }
        }) { monitors.append(m) }
    }

    private func handleMouseDown(at point: NSPoint) {
        selectionToken = UUID()
        hideToolbar()
        mouseDownPoint = point
        mouseDownRole = SelectionReader.roleAt(point)
    }

    private func handleMouseUp(at point: NSPoint, clicks: Int, shift: Bool) {
        guard Settings.autoBar else { return }
        guard AXIsProcessTrusted() else { plumeLog("mouseUp ignoré : accessibilité non autorisée"); return }
        let dragged = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > 6
        guard dragged || clicks >= 2 || shift else { return }
        if let role = mouseDownRole, SelectionReader.nonTextRoles.contains(role) { return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !Settings.isIgnored(app.bundleIdentifier) else { return }

        let token = UUID()
        selectionToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.selectionToken == token else { return }
            SelectionReader.read(app: app) { text in
                Task { @MainActor in
                    guard self.selectionToken == token,
                          let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    self.currentText = text
                    self.currentApp = app
                    self.currentPoint = point
                    self.showToolbar(at: point)
                }
            }
        }
    }

    /// Raccourci clavier : barre d'actions sur la sélection courante, même dans une app exclue.
    private func handleHotkey() {
        guard AXIsProcessTrusted() else { openAccessibility(); return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        let point = NSEvent.mouseLocation
        let token = UUID()
        selectionToken = token
        // Laisse le temps de relâcher les touches du raccourci avant un éventuel ⌘C.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, self.selectionToken == token else { return }
            SelectionReader.read(app: app) { text in
                Task { @MainActor in
                    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        NSSound.beep(); return
                    }
                    self.currentText = text
                    self.currentApp = app
                    self.currentPoint = point
                    self.showToolbar(at: point)
                }
            }
        }
    }

    // MARK: Barre

    private func showToolbar(at point: NSPoint) {
        let panel = toolbarPanel ?? FloatingPanel(keyable: false)
        toolbarPanel = panel
        let host = FirstMouseHostingView(rootView: ToolbarView(actions: ActionStore.toolbar) { [weak self] action in
            self?.startAction(action)
        })
        host.setFrameSize(host.fittingSize)
        panel.contentView = host
        panel.setContentSize(host.fittingSize)

        let size = panel.frame.size
        var origin = NSPoint(x: point.x - size.width / 2, y: point.y + 14)
        origin = clamp(origin: origin, size: size, near: point)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    private func hideToolbar() {
        toolbarPanel?.orderOut(nil)
    }

    // MARK: Résultat

    private func startAction(_ action: PlumeAction) {
        plumeLog("action \(action.id) sur \(currentText.count) caractères")
        hideToolbar()
        closeResult()

        let model = ResultModel(original: currentText, sourceApp: currentApp, action: action)
        model.onClose = { [weak self] in self?.closeResult() }
        resultModel = model

        let panel = FloatingPanel(keyable: true)
        let host = FirstMouseHostingView(rootView: ResultView(model: model, openSettings: { [weak self] in
            self?.closeResult()
            SettingsWindowController.shared.show()
        }))
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.setContentSize(size)
        resultPanel = panel

        resultTopLeft = NSPoint(x: currentPoint.x - 40, y: currentPoint.y - 12)
        placeResultPanel()
        NotificationCenter.default.addObserver(self, selector: #selector(resultResized), name: NSWindow.didResizeNotification, object: panel)
        NotificationCenter.default.addObserver(self, selector: #selector(resultMoved), name: NSWindow.didMoveNotification, object: panel)

        panel.makeKeyAndOrderFront(nil)
        model.run(action)
    }

    @objc private func resultResized() { placeResultPanel() }

    @objc private func resultMoved() {
        guard let panel = resultPanel else { return }
        resultTopLeft = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
    }

    private func placeResultPanel() {
        guard let panel = resultPanel else { return }
        let size = panel.frame.size
        let origin = clamp(origin: NSPoint(x: resultTopLeft.x, y: resultTopLeft.y - size.height), size: size, near: currentPoint)
        if panel.frame.origin != origin {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: panel)
            panel.setFrameOrigin(origin)
            NotificationCenter.default.addObserver(self, selector: #selector(resultMoved), name: NSWindow.didMoveNotification, object: panel)
        }
    }

    private func closeResult() {
        if let panel = resultPanel {
            NotificationCenter.default.removeObserver(self, name: nil, object: panel)
            panel.orderOut(nil)
        }
        resultPanel = nil
        resultModel = nil
    }

    private func clamp(origin: NSPoint, size: NSSize, near point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) } ?? NSScreen.main
        guard let vf = screen?.visibleFrame else { return origin }
        var o = origin
        o.x = min(max(o.x, vf.minX + 8), vf.maxX - size.width - 8)
        o.y = min(max(o.y, vf.minY + 8), vf.maxY - size.height - 8)
        return o
    }

    // MARK: Déclencheurs de test (développement, captures d'écran)

    private func installDebugTriggers() {
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.plume.debug"), object: nil, queue: .main) { [weak self] n in
            let command = (n.object as? String) ?? "panel"
            Task { @MainActor in self?.debug(command) }
        }
    }

    private func debug(_ command: String) {
        let sample = L.t("Bonjour, je vous confirme que les fichier on bien été transmit hier soir.",
                         "Hi, I can confirm that the file was sent yesterday evening and it work fine.")
        currentText = command.hasPrefix("fix:") ? String(command.dropFirst(4)) : sample
        currentApp = nil
        currentPoint = NSEvent.mouseLocation
        switch command {
        case "toolbar": showToolbar(at: currentPoint)
        case "settings": SettingsWindowController.shared.show()
        case "update":
            Updater.shared.onChange = {
                if let r = Updater.shared.available, !Updater.shared.installing { Updater.shared.install(r) }
            }
            Updater.shared.check(interactive: false)
        default:
            if let fix = ActionStore.all.first(where: { $0.id == "fix" }) ?? ActionStore.all.first { startAction(fix) }
        }
    }
}
