import Cocoa
import SwiftUI
import ApplicationServices
import ServiceManagement

// MARK: - Journal (~/Library/Logs/Plume.log)

func plumeLog(_ msg: String) {
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/Library/Logs/Plume.log")
    let line = "\(Date()) \(msg)\n"
    if let h = try? FileHandle(forWritingTo: url) {
        h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
    } else {
        try? line.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - Réglages

enum Settings {
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled") }
    }
    static var model: String {
        get { UserDefaults.standard.string(forKey: "model") ?? "haiku" }
        set { UserDefaults.standard.set(newValue, forKey: "model") }
    }
    static let models: [(id: String, label: String)] = [
        ("haiku", "Haiku (rapide)"),
        ("sonnet", "Sonnet (équilibré)"),
        ("opus", "Opus (le plus fin)"),
    ]
    /// Apps où la barre ne doit jamais apparaître.
    static let ignoredBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.notificationcenterui",
    ]
}

// MARK: - Actions

enum AIAction: String, CaseIterable, Identifiable {
    case demander, corriger, reformuler, raccourcir, traduire, resumer
    var id: String { rawValue }

    var title: String {
        switch self {
        case .demander: return "Demander à Claude"
        case .corriger: return "Corriger"
        case .reformuler: return "Reformuler"
        case .raccourcir: return "Raccourcir"
        case .traduire: return "Traduire"
        case .resumer: return "Résumer"
        }
    }

    var icon: String {
        switch self {
        case .demander: return "sparkles"
        case .corriger: return "text.badge.checkmark"
        case .reformuler: return "wand.and.stars"
        case .raccourcir: return "arrow.down.right.and.arrow.up.left"
        case .traduire: return "character.bubble"
        case .resumer: return "list.bullet"
        }
    }

    /// Texte de la bulle d'aide au survol.
    var hint: String {
        switch self {
        case .demander: return "Demander à Claude : écris ta propre consigne"
        case .corriger: return "Corriger : orthographe et grammaire, sans changer le style"
        case .reformuler: return "Reformuler : corriger et clarifier le texte"
        case .raccourcir: return "Raccourcir : version plus concise"
        case .traduire: return "Traduire : français vers anglais, sinon vers le français"
        case .resumer: return "Résumer : l'essentiel en quelques lignes"
        }
    }

    var instruction: String {
        switch self {
        case .demander:
            return ""
        case .corriger:
            return "Corrige uniquement les fautes d'orthographe, de grammaire, de conjugaison, d'accord, de ponctuation et de typographie. Ne modifie ni le style, ni le vocabulaire, ni la structure des phrases au-delà du strict nécessaire. Si le texte ne contient aucune faute, renvoie-le tel quel."
        case .reformuler:
            return "Réécris ce texte pour corriger toutes les fautes et le rendre plus clair, plus fluide et plus précis, en conservant le sens, le niveau de langue, le ton et toutes les informations. Ne rallonge pas le texte inutilement et n'invente rien."
        case .raccourcir:
            return "Rends ce texte plus concis en conservant toutes les informations importantes, et corrige au passage les fautes."
        case .traduire:
            return "Traduis ce texte en anglais s'il est rédigé en français, sinon traduis-le en français. Conserve le ton et la mise en forme."
        case .resumer:
            return "Résume ce texte en quelques phrases claires (ou en une courte liste à puces si c'est plus adapté), dans la langue du texte."
        }
    }

    static let toolbar: [AIAction] = [.demander, .corriger, .reformuler, .traduire, .resumer, .raccourcir]
}

enum Prompts {
    static let system = """
    Tu es un assistant d'écriture intégré à macOS. Tu reçois un texte sélectionné par l'utilisateur entre balises <texte> et une consigne.
    Réponds UNIQUEMENT avec le résultat demandé : pas d'introduction, pas de commentaire, pas d'explication, pas de guillemets ni de balises autour du résultat.
    Conserve la langue du texte (sauf consigne de traduction), ses retours à la ligne et sa mise en forme. N'ajoute pas de Markdown si le texte d'origine n'en contient pas.
    N'utilise jamais de tiret cadratin ni de tiret demi-cadratin.
    Si la consigne est une question sur le texte, réponds-y directement et brièvement.
    """

