import Cocoa
import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Fenêtre de réglages

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsRoot())
            host.sizingOptions = [] // taille fixée ci-dessous, contenu sous la barre de titre
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 820, height: 600)) // la barre de titre est désormais sous le contenu
            w.center()
            window = w
        }
        window?.title = L.t("Réglages de Plume", "Plume Settings")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Charte

enum Brand {
    static let accent = Color(red: 0.545, green: 0.361, blue: 0.965)          // #8b5cf6
    static let gradient = LinearGradient(
        colors: [Color(red: 0.937, green: 0.541, blue: 0.420),                // #ef8a6b
                 Color(red: 0.635, green: 0.310, blue: 0.878),                // #a24fe0
                 Color(red: 0.427, green: 0.290, blue: 1.0)],                 // #6d4aff
        startPoint: .topTrailing, endPoint: .bottomLeading)
    static let soft = LinearGradient(
        colors: [Color(red: 0.427, green: 0.290, blue: 1.0).opacity(0.10),
                 Color(red: 0.937, green: 0.541, blue: 0.420).opacity(0.10)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    static let gray = Color(red: 0.56, green: 0.56, blue: 0.60)
    static let orange = Color(red: 0.95, green: 0.60, blue: 0.18)
    static let red = Color(red: 0.93, green: 0.35, blue: 0.32)
    static let blue = Color(red: 0.25, green: 0.55, blue: 1.0)
    static let green = Color(red: 0.20, green: 0.76, blue: 0.41)
    static let teal = Color(red: 0.18, green: 0.70, blue: 0.77)
    static let pink = Color(red: 0.91, green: 0.36, blue: 0.60)
    static let indigo = Color(red: 0.37, green: 0.36, blue: 0.90)
}

// MARK: - Composants communs

/// Pastille d'icône colorée, façon Réglages Système.
struct IconTile: View {
    let symbol: String
    var color: Color? = nil
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(Brand.gradient))
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol)
                .font(.system(size: size * 0.55, weight: .semibold))
                .foregroundStyle(.white))
    }
}

struct GroupTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 4).padding(.top, 14).padding(.bottom, 2)
    }
}

struct Footnote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
    }
}

/// Groupe arrondi dont les lignes sont séparées par un trait fin.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        _VariadicView.Tree(CardLayout()) { content }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

private struct CardLayout: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != children.last?.id { Divider().padding(.leading, 12) }
            }
        }
    }
}

/// Ligne de réglage : tuile facultative, libellé, sous-titre, contrôle à droite.
struct Row<Trailing: View>: View {
    var icon: String? = nil
    var color: Color? = nil
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            if let icon { IconTile(symbol: icon, color: color) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(minHeight: 40)
    }
}

/// Bandeau d'en-tête d'une section.
struct Hero<Trailing: View>: View {
    let icon: String
    var color: Color? = nil
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: icon, color: color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.soft))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.accent.opacity(0.18)))
    }
}

struct StatusPill: View {
    let text: String
    let ok: Bool
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(ok ? Color.green : Color.secondary).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11))
        }
        .foregroundStyle(ok ? Color.green : Color.secondary)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Capsule().fill((ok ? Color.green : Color.secondary).opacity(0.13)))
    }
}

/// Raccourci affiché en touches de clavier.
struct KeyCaps: View {
    let label: String
    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(Self.split(label).enumerated()), id: \.offset) { _, key in
                Text(key).font(.system(size: 12))
                    .frame(minWidth: 14)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.15)))
            }
        }
    }

    static func split(_ label: String) -> [String] {
        let modifiers = Set("⌃⌥⇧⌘")
        var keys = label.prefix { modifiers.contains($0) }.map(String.init)
        let rest = String(label.drop { modifiers.contains($0) })
        if !rest.isEmpty { keys.append(rest) }
        return keys
    }
}

struct SidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Page de réglages : défilement et marges communs.
struct Page<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) { content }
                .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Racine

enum SettingsPane: String, CaseIterable, Identifiable {
    case claude, general, actions, apps, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .claude: return "Claude"
        case .general: return L.t("Général", "General")
        case .actions: return L.t("Actions", "Actions")
        case .apps: return L.t("Apps exclues", "Excluded apps")
        case .about: return L.t("À propos", "About")
        }
    }

    var icon: String {
        switch self {
        case .claude: return "sparkles"
        case .general: return "gearshape.fill"
        case .actions: return "square.grid.2x2.fill"
        case .apps: return "nosign"
        case .about: return "info"
        }
    }

    var color: Color? {
        switch self {
        case .claude: return nil
        case .general: return Brand.gray
        case .actions: return Brand.orange
        case .apps: return Brand.red
        case .about: return Brand.blue
        }
    }
}

