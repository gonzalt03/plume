import Cocoa
import SwiftUI

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

// MARK: - Survol (fiable même quand Plume n'est pas l'app active)

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

// MARK: - Barre d'outils (au-dessus de la sélection)

struct ToolbarView: View {
    let actions: [PlumeAction]
    let onAction: (PlumeAction) -> Void
    @State private var hovered: PlumeAction?

    var body: some View {
        VStack(spacing: 6) {
            // Emplacement réservé à la bulle, au-dessus de la barre (loin du texte sélectionné).
            ZStack {
                if let h = hovered { TooltipBubble(text: h.tooltip) }
            }
            .frame(height: 26)
            HStack(spacing: 2) {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    Button { onAction(action) } label: {
                        Image(systemName: action.icon)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(action.isFreeForm ? Color.purple : Color.primary)
                    }
                    .buttonStyle(HoverButtonStyle { inside in
                        if inside { hovered = action } else if hovered == action { hovered = nil }
                    })
                    if index == 0 && action.isFreeForm && actions.count > 1 {
                        Divider().frame(height: 18).padding(.horizontal, 2)
                    }
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 11).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.1)))
            .fixedSize()
        }
        .frame(width: 460)
    }
}

// MARK: - Différences mot à mot (corrections surlignées)

enum WordDiff {
    private static let regex = try! NSRegularExpression(pattern: "\\s+|[\\p{L}\\p{N}'’_-]+|[^\\s\\p{L}\\p{N}]")

    static func tokens(_ s: String) -> [String] {
        let ns = s as NSString
        return regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// Résultat avec les mots modifiés surlignés, ou nil si le diff n'apporte rien
    /// (aucun changement, ou texte presque entièrement réécrit).
    static func highlighted(original: String, result: String) -> (text: AttributedString, changes: Int)? {
        let a = tokens(original), b = tokens(result)
        let n = a.count, m = b.count
        guard n > 0, m > 0, n * m <= 4_000_000 else { return nil }

        // LCS calculée depuis la fin : dp[i][j] = LCS(a[i...], b[j...]).
        var dp = [Int32](repeating: 0, count: (n + 1) * (m + 1))
        func at(_ i: Int, _ j: Int) -> Int32 { dp[i * (m + 1) + j] }
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i * (m + 1) + j] = a[i] == b[j] ? at(i + 1, j + 1) + 1 : max(at(i + 1, j), at(i, j + 1))
            }
        }

        var inserted = [Bool](repeating: false, count: m)
        var i = 0, j = 0
        while j < m {
            if i < n && a[i] == b[j] { i += 1; j += 1 }
            else if i < n && at(i + 1, j) >= at(i, j + 1) { i += 1 }
            else { inserted[j] = true; j += 1 }
        }

        let words = b.indices.filter { !b[$0].allSatisfy(\.isWhitespace) }
        let changedWords = words.filter { inserted[$0] }.count
        guard changedWords > 0, Double(changedWords) / Double(max(words.count, 1)) <= 0.5 else { return nil }

        var out = AttributedString()
        var changes = 0
        var previousChanged = false
        for k in 0..<m {
            var piece = AttributedString(b[k])
            let isWord = !b[k].allSatisfy(\.isWhitespace)
            if inserted[k] && isWord {
                piece.backgroundColor = Color.green.opacity(0.28)
                if !previousChanged { changes += 1 }
                previousChanged = true
            } else if isWord {
                previousChanged = false
            }
            out += piece
        }
        return (out, changes)
    }
}

// MARK: - Panneau de résultat

@MainActor
final class ResultModel: ObservableObject {
    @Published var action: PlumeAction
    @Published var result = ""
    @Published var loading = false
    @Published var error: String?
    @Published var diff: (text: AttributedString, changes: Int)?
    /// Claude a renvoyé le texte d'origine à l'identique (ex. : aucune faute à corriger).
    @Published var unchanged = false
    let original: String
    let sourceApp: NSRunningApplication?
    private var lastPrompt: String?
    private let client = ClaudeClient()
    var onClose: () -> Void = {}

