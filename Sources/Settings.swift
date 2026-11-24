import Cocoa
import Security

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

func plumeError(_ msg: String) -> NSError {
    NSError(domain: "Plume", code: 1, userInfo: [NSLocalizedDescriptionKey: msg])
}

// MARK: - Langue de l'interface

enum Lang: String { case fr, en }

enum L {
    static var lang: Lang {
        switch Settings.uiLanguage {
        case "fr": return .fr
        case "en": return .en
        default: return (Locale.preferredLanguages.first ?? "en").hasPrefix("fr") ? .fr : .en
        }
    }

    /// Texte selon la langue de l'interface.
    static func t(_ fr: String, _ en: String) -> String { lang == .fr ? fr : en }

    /// Nom de la langue de l'interface, pour les consignes envoyées à Claude.
    static var nativeLanguageName: String { lang == .fr ? "French" : "English" }
}

// MARK: - Réglages

enum Settings {
    private static let d = UserDefaults.standard

    /// Afficher la barre automatiquement à chaque sélection.
    static var autoBar: Bool {
        get { d.object(forKey: "enabled") as? Bool ?? true }
        set { d.set(newValue, forKey: "enabled") }
    }

    /// "auto" (Claude Code si présent, sinon clé API), "cli" ou "api".
    static var provider: String {
        get { d.string(forKey: "provider") ?? "auto" }
        set { d.set(newValue, forKey: "provider") }
    }

    static var model: String {
        get { d.string(forKey: "model") ?? "haiku" }
        set { d.set(newValue, forKey: "model") }
    }

    /// "auto", "fr" ou "en".
    static var uiLanguage: String {
        get { d.string(forKey: "uiLanguage") ?? "auto" }
        set { d.set(newValue, forKey: "uiLanguage") }
    }

    /// Langue cible de l'action Traduire (nom anglais de la langue).
    static var translateTarget: String {
        get {
            let v = d.string(forKey: "translateTarget") ?? ""
            return v.isEmpty ? (L.lang == .fr ? "English" : "French") : v
        }
        set { d.set(newValue, forKey: "translateTarget") }
    }

    /// Consignes ajoutées à toutes les requêtes (style, typographie...).
    static var customInstructions: String {
        get { d.string(forKey: "customInstructions") ?? "" }
        set { d.set(newValue, forKey: "customInstructions") }
    }

    static var excludedBundleIDs: [String] {
        get { d.stringArray(forKey: "excludedApps") ?? [] }
        set { d.set(newValue, forKey: "excludedApps") }
    }

    /// Raccourci global : identifiant de préréglage (voir HotKey.presets).
    static var hotkey: String {
        get { d.string(forKey: "hotkey") ?? "ctrlOptC" }
        set { d.set(newValue, forKey: "hotkey") }
    }

    /// Apps où la barre ne doit jamais apparaître.
    static let systemIgnoredBundleIDs: Set<String> = [
        "com.apple.finder", "com.apple.dock", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.notificationcenterui",
    ]

    static func isIgnored(_ bundleID: String?) -> Bool {
        guard let id = bundleID else { return false }
        return systemIgnoredBundleIDs.contains(id) || excludedBundleIDs.contains(id)
    }

    static let translateLanguages: [(id: String, fr: String, en: String)] = [
        ("English", "Anglais", "English"), ("French", "Français", "French"),
        ("Spanish", "Espagnol", "Spanish"), ("German", "Allemand", "German"),
        ("Italian", "Italien", "Italian"), ("Portuguese", "Portugais", "Portuguese"),
        ("Dutch", "Néerlandais", "Dutch"), ("Chinese", "Chinois", "Chinese"),
        ("Japanese", "Japonais", "Japanese"),
    ]
}

// MARK: - Modèles

struct ModelChoice {
    let id: String       // alias utilisé par la CLI
    let apiID: String    // identifiant de l'API Messages
    let name: String
    var label: String {
        switch id {
        case "haiku": return L.t("Haiku (rapide)", "Haiku (fast)")
        case "sonnet": return L.t("Sonnet (équilibré)", "Sonnet (balanced)")
        default: return L.t("Opus (le plus fin)", "Opus (most capable)")
        }
    }
}

enum Models {
    static let all = [
        ModelChoice(id: "haiku", apiID: "claude-haiku-5-5", name: "Haiku"),
        ModelChoice(id: "sonnet", apiID: "claude-sonnet-5-5", name: "Sonnet"),
        ModelChoice(id: "opus", apiID: "claude-opus-5-5", name: "Opus"),
    ]
    static var current: ModelChoice { all.first { $0.id == Settings.model } ?? all[0] }
}

// MARK: - Trousseau (clé API)

enum Keychain {
    private static let service = "local.plume"
    private static let account = "anthropic-api-key"

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func apiKey() -> String? {
        var q = base
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    static func setAPIKey(_ key: String?) {
        SecItemDelete(base as CFDictionary)
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else { return }
        var q = base
        q[kSecValueData as String] = key.data(using: .utf8)
        SecItemAdd(q as CFDictionary, nil)
    }
}

// MARK: - Actions (personnalisables)

struct PlumeAction: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var icon: String
    /// Consigne envoyée à Claude. Vide : l'utilisateur écrit sa propre consigne.
    var instruction: String
    var hint: String
    var inToolbar: Bool

