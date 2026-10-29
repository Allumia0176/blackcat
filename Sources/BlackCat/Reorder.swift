import SwiftUI
import UniformTypeIdentifiers

// Glisser-déposer pour réordonner, sans aucun repère à l'écran : pendant le glisser,
// l'élément prend sa nouvelle place en direct et les autres se décalent.
extension UTType {
    // Types propres à l'app : un texte glissé depuis une autre app ne déplace rien.
    static let blackcatTask = UTType(exportedAs: "ai.veronese.blackcat.task")
    static let blackcatProject = UTType(exportedAs: "ai.veronese.blackcat.project")
}

struct ReorderDrop: DropDelegate {
    let target: UUID
    @Binding var dragging: UUID?
    let place: (UUID) -> Void

    // Dès que l'élément glissé passe sur un autre, il prend sa place.
    func dropEntered(info: DropInfo) {
        guard let dragged = dragging, dragged != target else { return }
        place(dragged)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    // L'ordre est déjà le bon : il n'y a plus qu'à finir le glisser.
    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

extension View {
    // Rend une ligne déplaçable : `id` est l'élément, `type` évite les mélanges tâches / projets.
    // `start` est appelé au début du geste (un seul « annuler » pour tout le glisser).
    func reorderable(id: UUID, type: UTType, dragging: Binding<UUID?>, start: @escaping () -> Void = {},
                     place: @escaping (UUID) -> Void) -> some View {
        onDrag {
            dragging.wrappedValue = id
            start()
            return NSItemProvider(item: id.uuidString as NSString, typeIdentifier: type.identifier)
        } preview: {
            // Aperçu invisible : c'est la ligne elle-même qui bouge dans la liste,
            // pas besoin d'une étiquette qui suit la souris.
            Color.clear.frame(width: 1, height: 1)
        }
        .onDrop(of: [type], delegate: ReorderDrop(target: id, dragging: dragging, place: place))
    }
}