    static func build(instruction: String, text: String) -> String {
        "Consigne : \(instruction)\n\n<texte>\n\(text)\n</texte>"
    }

    static func followUp(original: String, current: String, request: String) -> String {
        """
        Texte d'origine :
        <texte>
        \(original)
        </texte>

        Version actuelle :
        <version>
        \(current)
        </version>

        Nouvelle consigne à appliquer à la version actuelle : \(request)
        """
    }
}

// MARK: - Appel à la CLI claude

final class ClaudeRunner {
    private var process: Process?

    static func claudePath() -> String? {
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    func cancel() {
        if let p = process, p.isRunning { p.terminate() }
        process = nil
    }

    func run(prompt: String, model: String, completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        cancel()
        guard let path = Self.claudePath() else {
            Task { @MainActor in completion(.failure(Self.error("CLI « claude » introuvable (attendue dans ~/.local/bin)."))) }
            return
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = [
            "-p",
            "--model", model,
            // Pas de réglages utilisateur (donc pas de hooks ni plugins), pas d'outils, pas de MCP.
            "--setting-sources", "project",
            "--strict-mcp-config",
            "--tools", "",
            "--no-session-persistence",
            "--system-prompt", Prompts.system,
        ]
        // Dossier neutre : aucun CLAUDE.md de projet chargé.
        p.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        var env = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        p.environment = env

        let input = Pipe(), output = Pipe(), errors = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = errors

        do {
            try p.run()
        } catch {
            Task { @MainActor in completion(.failure(error)) }
            return
        }
        process = p
        input.fileHandleForWriting.write(prompt.data(using: .utf8) ?? Data())
        try? input.fileHandleForWriting.close()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let out = output.fileHandleForReading.readDataToEndOfFile()
            let err = errors.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let stdout = String(data: out, encoding: .utf8) ?? ""
            let stderr = String(data: err, encoding: .utf8) ?? ""
            let status = p.terminationStatus
            let reason = p.terminationReason
            Task { @MainActor in
                // Requête annulée ou remplacée par une plus récente : on ignore.
                guard let self, self.process === p else { return }
                self.process = nil
                if reason == .uncaughtSignal { return }
                if status == 0, !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    completion(.success(stdout))
                } else {
                    let msg = [stderr, stdout].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first { !$0.isEmpty } ?? "Erreur inconnue (code \(status))."
                    completion(.failure(Self.error(msg)))
                }
            }
        }
    }

    static func error(_ msg: String) -> NSError {
        NSError(domain: "Plume", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
    }
}

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

// MARK: - Fenêtres flottantes

final class FloatingPanel: NSPanel {
    private let keyable: Bool

    init(keyable: Bool) {
        self.keyable = keyable
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 40),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { keyable }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Barre d'outils (au-dessus de la sélection)

/// Survol fiable même quand Plume n'est pas l'app active (onHover / .help ne le sont pas).
struct HoverTracker: NSViewRepresentable {
    let onChange: (Bool) -> Void

    final class TrackingView: NSView {
        var onChange: (Bool) -> Void = { _ in }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                           options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { onChange(true) }
        override func mouseExited(with event: NSEvent) { onChange(false) }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> TrackingView {
        let v = TrackingView()
        v.onChange = onChange
        return v
    }

    func updateNSView(_ nsView: TrackingView, context: Context) { nsView.onChange = onChange }
}

struct HoverButtonStyle: ButtonStyle {
    var onHover: ((Bool) -> Void)? = nil

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, onHover: onHover)
    }

    private struct HoverBody: View {
        let configuration: ButtonStyle.Configuration
        let onHover: ((Bool) -> Void)?
        @State private var hovering = false
        var body: some View {
            configuration.label
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.16 : (hovering ? 0.08 : 0)))
                )
                .contentShape(Rectangle())
                .background(HoverTracker { h in
                    hovering = h
                    onHover?(h)
                })
        }
    }
}

struct TooltipBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.85)))
            .fixedSize()
    }
}

struct ToolbarView: View {
    let onAction: (AIAction) -> Void
    @State private var hovered: AIAction?

