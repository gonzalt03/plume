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
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.title = L.t("Réglages de Plume", "Plume Settings")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsRoot: View {
    @AppStorage("uiLanguage") private var uiLanguage = "auto"

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L.t("Général", "General"), systemImage: "gearshape") }
            ActionsSettings()
                .tabItem { Label(L.t("Actions", "Actions"), systemImage: "square.grid.2x2") }
            AppsSettings()
                .tabItem { Label(L.t("Apps exclues", "Excluded apps"), systemImage: "nosign") }
        }
        .frame(width: 640, height: 720)
        .id(uiLanguage) // reconstruit l'interface quand la langue change
    }
}

// MARK: Général

struct GeneralSettings: View {
    @AppStorage("provider") private var provider = "auto"
    @AppStorage("model") private var model = "haiku"
    @AppStorage("uiLanguage") private var uiLanguage = "auto"
    @AppStorage("translateTarget") private var translateTarget = ""
    @AppStorage("customInstructions") private var customInstructions = ""
    @AppStorage("enabled") private var autoBar = true
    @AppStorage("hotkey") private var hotkey = "ctrlOptC"
    @AppStorage("autoCheckUpdates") private var autoUpdates = true
    @State private var apiKeyInput = ""
    @State private var hasKey = Keychain.apiKey() != nil
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var cliFound: Bool { Backend.claudePath() != nil }