struct SettingsRoot: View {
    @AppStorage("uiLanguage") private var uiLanguage = "auto"
    @AppStorage("settingsPane") private var paneID = SettingsPane.claude.rawValue
    private var pane: SettingsPane {
        get { SettingsPane(rawValue: paneID) ?? .claude }
        nonmutating set { paneID = newValue.rawValue }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text(pane.title).font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 24).frame(height: 52)
                Group {
                    switch pane {
                    case .claude: ClaudeSettings()
                    case .general: GeneralSettings()
                    case .actions: ActionsSettings()
                    case .apps: AppsSettings()
                    case .about: AboutSettings()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .tint(Brand.accent)
        .id(uiLanguage) // reconstruit l'interface quand la langue change
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 38, height: 38)
                Text("Plume").font(.system(size: 14, weight: .semibold))
            }
            .padding(.horizontal, 6).padding(.top, 44).padding(.bottom, 14)

            ForEach(SettingsPane.allCases) { p in
                if p == .about { Spacer().frame(height: 10) }
                sidebarItem(p)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 210)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(SidebarMaterial())
    }

    private func sidebarItem(_ p: SettingsPane) -> some View {
        Button { pane = p } label: {
            HStack(spacing: 9) {
                IconTile(symbol: p.icon, color: p.color)
                Text(p.title)
                Spacer()
            }
            .padding(.horizontal, 8).padding(.vertical, 5)
            .foregroundStyle(pane == p ? Color.white : Color.primary)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(pane == p ? Brand.accent : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Claude

struct ClaudeSettings: View {
    @AppStorage("provider") private var provider = "auto"
    @AppStorage("model") private var model = "haiku"
    @AppStorage("customInstructions") private var customInstructions = ""
    @State private var apiKeyInput = ""
    @State private var hasKey = Keychain.apiKey() != nil

    private var cliFound: Bool { Backend.claudePath() != nil }

    var body: some View {
        Page {
            hero

            GroupTitle(L.t("Accès", "Access"))
            Card {
                Row(title: L.t("Source", "Source"),
                    subtitle: L.t("Automatique : Claude Code si installé, sinon la clé API.",
                                  "Automatic: Claude Code if installed, otherwise the API key.")) {
                    Picker("", selection: $provider) {
                        Text(L.t("Automatique", "Automatic")).tag("auto")
                        Text("Claude Code").tag("cli")
                        Text(L.t("Clé API", "API key")).tag("api")
                    }
                    .pickerStyle(.segmented).labelsHidden().fixedSize()
                }
                if provider != "cli" { apiKeyRow }
            }

            GroupTitle(L.t("Modèle", "Model"))
            HStack(spacing: 10) {
                ForEach(Models.all, id: \.id) { m in modelCard(m) }
            }

            GroupTitle(L.t("Consignes personnelles", "Personal instructions"))
            Card {
                TextEditor(text: $customInstructions)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .frame(height: 64)
                    .padding(8)
            }
            Footnote(L.t("Ajoutées à chaque requête. Ex. : « Vouvoie toujours. N'utilise jamais de tiret cadratin. »",
                         "Added to every request. E.g. \"Use British spelling. Never use em dashes.\""))
        }
    }

    private var hero: some View {
        let title: String, subtitle: String
        switch Backend.resolve() {
        case .cli?:
            title = L.t("Plume utilise Claude Code", "Plume uses Claude Code")
            subtitle = L.t("Ton abonnement Claude, sans clé API ni facturation à l'usage.",
                           "Your Claude subscription, no API key or pay-as-you-go billing.")
        case .api?:
            title = L.t("Plume utilise l'API Anthropic", "Plume uses the Anthropic API")
            subtitle = L.t("Facturée à l'usage sur ta clé API.", "Billed per use on your API key.")
        case nil:
            title = L.t("Aucun accès configuré", "No access configured")
            subtitle = L.t("Installe Claude Code ou enregistre une clé API ci-dessous.",
                           "Install Claude Code or save an API key below.")
        }
        return Hero(icon: "sparkles", title: title, subtitle: subtitle) {
            VStack(alignment: .trailing, spacing: 5) {
                StatusPill(text: cliFound ? L.t("Claude Code détecté", "Claude Code found")
                                          : L.t("Claude Code non installé", "Claude Code not installed"), ok: cliFound)
                StatusPill(text: hasKey ? L.t("Clé API enregistrée", "API key saved")
                                        : L.t("Aucune clé API", "No API key"), ok: hasKey)
            }
        }
    }

    private var apiKeyRow: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(L.t("Clé API Anthropic", "Anthropic API key"))
                Text(.init(L.t("Stockée dans le trousseau macOS. [Obtenir une clé](https://console.anthropic.com/settings/keys)",
                               "Stored in the macOS Keychain. [Get a key](https://console.anthropic.com/settings/keys)")))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            SecureField(hasKey ? L.t("Clé enregistrée (••••)", "Key saved (••••)") : "sk-ant-…", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder).frame(width: 170)
            Button(L.t("Enregistrer", "Save")) {
                Keychain.setAPIKey(apiKeyInput)
                apiKeyInput = ""
                hasKey = Keychain.apiKey() != nil
            }
            .buttonStyle(.borderedProminent)
            .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
            if hasKey {
                Button(role: .destructive) {
                    Keychain.setAPIKey(nil)
                    hasKey = false
                } label: { Image(systemName: "trash") }
                .help(L.t("Supprimer la clé", "Remove the key"))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func modelCard(_ m: ModelChoice) -> some View {
        let selected = model == m.id
        let level = (Models.all.firstIndex { $0.id == m.id } ?? 0) + 1
        let caption: String
        switch m.id {
        case "haiku": caption = L.t("Rapide, idéal au quotidien", "Fast, great for everyday use")
        case "sonnet": caption = L.t("Équilibré", "Balanced")
        default: caption = L.t("Le plus fin, plus lent", "Most capable, slower")
        }
        return Button { model = m.id } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(m.name).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Brand.accent) }
                }
                Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 3) {
                    ForEach(1...3, id: \.self) { i in
                        Capsule().fill(i <= level ? AnyShapeStyle(Brand.gradient) : AnyShapeStyle(Color.primary.opacity(0.12)))
                            .frame(height: 4)
                    }
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Brand.accent.opacity(0.14) : Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? Brand.accent : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Général

struct GeneralSettings: View {
    @AppStorage("uiLanguage") private var uiLanguage = "auto"
    @AppStorage("translateTarget") private var translateTarget = ""
    @AppStorage("enabled") private var autoBar = true
    @AppStorage("hotkey") private var hotkey = "ctrlOptC"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Page {
            GroupTitle(L.t("Barre d'actions", "Action bar"))
            Card {
                Row(icon: "cursorarrow.rays", color: Brand.indigo,
                    title: L.t("Afficher la barre à chaque sélection", "Show the bar on every selection"),
                    subtitle: L.t("Sinon, seulement via le raccourci clavier.", "Otherwise, only with the keyboard shortcut.")) {
                    Toggle("", isOn: $autoBar).toggleStyle(.switch).labelsHidden()
                }
                Row(icon: "keyboard", color: Brand.gray, title: L.t("Raccourci clavier", "Keyboard shortcut")) {
                    if let label = HotKey.label(for: hotkey) { KeyCaps(label: label) }
                    Picker("", selection: $hotkey) {
                        Text(L.t("Aucun", "None")).tag("none")
                        ForEach(HotKey.presets, id: \.id) { Text($0.label).tag($0.id) }
                    }
                    .labelsHidden().fixedSize()
                }
            }

            GroupTitle(L.t("Langue", "Language"))
            Card {
                Row(icon: "globe", color: Brand.blue, title: L.t("Interface", "Interface")) {
                    Picker("", selection: $uiLanguage) {
                        Text(L.t("Automatique (système)", "Automatic (system)")).tag("auto")
                        Text("Français").tag("fr")
                        Text("English").tag("en")
                    }
                    .labelsHidden().fixedSize()
                }
                Row(icon: "character.bubble", color: Brand.teal, title: L.t("Traduire vers", "Translate into"),
                    subtitle: L.t("Langue cible de l'action Traduire.", "Target language of the Translate action.")) {
                    Picker("", selection: Binding(
                        get: { Settings.translateTarget },
                        set: { translateTarget = $0 })) {
                        ForEach(Settings.translateLanguages, id: \.id) { lang in
                            Text(L.lang == .fr ? lang.fr : lang.en).tag(lang.id)
                        }
                    }
                    .labelsHidden().fixedSize()
                }
            }

            GroupTitle(L.t("Système", "System"))
            Card {
                Row(icon: "power", color: Brand.green, title: L.t("Lancer à l'ouverture de session", "Launch at login")) {
                    Toggle("", isOn: $launchAtLogin).toggleStyle(.switch).labelsHidden()
                        .onChange(of: launchAtLogin) { on in
                            do {
                                if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
            }
        }
    }
}

// MARK: Actions

struct ActionsSettings: View {
    @State private var actions = ActionStore.all
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            barPreview
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    List(selection: $selection) {
                        ForEach($actions) { $action in
                            HStack(spacing: 8) {
                                Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(.tertiary)
                                IconTile(symbol: action.icon, color: action.isFreeForm ? nil : Brand.indigo)
                                Text(action.title).lineLimit(1)
                                Spacer()
                                Toggle("", isOn: $action.inToolbar).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                                    .help(L.t("Afficher dans la barre", "Show in the bar"))
                            }
                            .padding(.vertical, 2)
                            .tag(action.id)
                        }
                        .onMove { actions.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .scrollContentBackground(.hidden)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    HStack(spacing: 0) {
                        Button { add() } label: { Image(systemName: "plus").frame(width: 22, height: 16) }
                        Button { remove() } label: { Image(systemName: "minus").frame(width: 22, height: 16) }
                            .disabled(selection == nil)
                        Spacer()
                        Button(L.t("Réinitialiser", "Reset")) {
                            ActionStore.reset()
                            actions = ActionStore.all
                            selection = nil
                        }
                        .buttonStyle(.link)
                    }
                }
                .frame(width: 272)

                Group {
                    if let index = actions.firstIndex(where: { $0.id == selection }) {
                        ActionEditor(action: $actions[index])
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "hand.tap").font(.system(size: 24)).foregroundStyle(.tertiary)
                            Text(L.t("Sélectionne une action pour la modifier. L'interrupteur l'affiche dans la barre ; glisse les lignes pour changer l'ordre.",
                                     "Select an action to edit it. The switch shows it in the bar; drag rows to change the order."))
                                .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 4)
        .onChange(of: actions) { ActionStore.all = $0 }
    }

    /// Aperçu de la barre telle qu'elle apparaîtra, dans l'ordre de la liste.
    private var barPreview: some View {
        VStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(actions.filter(\.inToolbar)) { a in
                    Image(systemName: a.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(a.isFreeForm ? Brand.accent : Color.primary)
                        .frame(width: 30, height: 30)
                        .help(a.title)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 11).fill(.regularMaterial))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.1)))
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            Text(L.t("Aperçu de la barre, dans l'ordre de la liste", "Bar preview, in list order"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Brand.soft))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Brand.accent.opacity(0.18)))
    }

    private func add() {
        let a = PlumeAction(id: UUID().uuidString, title: L.t("Nouvelle action", "New action"), icon: "star",
                            instruction: L.t("Réécris ce texte sur un ton plus chaleureux.", "Rewrite this text in a warmer tone."),
                            hint: "", inToolbar: true)
        actions.append(a)
        selection = a.id
    }

    private func remove() {
        actions.removeAll { $0.id == selection }
        selection = nil
    }
}