    var body: some View {
        VStack(spacing: 6) {
            // Emplacement réservé à la bulle, au-dessus de la barre (loin du texte sélectionné).
            ZStack {
                if let h = hovered { TooltipBubble(text: h.hint) }
            }
            .frame(height: 26)
            HStack(spacing: 2) {
                ForEach(AIAction.toolbar) { action in
                    Button { onAction(action) } label: {
                        Image(systemName: action.icon)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(action == .demander ? Color.purple : Color.primary)
                    }
                    .buttonStyle(HoverButtonStyle { inside in
                        if inside { hovered = action } else if hovered == action { hovered = nil }
                    })
                    if action == .demander { Divider().frame(height: 18).padding(.horizontal, 2) }
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 11).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.1)))
            .fixedSize()
        }
        .frame(width: 400)
    }
}

// MARK: - Panneau de résultat

@MainActor
final class ResultModel: ObservableObject {
    @Published var action: AIAction
    @Published var result = ""
    @Published var loading = false
    @Published var error: String?
    let original: String
    let sourceApp: NSRunningApplication?
    private var lastPrompt: String?
    private let runner = ClaudeRunner()
    var onClose: () -> Void = {}

    init(original: String, sourceApp: NSRunningApplication?, action: AIAction) {
        self.original = original
        self.sourceApp = sourceApp
        self.action = action
    }

    var trimmedOriginal: String { original.trimmingCharacters(in: .whitespacesAndNewlines) }

    func run(_ a: AIAction) {
        action = a
        if a == .demander {
            runner.cancel()
            result = ""; error = nil; loading = false
            return
        }
        send(Prompts.build(instruction: a.instruction, text: trimmedOriginal))
    }

    func ask(_ request: String) {
        let q = request.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        if result.isEmpty {
            send(Prompts.build(instruction: q, text: trimmedOriginal))
        } else {
            send(Prompts.followUp(original: trimmedOriginal, current: result, request: q))
        }
    }

    func regenerate() {
        if let p = lastPrompt { send(p) }
    }

    private func send(_ prompt: String) {
        lastPrompt = prompt
        loading = true
        error = nil
        runner.run(prompt: prompt, model: Settings.model) { [weak self] r in
            guard let self else { return }
            self.loading = false
            switch r {
            case .success(let s):
                self.result = s.trimmingCharacters(in: .whitespacesAndNewlines)
                plumeLog("réponse Claude : \(self.result.count) caractères")
            case .failure(let e):
                self.error = e.localizedDescription
                plumeLog("erreur Claude : \(e.localizedDescription)")
            }
        }
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    func replace() {
        guard !result.isEmpty else { return }
        // Conserve les espaces / retours à la ligne entourant la sélection d'origine.
        let leading = String(original.prefix { $0.isWhitespace || $0.isNewline })
        let trailing = String(original.reversed().prefix { $0.isWhitespace || $0.isNewline }.reversed())
        let text = leading + result + trailing
        close()
        SelectionReader.replace(with: text, in: sourceApp)
    }

    func close() {
        runner.cancel()
        onClose()
    }
}

struct ResultView: View {
    @ObservedObject var model: ResultModel
    @State private var expanded = false
    @State private var followUp = ""
    @State private var copied = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(alignment: .leading, spacing: 12) {
                originalBox
                resultArea
                Divider()
                footer
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
        }
        .padding(12)
        .frame(width: 500)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
        .background(
            Button("") { model.close() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        )
        .onAppear { if model.action == .demander { fieldFocused = true } }
    }

