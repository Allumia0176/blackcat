import Foundation

// L'app s'appelait HappytoHelp jusqu'au 27/10/2026. Au premier lancement de BlackCat,
// on recopie ses réglages, ses tâches et sa clé API. On copie sans rien effacer :
// les anciennes données restent en place, en secours.
enum Migration {
    static let oldID = "ai.veronese.happytohelp"
    private static let doneKey = "migratedFromHappytoHelp"

    @MainActor
    static func fromHappytoHelp() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        run(oldDefaults: defaults.persistentDomain(forName: oldID),
            into: defaults,
            oldFolder: support.appendingPathComponent("HappytoHelp", isDirectory: true),
            newFolder: support.appendingPathComponent("BlackCat", isDirectory: true))
        if Keychain.read().isEmpty {
            let oldKey = Keychain.read(service: oldID)
            if !oldKey.isEmpty { Keychain.save(oldKey) }
        }
        defaults.set(true, forKey: doneKey)
    }

    // Séparé pour les essais, qui travaillent sur des dossiers et des réglages temporaires.
    static func run(oldDefaults: [String: Any]?, into defaults: UserDefaults, oldFolder: URL, newFolder: URL) {
        for (key, value) in oldDefaults ?? [:] {
            let newKey = key == "NSWindow Frame HappytoHelp.main" ? "NSWindow Frame BlackCat.main" : key
            if defaults.object(forKey: newKey) == nil { defaults.set(value, forKey: newKey) }
        }
        let fm = FileManager.default
        let oldTasks = oldFolder.appendingPathComponent("taches.json")
        let newTasks = newFolder.appendingPathComponent("taches.json")
        if fm.fileExists(atPath: oldTasks.path), !fm.fileExists(atPath: newTasks.path) {
            try? fm.createDirectory(at: newFolder, withIntermediateDirectories: true)
            try? fm.copyItem(at: oldTasks, to: newTasks)
        }
    }
}