    var isFreeForm: Bool { instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Texte de la bulle d'aide.
    var tooltip: String {
        let h = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !h.isEmpty { return "\(title) : \(h)" }
        if isFreeForm { return "\(title) : " + L.t("écris ta propre consigne", "write your own instruction") }
        let short = instruction.count > 60 ? String(instruction.prefix(60)) + "…" : instruction
        return "\(title) : \(short)"
    }

    /// Consigne finale, avec les variables remplacées.
    var resolvedInstruction: String {
        instruction
            .replacingOccurrences(of: "{target}", with: Settings.translateTarget)
            .replacingOccurrences(of: "{native}", with: L.nativeLanguageName)
    }
}

enum ActionStore {
    static let iconChoices = [
        "sparkles", "text.badge.checkmark", "wand.and.stars", "character.bubble", "list.bullet",
        "arrow.down.right.and.arrow.up.left", "arrow.up.left.and.arrow.down.right", "envelope",
        "briefcase", "face.smiling", "graduationcap", "lightbulb", "questionmark.circle",
        "text.quote", "pencil", "highlighter", "textformat", "chevron.left.forwardslash.chevron.right",
        "bubble.left.and.bubble.right", "hand.thumbsup", "checklist", "number", "globe", "star",
    ]

    static func defaults() -> [PlumeAction] {
        let fr = L.lang == .fr
        return [
            PlumeAction(id: "ask", title: L.t("Demander à Claude", "Ask Claude"), icon: "sparkles",
                        instruction: "", hint: "", inToolbar: true),
            PlumeAction(id: "fix", title: L.t("Corriger", "Fix"), icon: "text.badge.checkmark",
                        instruction: fr
                        ? "Corrige uniquement les fautes d'orthographe, de grammaire, de conjugaison, d'accord, de ponctuation et de typographie. Ne modifie ni le style, ni le vocabulaire, ni la structure des phrases au-delà du strict nécessaire. Si le texte ne contient aucune faute, renvoie-le tel quel."
                        : "Fix only spelling, grammar, agreement, punctuation and typography mistakes. Do not change the style, vocabulary or sentence structure beyond what is strictly necessary. If the text has no mistakes, return it unchanged.",
                        hint: L.t("orthographe et grammaire, sans changer le style", "spelling and grammar, style unchanged"),
                        inToolbar: true),
            PlumeAction(id: "rephrase", title: L.t("Reformuler", "Rephrase"), icon: "wand.and.stars",
                        instruction: fr
                        ? "Réécris ce texte pour corriger toutes les fautes et le rendre plus clair, plus fluide et plus précis, en conservant le sens, le niveau de langue, le ton et toutes les informations. Ne rallonge pas le texte inutilement et n'invente rien."
                        : "Rewrite this text to fix every mistake and make it clearer, smoother and more precise, keeping its meaning, register, tone and all of its information. Do not make it longer than needed and do not invent anything.",
                        hint: L.t("corriger et clarifier le texte", "fix and clarify the text"),
                        inToolbar: true),
            PlumeAction(id: "translate", title: L.t("Traduire", "Translate"), icon: "character.bubble",
                        instruction: "Translate this text into {target}. If it is already in {target}, translate it into {native} instead. Keep the tone and formatting.",
                        hint: L.t("vers la langue choisie dans les réglages", "into the language chosen in Settings"),
                        inToolbar: true),
            PlumeAction(id: "summarize", title: L.t("Résumer", "Summarize"), icon: "list.bullet",
                        instruction: fr
                        ? "Résume ce texte en quelques phrases claires (ou en une courte liste à puces si c'est plus adapté), dans la langue du texte."
                        : "Summarize this text in a few clear sentences (or a short bullet list if that fits better), in the language of the text.",
                        hint: L.t("l'essentiel en quelques lignes", "the gist in a few lines"),
                        inToolbar: true),
            PlumeAction(id: "shorten", title: L.t("Raccourcir", "Shorten"), icon: "arrow.down.right.and.arrow.up.left",
                        instruction: fr
                        ? "Rends ce texte plus concis en conservant toutes les informations importantes, et corrige au passage les fautes."
                        : "Make this text more concise while keeping all important information, and fix any mistakes along the way.",
                        hint: L.t("version plus concise", "a more concise version"),
                        inToolbar: true),
        ]
    }

    static var all: [PlumeAction] {
        get {
            if let data = UserDefaults.standard.data(forKey: "actions"),
               let list = try? JSONDecoder().decode([PlumeAction].self, from: data), !list.isEmpty {
                return list
            }
            return defaults()
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: "actions")
            }
        }
    }

    static var isCustomized: Bool { UserDefaults.standard.data(forKey: "actions") != nil }

    static func reset() { UserDefaults.standard.removeObject(forKey: "actions") }

    static var toolbar: [PlumeAction] { all.filter(\.inToolbar) }
}