    private var header: some View {
        HStack {
            Menu {
                ForEach(AIAction.allCases) { a in
                    Button { model.run(a) } label: { Label(a.title, systemImage: a.icon) }
                }
            } label: {
                Text(model.action.title).font(.system(size: 15, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Text(Settings.models.first { $0.id == Settings.model }?.label ?? Settings.model)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button { model.close() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(HoverButtonStyle())
            .help("Fermer (Échap)")
        }
    }

    private var originalBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.trimmedOriginal)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(expanded ? nil : 2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.trimmedOriginal.count > 110 {
                Button(expanded ? "Afficher moins" : "Afficher plus") { expanded.toggle() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
    }

    @ViewBuilder
    private var resultArea: some View {
        if model.loading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Claude réfléchit…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        } else if let e = model.error {
            Text(e)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.result.isEmpty {
            Text(model.action == .demander ? "Que veux-tu faire avec ce texte ?" : "")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else if model.result.count > 900 {
            ScrollView {
                resultText
            }
            .frame(height: 320)
        } else {
            resultText
        }
    }

    private var resultText: some View {
        Text(model.result)
            .font(.system(size: 14))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            TextField(model.result.isEmpty ? "Demander à Claude…" : "Demander un suivi", text: $followUp)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onSubmit {
                    model.ask(followUp)
                    followUp = ""
                }
            Spacer(minLength: 4)
            Button { model.regenerate() } label: { Label("Régénérer", systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered)
                .disabled(model.loading || model.result.isEmpty && model.error == nil)
            Button {
                model.copy()
                copied = true
                // Bref retour « Copié », puis fermeture du panneau.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { model.close() }
            } label: {
                Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.loading || model.result.isEmpty)
            .help("Copier en texte brut (⇧⌘C)")
            Button("Remplacer") { model.replace() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.loading || model.result.isEmpty)
                .help("Remplacer la sélection (⌘↩)")
        }
    }
}

// MARK: - Déplacement dans le dossier Applications

enum AppMover {
    /// Chemin réel de l'app, même si macOS l'exécute depuis une copie « translocated »
    /// (app téléchargée lancée depuis son dossier d'origine).
    static func originalBundleURL() -> URL {
        let url = Bundle.main.bundleURL
        guard url.path.contains("/AppTranslocation/"),
              let handle = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY),
              let sym = dlsym(handle, "SecTranslocateCreateOriginalPathForURL") else { return url }
        typealias Fn = @convention(c) (CFURL, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?
        let fn = unsafeBitCast(sym, to: Fn.self)
        return fn(url as CFURL, nil)?.takeRetainedValue() as URL? ?? url
    }

    static func isInApplications(_ url: URL) -> Bool {
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        return parent.hasPrefix("/Applications") || parent.hasPrefix(NSHomeDirectory() + "/Applications")
    }

    /// Propose de déplacer Plume dans Applications. Renvoie true si l'app va se relancer.
    static func offerMoveIfNeeded() -> Bool {
        let source = originalBundleURL()
        guard !isInApplications(source), !UserDefaults.standard.bool(forKey: "dontAskMove") else { return false }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Déplacer Plume dans le dossier Applications ?"
        alert.informativeText = "Plume fonctionne mieux depuis le dossier Applications : lancement à l'ouverture de session et autorisation d'accessibilité conservée."
        alert.addButton(withTitle: "Déplacer dans Applications")
        alert.addButton(withTitle: "Pas maintenant")
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Ne plus demander"
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on { UserDefaults.standard.set(true, forKey: "dontAskMove") }
        guard response == .alertFirstButtonReturn else { return false }

        let fm = FileManager.default
        let destDir = fm.isWritableFile(atPath: "/Applications") ? "/Applications" : NSHomeDirectory() + "/Applications"
        let dest = URL(fileURLWithPath: destDir).appendingPathComponent(source.lastPathComponent)
        do {
            try fm.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.trashItem(at: dest, resultingItemURL: nil) }
            if source.path.hasPrefix("/Volumes/") {
                try fm.copyItem(at: source, to: dest)           // depuis le DMG : copie
            } else {
                do { try fm.moveItem(at: source, to: dest) }    // sinon : déplacement
                catch { try fm.copyItem(at: source, to: dest) }
            }
            run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path], wait: true)
            // Relance la copie installée une fois ce processus terminé.
            let pid = ProcessInfo.processInfo.processIdentifier
            run("/bin/sh", ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$0\"", dest.path], wait: false)
            plumeLog("déplacée vers \(dest.path)")
            NSApp.terminate(nil)
            return true
        } catch {
            let fail = NSAlert()
            fail.messageText = "Impossible de déplacer Plume"
            fail.informativeText = error.localizedDescription
            fail.runModal()
            return false
        }
    }

    /// Une seule instance à la fois : la plus récente remplace les anciennes.
    static func terminateOtherInstances() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let me = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) where app.processIdentifier != me {
            app.terminate()
        }
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String], wait: Bool) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        try? p.run()
        if wait { p.waitUntilExit(); return p.terminationStatus }
        return 0
    }
}