struct ActionEditor: View {
    @Binding var action: PlumeAction
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Card {
                    Row(title: L.t("Nom", "Name")) {
                        TextField("", text: $action.title).textFieldStyle(.roundedBorder).frame(width: 190)
                    }
                    Row(title: L.t("Bulle d'aide", "Tooltip")) {
                        TextField("", text: $action.hint).textFieldStyle(.roundedBorder).frame(width: 190)
                    }
                }

                GroupTitle(L.t("Icône", "Icon"))
                Card {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(ActionStore.iconChoices, id: \.self) { name in
                            let on = name == action.icon
                            Button { action.icon = name } label: {
                                Image(systemName: name)
                                    .font(.system(size: 13))
                                    .frame(maxWidth: .infinity, minHeight: 30)
                                    .foregroundStyle(on ? Color.white : Color.primary)
                                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(on ? Brand.accent : Color.clear))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help(name)
                        }
                    }
                    .padding(10)
                }

                GroupTitle(L.t("Consigne envoyée à Claude", "Instruction sent to Claude"))
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $action.instruction)
                            .font(.system(size: 12))
                            .scrollContentBackground(.hidden)
                            .frame(height: 96)
                        HStack(spacing: 6) {
                            variableChip("{target}", L.t("langue de traduction", "translation language"))
                            variableChip("{native}", L.t("langue de l'interface", "interface language"))
                        }
                    }
                    .padding(10)
                }
                Footnote(L.t("Vide : tu écris ta consigne à chaque fois.", "Empty: you type the instruction each time."))
            }
        }
    }

    private func variableChip(_ token: String, _ label: String) -> some View {
        Button { action.instruction += token } label: {
            HStack(spacing: 4) {
                Text(token).font(.system(size: 11, design: .monospaced))
                Text(label).font(.system(size: 11))
            }
            .foregroundStyle(Brand.accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Brand.accent.opacity(0.13)))
        }
        .buttonStyle(.plain)
        .help(L.t("Insérer \(token)", "Insert \(token)"))
    }
}

