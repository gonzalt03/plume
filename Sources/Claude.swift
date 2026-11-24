import Foundation

// MARK: - Consignes

enum Prompts {
    static var system: String {
        var s = """
        You are a writing assistant built into macOS. You receive text the user selected, between <text> tags, and an instruction.
        Reply ONLY with the requested result: no preamble, no commentary, no explanation, no quotes or tags around the result.
        Keep the language of the text (unless the instruction asks for a translation), its line breaks and its formatting. Do not add Markdown if the original text has none.
        If the instruction is a question about the text, answer it directly and briefly, in \(L.nativeLanguageName).
        """
        let custom = Settings.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { s += "\n\nAdditional preferences from the user (always apply them):\n\(custom)" }
        return s
    }

    static func build(instruction: String, text: String) -> String {
        "Instruction: \(instruction)\n\n<text>\n\(text)\n</text>"
    }

    static func followUp(original: String, current: String, request: String) -> String {
        """
        Original text:
        <text>
        \(original)
        </text>

        Current version:
        <version>
        \(current)
        </version>

        New instruction to apply to the current version: \(request)
        """
    }
}

// MARK: - Accès à Claude : CLI Claude Code ou API Anthropic

enum Backend {
    case cli(path: String)
    case api(key: String)

    var label: String {
        switch self {
        case .cli: return "Claude Code"
        case .api: return "API"
        }
    }

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

    /// Accès retenu selon le réglage et ce qui est disponible.
    static func resolve() -> Backend? {
        let cli = claudePath()
        let key = Keychain.apiKey()
        switch Settings.provider {
        case "cli": return cli.map { .cli(path: $0) }
        case "api": return key.map { .api(key: $0) }
        default:
            if let cli { return .cli(path: cli) }
            if let key { return .api(key: key) }
            return nil
        }
    }

    static var missingMessage: String {
        switch Settings.provider {
        case "cli": return L.t("Claude Code est introuvable. Installe-le (claude.com/claude-code) ou choisis la clé API dans les réglages.",
                               "Claude Code was not found. Install it (claude.com/claude-code) or switch to an API key in Settings.")
        case "api": return L.t("Aucune clé API. Ajoute ta clé Anthropic dans les réglages de Plume.",
                               "No API key. Add your Anthropic API key in Plume's Settings.")
        default: return L.t("Plume a besoin de Claude Code ou d'une clé API Anthropic : configure l'un des deux dans les réglages.",
                            "Plume needs Claude Code or an Anthropic API key: set one up in Settings.")
        }
    }
}

@MainActor
final class ClaudeClient {
    private var process: Process?
    private var task: URLSessionDataTask?
    private var generation = 0

    func cancel() {
        generation += 1
        if let p = process, p.isRunning { p.terminate() }
        process = nil
        task?.cancel()
        task = nil
    }

    func run(prompt: String, completion: @escaping @MainActor (Result<String, Error>) -> Void) {
        cancel()
        let gen = generation
        let done: @MainActor (Result<String, Error>) -> Void = { [weak self] r in
            guard let self, self.generation == gen else { return }
            self.process = nil
            self.task = nil
            completion(r)
        }
        switch Backend.resolve() {
        case .cli(let path)?: runCLI(path: path, prompt: prompt, done: done)
        case .api(let key)?: runAPI(key: key, prompt: prompt, done: done)
        case nil: done(.failure(plumeError(Backend.missingMessage)))
        }
    }

    // MARK: CLI Claude Code (abonnement, sans clé)

    private func runCLI(path: String, prompt: String, done: @escaping @MainActor (Result<String, Error>) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = [
            "-p",
            "--model", Models.current.id,
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
        do { try p.run() } catch { done(.failure(error)); return }
        process = p
        input.fileHandleForWriting.write(prompt.data(using: .utf8) ?? Data())
        try? input.fileHandleForWriting.close()

        DispatchQueue.global(qos: .userInitiated).async {
            let out = output.fileHandleForReading.readDataToEndOfFile()
            let err = errors.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let stdout = String(data: out, encoding: .utf8) ?? ""
            let stderr = String(data: err, encoding: .utf8) ?? ""
            let status = p.terminationStatus
            let killed = p.terminationReason == .uncaughtSignal
            Task { @MainActor in
                if killed { return }
                if status == 0, !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    done(.success(stdout))
                } else {
                    let msg = [stderr, stdout].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first { !$0.isEmpty } ?? "Erreur inconnue (code \(status))."
                    done(.failure(plumeError(msg)))
                }
            }
        }
    }

    // MARK: API Messages (clé API)

    private func runAPI(key: String, prompt: String, done: @escaping @MainActor (Result<String, Error>) -> Void) {
        let model = Models.current
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model.apiID,
            "max_tokens": 16000,
            "system": Prompts.system,
            "messages": [["role": "user", "content": prompt]],
            // Tâches d'écriture courtes : effort bas pour répondre vite.
            "output_config": ["effort": "low"],
        ]
        if model.id != "haiku" {
            // En cas de refus du modèle, l'API relance la requête sur un modèle de repli.
            body["fallbacks"] = "default"
            req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let t = URLSession.shared.dataTask(with: req) { data, response, error in
            var result: Result<String, Error>
            if let error {
                result = .failure(error)
            } else if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let err = json["error"] as? [String: Any] {
                    let msg = err["message"] as? String ?? "API error"
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    result = .failure(plumeError("API (\(status)) : \(msg)"))
                } else if json["stop_reason"] as? String == "refusal" {
                    result = .failure(plumeError(L.t("Claude a refusé de traiter ce texte.", "Claude declined to process this text.")))
                } else {
                    let blocks = json["content"] as? [[String: Any]] ?? []
                    let text = blocks.filter { $0["type"] as? String == "text" }
                        .compactMap { $0["text"] as? String }.joined()
                    result = text.isEmpty ? .failure(plumeError(L.t("Réponse vide.", "Empty response."))) : .success(text)
                }
            } else {
                result = .failure(plumeError(L.t("Réponse illisible de l'API.", "Unreadable API response.")))
            }
            let r = result
            Task { @MainActor in done(r) }
        }
        task = t
        t.resume()
    }
}
