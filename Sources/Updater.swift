import Cocoa
import SwiftUI
import ApplicationServices

import Security

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
        alert.messageText = L.t("Déplacer Plume dans le dossier Applications ?", "Move Plume to the Applications folder?")
        alert.informativeText = L.t("Plume fonctionne mieux depuis le dossier Applications : lancement à l'ouverture de session et autorisation d'accessibilité conservée.", "Plume works best from the Applications folder: launch at login and Accessibility permission are kept.")
        alert.addButton(withTitle: L.t("Déplacer dans Applications", "Move to Applications"))
        alert.addButton(withTitle: L.t("Pas maintenant", "Not now"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = L.t("Ne plus demander", "Don't ask again")
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
            fail.messageText = L.t("Impossible de déplacer Plume", "Could not move Plume")
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
            if interactive { info(L.t("Impossible de vérifier les mises à jour", "Could not check for updates"), error ?? L.t("Aucune release avec un DMG trouvée.", "No release with a DMG found.")) }
            return
        }
        guard Self.isNewer(release.version, than: currentVersion) else {
            available = nil; onChange()
            if interactive { info(L.t("Plume est à jour", "Plume is up to date"), L.t("Version \(currentVersion), la plus récente.", "Version \(currentVersion) is the latest.")) }
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
        alert.messageText = L.t("Plume \(release.version) est disponible", "Plume \(release.version) is available")
        let notes = release.notes.count > 600 ? String(release.notes.prefix(600)) + "…" : release.notes
        alert.informativeText = L.t("Version installée : \(currentVersion).", "Installed version: \(currentVersion).") + "\n\n\(notes)"
        alert.addButton(withTitle: L.t("Installer et relancer", "Install and Relaunch"))
        alert.addButton(withTitle: L.t("Plus tard", "Later"))
        alert.addButton(withTitle: L.t("Ignorer cette version", "Skip This Version"))
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
                result = .failure(error ?? plumeError(L.t("Téléchargement impossible.", "Download failed.")))
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
            info(L.t("Échec de la mise à jour", "Update failed"), error.localizedDescription)
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
            throw plumeError(L.t("Impossible d'ouvrir l'image disque téléchargée.", "Could not open the downloaded disk image."))
        }
        defer { Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }
        let source = mount.appendingPathComponent("Plume.app")
        let target = stage.appendingPathComponent("Plume.app")
        guard Self.run("/usr/bin/ditto", [source.path, target.path]) == 0 else {
            throw plumeError(L.t("Plume.app introuvable dans l'image disque.", "Plume.app not found in the disk image."))
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
            throw plumeError(L.t("Vérification de signature impossible.", "Could not verify the signature."))
        }
        let status = SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), requirement)
        guard status == errSecSuccess else {
            throw plumeError(L.t("La mise à jour n'est pas signée par le même certificat que Plume (code \(status)). Installation annulée.", "The update is not signed with the same certificate as Plume (code \(status)). Installation cancelled."))
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