// MARK: - Mises à jour depuis les releases GitHub

@MainActor
final class Updater {
    static let shared = Updater()
    static let repo = "gonzalt03/plume"

    struct Release { let version: String; let dmgURL: URL; let notes: String }

    private(set) var available: Release?
    private(set) var installing = false
    var onChange: () -> Void = {}
    private var timer: Timer?

    static var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates") }
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Vérification au lancement puis toutes les 24 h.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if Updater.autoCheck { self?.check(interactive: false) }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { _ in
            Task { @MainActor in if Updater.autoCheck { Updater.shared.check(interactive: false) } }
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ v: String) -> [Int] {
            v.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    func check(interactive: Bool) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Plume-Updater", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, error in
            var release: Release?
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String,
               let assets = json["assets"] as? [[String: Any]],
               let dmg = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
               let urlString = dmg["browser_download_url"] as? String, let url = URL(string: urlString) {
                release = Release(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                                  dmgURL: url, notes: json["body"] as? String ?? "")
            }
            let err = error?.localizedDescription
            Task { @MainActor in Updater.shared.handle(release, error: err, interactive: interactive) }
        }.resume()
    }

    private func handle(_ release: Release?, error: String?, interactive: Bool) {
        guard let release else {
            plumeLog("vérification des mises à jour : échec \(error ?? "réponse inattendue")")
            if interactive { info("Impossible de vérifier les mises à jour", error ?? "Aucune release avec un DMG trouvée.") }
            return
        }
        guard Self.isNewer(release.version, than: currentVersion) else {
            available = nil; onChange()
            if interactive { info("Plume est à jour", "Version \(currentVersion), la plus récente.") }
            return
        }
        available = release
        onChange()
        plumeLog("mise à jour disponible : \(release.version)")
        // En automatique, on ne redemande pas pour une version déjà ignorée.
        if !interactive, UserDefaults.standard.string(forKey: "skippedVersion") == release.version { return }
        prompt(release)
    }

    func prompt(_ release: Release) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Plume \(release.version) est disponible"
        let notes = release.notes.count > 600 ? String(release.notes.prefix(600)) + "…" : release.notes
        alert.informativeText = "Version installée : \(currentVersion).\n\n\(notes)"
        alert.addButton(withTitle: "Installer et relancer")
        alert.addButton(withTitle: "Plus tard")
        alert.addButton(withTitle: "Ignorer cette version")
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(release)
        case .alertThirdButtonReturn: UserDefaults.standard.set(release.version, forKey: "skippedVersion")
        default: break
        }
    }

    func install(_ release: Release) {
        guard !installing else { return }
        installing = true
        onChange()
        plumeLog("téléchargement de \(release.dmgURL)")
        URLSession.shared.downloadTask(with: release.dmgURL) { file, _, error in
            var result: Result<URL, Error>
            if let file {
                // Le fichier temporaire est supprimé à la fin du callback : on le déplace.
                let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("Plume-update-\(UUID().uuidString).dmg")
                do { try FileManager.default.moveItem(at: file, to: dmg); result = .success(dmg) }
                catch { result = .failure(error) }
            } else {
                result = .failure(error ?? ClaudeRunner.error("Téléchargement impossible."))
            }
            let r = result
            Task { @MainActor in Updater.shared.finishInstall(r) }
        }.resume()
    }

    private func finishInstall(_ download: Result<URL, Error>) {
        defer { installing = false; onChange() }
        do {
            let dmg = try download.get()
            defer { try? FileManager.default.removeItem(at: dmg) }
            let staged = try extractApp(from: dmg)
            try verifySignature(of: staged)
            let dest = AppMover.originalBundleURL()
            _ = try FileManager.default.replaceItemAt(dest, withItemAt: staged)
            Self.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path])
            plumeLog("mise à jour installée dans \(dest.path), relance")
            let pid = ProcessInfo.processInfo.processIdentifier
            Self.run("/bin/sh", ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \"$0\"", dest.path], wait: false)
            NSApp.terminate(nil)
        } catch {
            plumeLog("échec de la mise à jour : \(error.localizedDescription)")
            info("Échec de la mise à jour", error.localizedDescription)
        }
    }

    /// Monte le DMG, copie Plume.app dans un dossier temporaire, démonte.
    private func extractApp(from dmg: URL) throws -> URL {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("plume-mount-\(UUID().uuidString)")
        let stage = fm.temporaryDirectory.appendingPathComponent("plume-stage-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        guard Self.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path]) == 0 else {
            throw ClaudeRunner.error("Impossible d'ouvrir l'image disque téléchargée.")
        }
        defer { Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let source = mount.appendingPathComponent("Plume.app")
        let target = stage.appendingPathComponent("Plume.app")
        guard Self.run("/usr/bin/ditto", [source.path, target.path]) == 0 else {
            throw ClaudeRunner.error("Plume.app introuvable dans l'image disque.")
        }
        return target
    }

    /// La nouvelle version doit être signée avec le même certificat que l'app actuelle.
    private func verifySignature(of app: URL) throws {
        var selfCode: SecCode?
        var selfStatic: SecStaticCode?
        var requirement: SecRequirement?
        var staticCode: SecStaticCode?
        guard SecCodeCopySelf([], &selfCode) == errSecSuccess, let selfCode,
              SecCodeCopyStaticCode(selfCode, [], &selfStatic) == errSecSuccess, let selfStatic,
              SecCodeCopyDesignatedRequirement(selfStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw ClaudeRunner.error("Vérification de signature impossible.")
        }
        let status = SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
        guard status == errSecSuccess else {
            throw ClaudeRunner.error("La mise à jour n'est pas signée par le même certificat que Plume (code \(status)). Installation annulée.")
        }
    }

    private func info(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }

    @discardableResult
    static func run(_ path: String, _ args: [String], wait: Bool = true) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        if wait { p.waitUntilExit(); return p.terminationStatus }
        return 0
    }
}