// MARK: Apps exclues

struct AppsSettings: View {
    @State private var ids = Settings.excludedBundleIDs
    @State private var selection: String?
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Hero(icon: "nosign", color: Brand.red,
                 title: L.t("La barre n'apparaît jamais dans ces apps", "The bar never appears in these apps"),
                 subtitle: L.t("Le raccourci clavier reste disponible.", "The keyboard shortcut still works.")) { EmptyView() }
                .padding(.bottom, 12)

            Group {
                if ids.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle").font(.system(size: 24)).foregroundStyle(.tertiary)
                        Text(L.t("Aucune app exclue : la barre apparaît partout.", "No excluded app: the bar shows everywhere."))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(selection: $selection) {
                        ForEach(ids, id: \.self) { id in
                            HStack(spacing: 10) {
                                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 24, height: 24)
                                    Text(FileManager.default.displayName(atPath: url.path))
                                } else {
                                    Image(systemName: "app.dashed").font(.system(size: 18)).frame(width: 24, height: 24)
                                    Text(id).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .tag(id)
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(dropTargeted ? Brand.accent : Color.primary.opacity(0.08), lineWidth: dropTargeted ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
                for p in providers {
                    _ = p.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        DispatchQueue.main.async { add(url) }
                    }
                }
                return true
            }

            HStack(spacing: 0) {
                Button { pickApps() } label: { Image(systemName: "plus").frame(width: 22, height: 16) }
                Button { ids.removeAll { $0 == selection }; selection = nil } label: {
                    Image(systemName: "minus").frame(width: 22, height: 16)
                }
                .disabled(selection == nil)
                Spacer()
                Footnote(L.t("Astuce : glisse une app depuis le Finder.", "Tip: drag an app from the Finder."))
            }
            .padding(.top, 1)
        }
        .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 4)
        .onChange(of: ids) { Settings.excludedBundleIDs = $0 }
    }

    private func add(_ url: URL) {
        if let id = Bundle(url: url)?.bundleIdentifier, !ids.contains(id) { ids.append(id) }
    }

    private func pickApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(add)
    }
}