    var body: some View {
        Form {
            Section("Claude") {
                Picker(L.t("Accès à Claude", "Claude access"), selection: $provider) {
                    Text(L.t("Automatique", "Automatic")).tag("auto")
                    Text("Claude Code").tag("cli")
                    Text(L.t("Clé API Anthropic", "Anthropic API key")).tag("api")
                }
                Text(statusText).font(.caption).foregroundStyle(.secondary)

                HStack {
                    SecureField(hasKey ? L.t("Clé enregistrée (••••)", "Key saved (••••)") : "sk-ant-…", text: $apiKeyInput)
                    Button(L.t("Enregistrer", "Save")) {
                        Keychain.setAPIKey(apiKeyInput)
                        apiKeyInput = ""
                        hasKey = Keychain.apiKey() != nil
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    if hasKey {
                        Button(L.t("Supprimer", "Remove"), role: .destructive) {
                            Keychain.setAPIKey(nil)
                            hasKey = false
                        }
                    }
                }
                Link(L.t("Obtenir une clé API sur console.anthropic.com", "Get an API key at console.anthropic.com"),
                     destination: URL(string: "https://console.anthropic.com/settings/keys")!)
                    .font(.caption)

                Picker(L.t("Modèle", "Model"), selection: $model) {
                    ForEach(Models.all, id: \.id) { Text($0.label).tag($0.id) }
                }
            }

            Section(L.t("Langue", "Language")) {
                Picker(L.t("Interface", "Interface"), selection: $uiLanguage) {
                    Text(L.t("Automatique (système)", "Automatic (system)")).tag("auto")
                    Text("Français").tag("fr")
                    Text("English").tag("en")
                }
                Picker(L.t("Traduire vers", "Translate into"), selection: Binding(
                    get: { Settings.translateTarget },
                    set: { translateTarget = $0 })) {
                    ForEach(Settings.translateLanguages, id: \.id) { lang in
                        Text(L.lang == .fr ? lang.fr : lang.en).tag(lang.id)
                    }
                }
            }

            Section {
                TextEditor(text: $customInstructions)
                    .font(.system(size: 12))
                    .frame(height: 60)
            } header: {
                Text(L.t("Consignes personnelles", "Personal instructions"))
            } footer: {
                Text(L.t("Ajoutées à chaque requête. Ex. : « Vouvoie toujours. N'utilise jamais de tiret cadratin. »",
                         "Added to every request. E.g. \"Use British spelling. Never use em dashes.\""))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L.t("Comportement", "Behavior")) {
                Toggle(L.t("Afficher la barre à chaque sélection", "Show the bar on every selection"), isOn: $autoBar)
                Picker(L.t("Raccourci clavier", "Keyboard shortcut"), selection: $hotkey) {
                    Text(L.t("Aucun", "None")).tag("none")
                    ForEach(HotKey.presets, id: \.id) { Text($0.label).tag($0.id) }
                }
                Toggle(L.t("Lancer à l'ouverture de session", "Launch at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle(L.t("Vérifier automatiquement les mises à jour", "Check for updates automatically"), isOn: $autoUpdates)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        let cli = cliFound ? L.t("Claude Code détecté", "Claude Code found") : L.t("Claude Code non installé", "Claude Code not installed")
        let key = hasKey ? L.t("clé API enregistrée", "API key saved") : L.t("aucune clé API", "no API key")
        let used: String
        switch Backend.resolve() {
        case .cli?: used = L.t("Plume utilise Claude Code (ton abonnement).", "Plume uses Claude Code (your subscription).")
        case .api?: used = L.t("Plume utilise l'API Anthropic (facturée à l'usage).", "Plume uses the Anthropic API (pay as you go).")
        case nil: used = L.t("Aucun accès configuré.", "No access configured.")
        }
        return "\(cli), \(key). \(used)"
    }
}

// MARK: Actions

struct ActionsSettings: View {
    @State private var actions = ActionStore.all
    @State private var selection: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                List(selection: $selection) {
                    ForEach($actions) { $action in
                        HStack {
                            Toggle("", isOn: $action.inToolbar).labelsHidden()
                                .help(L.t("Afficher dans la barre", "Show in the bar"))
                            Image(systemName: action.icon).frame(width: 20)
                            Text(action.title)
                        }
                        .tag(action.id)
                    }
                    .onMove { actions.move(fromOffsets: $0, toOffset: $1) }
                }
                .frame(width: 230)
                HStack(spacing: 4) {
                    Button { add() } label: { Image(systemName: "plus") }
                    Button { remove() } label: { Image(systemName: "minus") }.disabled(selection == nil)
                    Button { move(-1) } label: { Image(systemName: "arrow.up") }.disabled(selection == nil)
                    Button { move(1) } label: { Image(systemName: "arrow.down") }.disabled(selection == nil)
                    Spacer()
                    Button(L.t("Réinitialiser", "Reset")) {
                        ActionStore.reset()
                        actions = ActionStore.all
                        selection = nil
                    }
                }
                .frame(width: 230)
            }

            if let index = actions.firstIndex(where: { $0.id == selection }) {
                ActionEditor(action: $actions[index])
            } else {
                Text(L.t("Sélectionne une action pour la modifier. La case cochée l'affiche dans la barre ; l'ordre de la liste est celui de la barre.",
                         "Select an action to edit it. The checkbox shows it in the bar; the list order is the bar order."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding()
        .onChange(of: actions) { ActionStore.all = $0 }
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

    private func move(_ delta: Int) {
        guard let i = actions.firstIndex(where: { $0.id == selection }) else { return }
        let j = i + delta
        guard actions.indices.contains(j) else { return }
        actions.swapAt(i, j)
    }
}

struct ActionEditor: View {
    @Binding var action: PlumeAction

    var body: some View {
        Form {
            TextField(L.t("Nom", "Name"), text: $action.title)
            Picker(L.t("Icône", "Icon"), selection: $action.icon) {
                ForEach(ActionStore.iconChoices, id: \.self) { name in
                    Label(name, systemImage: name).tag(name)
                }
            }
            TextField(L.t("Bulle d'aide", "Tooltip"), text: $action.hint)
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("Consigne envoyée à Claude", "Instruction sent to Claude"))
                TextEditor(text: $action.instruction)
                    .font(.system(size: 12))
                    .frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.secondary.opacity(0.3)))
                Text(L.t("Vide : tu écris ta consigne à chaque fois. Variables : {target} (langue de traduction), {native} (langue de l'interface).",
                         "Empty: you type the instruction each time. Variables: {target} (translation language), {native} (interface language)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Apps exclues

struct AppsSettings: View {
    @State private var ids = Settings.excludedBundleIDs
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L.t("La barre n'apparaît jamais dans ces apps (le raccourci clavier reste disponible).",
                     "The bar never appears in these apps (the keyboard shortcut still works)."))
                .foregroundStyle(.secondary)
            List(selection: $selection) {
                ForEach(ids, id: \.self) { id in
                    HStack {
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 18, height: 18)
                            Text(FileManager.default.displayName(atPath: url.path))
                        } else {
                            Text(id)
                        }
                    }
                    .tag(id)
                }
            }
            HStack {
                Button { addApp() } label: { Label(L.t("Ajouter une app…", "Add an app…"), systemImage: "plus") }
                Button { ids.removeAll { $0 == selection }; selection = nil } label: {
                    Label(L.t("Retirer", "Remove"), systemImage: "minus")
                }
                .disabled(selection == nil)
            }
        }
        .padding()
        .onChange(of: ids) { Settings.excludedBundleIDs = $0 }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !ids.contains(id) { ids.append(id) }
        }
    }
}
