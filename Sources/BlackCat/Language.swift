import Foundation
import Observation

// Langue de l'app : anglais par défaut, français en option dans les Réglages.
@Observable
final class Language: @unchecked Sendable {
    static let shared = Language()

    var french: Bool {
        didSet {
            UserDefaults.standard.set(french ? "fr" : "en", forKey: "language")
            onChange?()
        }
    }

    // Pour ce qui n'est pas en SwiftUI (le menu clavier de l'app).
    @ObservationIgnored var onChange: (() -> Void)?

    private init() {
        french = UserDefaults.standard.string(forKey: "language") == "fr"
    }
}

// Le texte dans la langue choisie. Lu dans une vue SwiftUI, il la redessine quand la langue change.
func L(_ english: String, _ french: String) -> String {
    Language.shared.french ? french : english
}