// MARK: À propos

struct AboutSettings: View {
    @AppStorage("autoCheckUpdates") private var autoUpdates = true
    @AppStorage("lastUpdateCheck") private var lastCheck: Double = 0

    private var version: String { Updater.shared.currentVersion }

    var body: some View {
        Page {
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
                Text("Plume").font(.system(size: 20, weight: .semibold))
                Text(statusLine).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)

            GroupTitle(L.t("Mises à jour", "Updates"))
            Card {
                Row(title: L.t("Vérifier automatiquement", "Check automatically"),
                    subtitle: L.t("Depuis les releases GitHub.", "From GitHub releases.")) {
                    Toggle("", isOn: $autoUpdates).toggleStyle(.switch).labelsHidden()
                }
                Row(title: L.t("Dernière vérification", "Last check"), subtitle: lastCheckText) {
                    Button(L.t("Rechercher maintenant", "Check now")) { Updater.shared.check(interactive: true) }
                }
            }

            GroupTitle(L.t("Liens", "Links"))
            Card {
                Row(title: L.t("Code source et notes de version", "Source code and release notes")) {
                    Link("GitHub ↗", destination: URL(string: "https://github.com/\(Updater.repo)")!)
                }
                Row(title: L.t("Signaler un problème", "Report an issue")) {
                    Link(L.t("Ouvrir une issue ↗", "Open an issue ↗"), destination: URL(string: "https://github.com/\(Updater.repo)/issues")!)
                }
            }
        }
    }

    private var statusLine: String {
        if let r = Updater.shared.available {
            return L.t("Version \(version) · mise à jour \(r.version) disponible", "Version \(version) · update \(r.version) available")
        }
        return L.t("Version \(version)", "Version \(version)")
    }

    private var lastCheckText: String {
        guard lastCheck > 0 else { return L.t("Jamais", "Never") }
        let date = Date(timeIntervalSince1970: lastCheck)
        if Date().timeIntervalSince(date) < 60 { return L.t("À l'instant", "Just now") }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: L.lang == .fr ? "fr_FR" : "en_US")
        return f.localizedString(for: date, relativeTo: Date())
    }
}