    init(original: String, sourceApp: NSRunningApplication?, action: PlumeAction) {
        self.original = original
        self.sourceApp = sourceApp
        self.action = action
    }

    var trimmedOriginal: String { original.trimmingCharacters(in: .whitespacesAndNewlines) }

    var backendLabel: String {
        guard let b = Backend.resolve() else { return "" }
        return "\(Models.current.name) · \(b.label)"
    }

    func run(_ a: PlumeAction) {
        action = a
        if a.isFreeForm {
            client.cancel()
            result = ""; error = nil; loading = false; diff = nil; unchanged = false
            return
        }
        send(Prompts.build(instruction: a.resolvedInstruction, text: trimmedOriginal))
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
        client.run(prompt: prompt) { [weak self] r in
            guard let self else { return }
            self.loading = false
            switch r {
            case .success(let s):
                self.result = s.trimmingCharacters(in: .whitespacesAndNewlines)
                self.diff = WordDiff.highlighted(original: self.trimmedOriginal, result: self.result)
                func norm(_ s: String) -> String { s.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
                self.unchanged = norm(self.result) == norm(self.trimmedOriginal)
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
        client.cancel()
        onClose()
    }
}

struct ResultView: View {
    @ObservedObject var model: ResultModel
    var openSettings: () -> Void = {}
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
        .frame(width: 520)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.1)))
        .background(
            Button("") { model.close() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
        )
        .onAppear { if model.action.isFreeForm { fieldFocused = true } }
    }

    private var header: some View {
        HStack {
            Menu {
                ForEach(ActionStore.all) { a in
                    Button { model.run(a) } label: { Label(a.title, systemImage: a.icon) }
                }
            } label: {
                Text(model.action.title).font(.system(size: 15, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            Text(model.backendLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button { model.close() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(HoverButtonStyle())
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
                Button(expanded ? L.t("Afficher moins", "Show less") : L.t("Afficher plus", "Show more")) { expanded.toggle() }
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
                Text(L.t("Claude réfléchit…", "Claude is thinking…")).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
        } else if let e = model.error {
            VStack(alignment: .leading, spacing: 6) {
                Text(e)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if Backend.resolve() == nil {
                    Button(L.t("Ouvrir les réglages", "Open Settings")) { openSettings() }
                }
            }
        } else if model.result.isEmpty {
            Text(model.action.isFreeForm ? L.t("Que veux-tu faire avec ce texte ?", "What should Claude do with this text?") : "")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if model.unchanged {
                    Label(model.action.id == "fix"
                          ? L.t("Aucune faute trouvée, ton texte est correct.", "No mistakes found, your text is correct.")
                          : L.t("Aucune modification nécessaire.", "No changes needed."),
                          systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.green)
                }
                if model.result.count > 900 {
                    ScrollView { resultText }.frame(height: 320)
                } else {
                    resultText
                }
                if let d = model.diff {
                    Text(L.t("\(d.changes) modification(s) surlignée(s)", "\(d.changes) change(s) highlighted"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var resultText: some View {
        Group {
            if let d = model.diff { Text(d.text) } else { Text(model.result) }
        }
        .font(.system(size: 14))
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").foregroundStyle(.purple)
            TextField(model.result.isEmpty ? L.t("Demander à Claude…", "Ask Claude…") : L.t("Demander un suivi", "Ask a follow-up"),
                      text: $followUp)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .onSubmit {
                    model.ask(followUp)
                    followUp = ""
                }
            Spacer(minLength: 4)
            Button { model.regenerate() } label: { Label(L.t("Régénérer", "Retry"), systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered)
                .disabled(model.loading || model.result.isEmpty && model.error == nil)
            Button {
                model.copy()
                copied = true
                // Bref retour « Copié », puis fermeture du panneau.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { model.close() }
            } label: {
                Label(copied ? L.t("Copié", "Copied") : L.t("Copier", "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.loading || model.result.isEmpty)
            Button(L.t("Remplacer", "Replace")) { model.replace() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.loading || model.result.isEmpty)
        }
    }
}
