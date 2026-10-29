import Foundation
import Observation
import SwiftUI  // move(fromOffsets:toOffset:)

struct TaskItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var done = false
    var notes = ""  // la description, visible quand on déplie la tâche

    init(text: String) {
        self.text = text
    }

    // Les tâches enregistrées avant l'ajout des descriptions n'ont pas le champ `notes`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        text = try c.decode(String.self, forKey: .text)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var tasks: [TaskItem] = []

    var open: [TaskItem] { tasks.filter { !$0.done } }
    var finished: [TaskItem] { tasks.filter(\.done) }
}

// Les projets et leurs tâches, enregistrés dans un fichier JSON sur le Mac.
// Dans chaque projet, les tâches à faire viennent avant les terminées.
@MainActor
@Observable
final class TaskStore {
    var projects: [Project] = [] {
        didSet { save() }
    }
    var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: "selectedProject") }
    }

    var selected: Project? {
        projects.first { $0.id == selectedID } ?? projects.first
    }

    private let file: URL

    // `file` sert aux essais, qui ne doivent jamais toucher le vrai fichier.
    init(file: URL? = nil) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BlackCat", isDirectory: true)
        if file == nil {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        self.file = file ?? folder.appendingPathComponent("taches.json")
        if let data = try? Data(contentsOf: self.file),
           let saved = try? JSONDecoder().decode([Project].self, from: data) {
            projects = saved
        }
        selectedID = UserDefaults.standard.string(forKey: "selectedProject").flatMap(UUID.init(uuidString:))
    }

    // ⌘Z / ⇧⌘Z : chaque modification enregistre l'état d'avant dans le gestionnaire
    // d'annulation de la fenêtre (branché par MainWindowController).
    var undoManager: UndoManager?
    private var pendingMove: (projects: [Project], selected: UUID?)?

    private func recordUndo(_ name: String, from before: (projects: [Project], selected: UUID?)? = nil) {
        guard let undoManager else { return }
        let state = before ?? (projects, selectedID)
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restore(state, name) }
        }
        undoManager.setActionName(name)
    }

    // Revenir à un état ; l'état quitté devient le « rétablir ».
    private func restore(_ state: (projects: [Project], selected: UUID?), _ name: String) {
        recordUndo(name)
        projects = state.projects
        selectedID = state.selected
    }

    // Début d'un glisser-déposer : un seul « annuler » pour tout le geste, et seulement
    // si quelque chose a vraiment bougé.
    func beginMove() {
        pendingMove = (projects, selectedID)
        moveRecorded = false
    }

    private var moveRecorded = false

    // Au premier vrai déplacement du geste, on enregistre l'état d'avant le glisser ; ensuite plus rien.
    private func recordMove() {
        guard !moveRecorded else { return }
        recordUndo(L("Move", "Déplacer"), from: pendingMove)
        pendingMove = nil
        moveRecorded = true
    }

    func addProject(_ name: String) {
        recordUndo(L("New Project", "Nouveau projet"))
        let project = Project(name: name)
        projects.append(project)
        selectedID = project.id
    }

    func deleteProject(_ id: UUID) {
        guard projects.contains(where: { $0.id == id }) else { return }
        recordUndo(L("Delete Project", "Supprimer le projet"))
        projects.removeAll { $0.id == id }
        if selectedID == id { selectedID = projects.first?.id }
    }

    func addTask(_ text: String) {
        guard let p = selectedIndex else { return }
        recordUndo(L("New Task", "Nouvelle tâche"))
        projects[p].tasks.insert(TaskItem(text: text), at: 0)
    }

    // Une tâche cochée passe en tête des terminées ; décochée, en fin des tâches à faire.
    func toggle(_ id: UUID, in projectID: UUID? = nil) {
        guard let p = index(of: projectID ?? selected?.id),
              let t = projects[p].tasks.firstIndex(where: { $0.id == id }) else { return }
        recordUndo(projects[p].tasks[t].done ? L("Uncheck", "Décocher") : L("Check", "Cocher"))
        var task = projects[p].tasks.remove(at: t)
        task.done.toggle()
        let openCount = projects[p].tasks.filter { !$0.done }.count
        projects[p].tasks.insert(task, at: openCount)
    }

    func renameTask(_ id: UUID, to text: String) {
        guard let p = selectedIndex, let t = projects[p].tasks.firstIndex(where: { $0.id == id }),
              projects[p].tasks[t].text != text else { return }
        recordUndo(L("Edit Task", "Modifier la tâche"))
        projects[p].tasks[t].text = text
    }

    func setNotes(_ id: UUID, to notes: String) {
        guard let p = selectedIndex, let t = projects[p].tasks.firstIndex(where: { $0.id == id }),
              projects[p].tasks[t].notes != notes else { return }
        recordUndo(L("Edit Description", "Modifier la description"))
        projects[p].tasks[t].notes = notes
    }

    func renameProject(_ id: UUID, to name: String) {
        guard let p = index(of: id), projects[p].name != name else { return }
        recordUndo(L("Rename Project", "Renommer le projet"))
        projects[p].name = name
    }

    func deleteTask(_ id: UUID) {
        guard let p = selectedIndex, projects[p].tasks.contains(where: { $0.id == id }) else { return }
        recordUndo(L("Delete Task", "Supprimer la tâche"))
        projects[p].tasks.removeAll { $0.id == id }
    }

    // Déplacement au clavier : la tâche se place juste avant `target` (à la fin si nil),
    // parmi les tâches du même état (à faire avec à faire, terminées avec terminées).
    @discardableResult
    func moveTask(_ id: UUID, before target: UUID?) -> Bool {
        guard let p = selectedIndex, id != target,
              let task = projects[p].tasks.first(where: { $0.id == id }) else { return false }
        var group = task.done ? projects[p].finished : projects[p].open
        if let target, !group.contains(where: { $0.id == target }) { return false }
        group.removeAll { $0.id == id }
        let index = target.flatMap { t in group.firstIndex { $0.id == t } } ?? group.count
        group.insert(task, at: index)
        let tasks = task.done ? projects[p].open + group : group + projects[p].finished
        guard tasks.map(\.id) != projects[p].tasks.map(\.id) else { return false }
        recordUndo(L("Move", "Déplacer"))
        projects[p].tasks = tasks
        return true
    }

    // Glisser-déposer en direct : la tâche prend la place de `target`, les autres se décalent.
    // Vers le bas elle passe après la cible, vers le haut avant, comme dans les apps d'Apple.
    @discardableResult
    func placeTask(_ id: UUID, at target: UUID) -> Bool {
        guard let p = selectedIndex, id != target,
              let task = projects[p].tasks.first(where: { $0.id == id }),
              let other = projects[p].tasks.first(where: { $0.id == target }),
              task.done == other.done else { return false }
        var group = task.done ? projects[p].finished : projects[p].open
        guard let slot = group.firstIndex(where: { $0.id == target }) else { return false }
        group.removeAll { $0.id == id }
        group.insert(task, at: min(slot, group.count))
        recordMove()
        projects[p].tasks = task.done ? projects[p].open + group : group + projects[p].finished
        return true
    }

    @discardableResult
    func placeProject(_ id: UUID, at target: UUID) -> Bool {
        guard id != target, let project = projects.first(where: { $0.id == id }),
              let slot = projects.firstIndex(where: { $0.id == target }) else { return false }
        var list = projects
        list.removeAll { $0.id == id }
        list.insert(project, at: min(slot, list.count))
        recordMove()
        projects = list
        return true
    }

    // Même principe pour l'ordre des projets, à une place donnée.
    @discardableResult
    func moveProject(_ id: UUID, before target: UUID?) -> Bool {
        guard id != target, let project = projects.first(where: { $0.id == id }) else { return false }
        var list = projects
        list.removeAll { $0.id == id }
        let index = target.flatMap { t in list.firstIndex { $0.id == t } } ?? list.count
        list.insert(project, at: index)
        guard list.map(\.id) != projects.map(\.id) else { return false }
        recordUndo(L("Move", "Déplacer"))
        projects = list
        return true
    }

    private var selectedIndex: Int? { index(of: selected?.id) }

    private func index(of id: UUID?) -> Int? {
        guard let id else { return nil }
        return projects.firstIndex { $0.id == id }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(projects) else { return }
        try? data.write(to: file, options: .atomic)
    }
}