// MARK: - Contrôleur principal

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppMover.offerMoveIfNeeded() { return }
        AppMover.terminateOtherInstances()
        setupStatusItem()
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        plumeLog("Démarrage, accessibilité autorisée : \(trusted)")
        installMonitors()
        Updater.shared.onChange = { [weak self] in self?.rebuildMenu() }
        Updater.shared.start()
        // Déclencheur de test : vérifie et installe la dernière release sans confirmation.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.plume.test-update"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                Updater.shared.onChange = {
                    if let r = Updater.shared.available, !Updater.shared.installing { Updater.shared.install(r) }
                }
                Updater.shared.check(interactive: false)
            }
        }
        // Déclencheur de test : ouvre le panneau avec un texte d'exemple.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("local.plume.test"), object: nil, queue: .main) { [weak self] n in
            let text = (n.object as? String) ?? "Des fichiers ont transmis normalement tous les éléments réémis depuis le 1er Septembre jusqu au 8 Novembre"
            Task { @MainActor in
                guard let self else { return }
                self.currentText = text
                self.currentApp = NSWorkspace.shared.frontmostApplication
                self.currentPoint = NSEvent.mouseLocation
                self.startAction(.corriger)
            }
        }
    }

    // MARK: Menu

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let image = Bundle.main.image(forResource: "MenuBarIcon")
                ?? NSImage(systemSymbolName: "text.badge.checkmark", accessibilityDescription: "Plume")
            image?.size = NSSize(width: 18, height: 18)
            image?.isTemplate = true
            button.image = image
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Plume", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "Barre sur sélection activée", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = Settings.enabled ? .on : .off
        menu.addItem(toggle)

        let modelItem = NSMenuItem(title: "Modèle", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for m in Settings.models {
            let item = NSMenuItem(title: m.label, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = m.id
            item.state = Settings.model == m.id ? .on : .off
            modelMenu.addItem(item)
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)

        let login = NSMenuItem(title: "Lancer à l'ouverture de session", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let trusted = AXIsProcessTrusted()
        let ax = NSMenuItem(title: trusted ? "Accessibilité : autorisée" : "Autoriser l'accessibilité…",
                            action: trusted ? nil : #selector(openAccessibility), keyEquivalent: "")
        ax.target = self
        ax.isEnabled = !trusted
        menu.addItem(ax)
        if ClaudeRunner.claudePath() == nil {
            let warn = NSMenuItem(title: "CLI claude introuvable", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        menu.addItem(.separator())
        let updater = Updater.shared
        if updater.installing {
            let item = NSMenuItem(title: "Installation de la mise à jour…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else if let release = updater.available {
            let item = NSMenuItem(title: "Installer Plume \(release.version)…", action: #selector(installUpdate), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let check = NSMenuItem(title: "Rechercher les mises à jour…", action: #selector(checkUpdates), keyEquivalent: "")
        check.target = self
        menu.addItem(check)
        let auto = NSMenuItem(title: "Vérifier automatiquement", action: #selector(toggleAutoCheck), keyEquivalent: "")
        auto.target = self
        auto.state = Updater.autoCheck ? .on : .off
        menu.addItem(auto)
        let version = NSMenuItem(title: "Version \(updater.currentVersion)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        menu.delegate = self
        statusItem.menu = menu
    }

    @objc private func checkUpdates() { Updater.shared.check(interactive: true) }

    @objc private func installUpdate() {
        if let r = Updater.shared.available { Updater.shared.prompt(r) }
    }

    @objc private func toggleAutoCheck() {
        Updater.autoCheck.toggle()
        rebuildMenu()
    }

    @objc private func toggleEnabled() {
        Settings.enabled.toggle()
        if !Settings.enabled { hideToolbar() }
        rebuildMenu()
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? String { Settings.model = id }
        rebuildMenu()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
        rebuildMenu()
    }

    @objc private func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Surveillance souris / clavier

    private func installMonitors() {
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown], handler: { [weak self] e in
            let point = NSEvent.mouseLocation
            Task { @MainActor in self?.handleMouseDown(at: point) }
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp], handler: { [weak self] e in
            let point = NSEvent.mouseLocation
            let clicks = e.clickCount
            let shift = e.modifierFlags.contains(.shift)
            Task { @MainActor in self?.handleMouseUp(at: point, clicks: clicks, shift: shift) }
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .scrollWheel, .rightMouseDown], handler: { [weak self] _ in
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
        guard Settings.enabled else { return }
        guard AXIsProcessTrusted() else { plumeLog("mouseUp ignoré : accessibilité non autorisée"); return }
        let dragged = hypot(point.x - mouseDownPoint.x, point.y - mouseDownPoint.y) > 6
        guard dragged || clicks >= 2 || shift else { return }
        if let role = mouseDownRole, SelectionReader.nonTextRoles.contains(role) { plumeLog("ignoré, rôle \(role)"); return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              !Settings.ignoredBundleIDs.contains(app.bundleIdentifier ?? "") else { return }

        let token = UUID()
        selectionToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.selectionToken == token else { return }
            SelectionReader.read(app: app) { text in
                plumeLog("sélection dans \(app.bundleIdentifier ?? "?") (rôle \(self.mouseDownRole ?? "?")) : \(text.map { "\($0.count) caractères" } ?? "aucune")")
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

    // MARK: Barre

    private func showToolbar(at point: NSPoint) {
        let panel = toolbarPanel ?? FloatingPanel(keyable: false)
        toolbarPanel = panel
        let host = FirstMouseHostingView(rootView: ToolbarView { [weak self] action in
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

    private func startAction(_ action: AIAction) {
        plumeLog("action \(action.rawValue) sur \(currentText.count) caractères")
        hideToolbar()
        closeResult()

        let model = ResultModel(original: currentText, sourceApp: currentApp, action: action)
        model.onClose = { [weak self] in self?.closeResult() }
        resultModel = model

        let panel = FloatingPanel(keyable: true)
        let host = FirstMouseHostingView(rootView: ResultView(model: model))
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
        plumeLog("panneau : frame \(panel.frame) visible \(panel.isVisible) écrans \(NSScreen.screens.map { $0.frame })")
        model.run(action)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak panel] in
            if let panel { plumeLog("panneau après 3 s : frame \(panel.frame) visible \(panel.isVisible)") }
        }
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
}

extension AppController: NSMenuDelegate {
    nonisolated func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in self.rebuildMenuIfAXChanged() }
    }

    private func rebuildMenuIfAXChanged() {
        rebuildMenu()
    }
}

// MARK: - Démarrage

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    app.run()
}
