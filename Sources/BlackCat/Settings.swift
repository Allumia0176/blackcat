import AppKit
import Observation
import ServiceManagement

// Les réglages de la page Réglages, gardés d'un lancement à l'autre.
@MainActor
@Observable
final class Settings {
    enum Appearance: String, CaseIterable { case auto, light, dark }

    var appearance: Appearance {
        didSet { save(appearance.rawValue, "appearance"); applyAppearance() }
    }
    var correctShortcut: Shortcut? {
        didSet { save(correctShortcut, "correctShortcut"); onShortcutsChange?() }
    }
    var openShortcut: Shortcut? {
        didSet { save(openShortcut, "openShortcut"); onShortcutsChange?() }
    }
    // Ferme la fenêtre des tâches (l'app reste en fond). Échap par défaut.
    var closeShortcut: Shortcut? {
        didSet { save(closeShortcut, "closeShortcut") }
    }
    var apiKey: String {
        didSet { Keychain.save(apiKey) }
    }
    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // Disparition des explications d'une correction (soulignés et bulle).
    var explainSeconds: Int {  // 0 = jamais
        didSet { defaults.set(explainSeconds, forKey: "explainSeconds") }
    }
    var hideOnClick: Bool {
        didSet { defaults.set(hideOnClick, forKey: "hideOnClick") }
    }
    var hideOnTyping: Bool {
        didSet { defaults.set(hideOnTyping, forKey: "hideOnTyping") }
    }

    // Liste de tâches du menu du chat : projet affiché (nil = le projet en cours) et nombre de tâches (0 = aucune liste).
    var menuProjectID: UUID? {
        didSet { defaults.set(menuProjectID?.uuidString, forKey: "menuProjectID") }
    }
    var menuTaskCount: Int {
        didSet { defaults.set(menuTaskCount, forKey: "menuTaskCount") }
    }

    var onShortcutsChange: (() -> Void)?

    private let defaults = UserDefaults.standard

    init() {
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .auto
        correctShortcut = Self.load("correctShortcut", fallback: .correctDefault)
        openShortcut = Self.load("openShortcut", fallback: .openDefault)
        closeShortcut = Self.load("closeShortcut", fallback: .closeDefault)
        apiKey = Keychain.read()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        explainSeconds = defaults.object(forKey: "explainSeconds") as? Int ?? 60
        hideOnClick = defaults.object(forKey: "hideOnClick") as? Bool ?? true
        hideOnTyping = defaults.object(forKey: "hideOnTyping") as? Bool ?? true
        menuProjectID = defaults.string(forKey: "menuProjectID").flatMap(UUID.init(uuidString:))
        menuTaskCount = defaults.object(forKey: "menuTaskCount") as? Int ?? 5
        applyAppearance()
    }

    var dismissRules: CorrectionOverlay.Rules {
        CorrectionOverlay.Rules(seconds: explainSeconds > 0 ? TimeInterval(explainSeconds) : nil,
                                onClick: hideOnClick, onTyping: hideOnTyping)
    }

    func applyAppearance() {
        switch appearance {
        case .auto: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    // Un raccourci retiré par l'utilisateur est gardé comme « aucun », pas remplacé par celui par défaut.
    private static func load(_ key: String, fallback: Shortcut) -> Shortcut? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return fallback }
        return try? JSONDecoder().decode(Shortcut?.self, from: data) ?? nil
    }

    private func save(_ value: Shortcut?, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private func save(_ value: String, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
