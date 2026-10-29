import AppKit
import SwiftUI

// La page d'un projet : ajout, tâches à faire, terminées repliées en bas.
// Au clavier : ↓ depuis le champ pour descendre dans la liste, ↑ ↓ pour se
// déplacer, ⌥↑ ⌥↓ pour déplacer la tâche, Espace pour cocher, Entrée pour modifier,
// ⌫ pour supprimer. Souris : double-clic pour modifier, glisser pour déplacer,
// corbeille au survol. Échap ferme la fenêtre (MainWindow).
struct TasksView: View {
    @Bindable var store: TaskStore
    @State private var draft = ""
    @State private var leaving: Set<UUID> = []
    @State private var showDone = false
    @State private var cursor: UUID?
    @State private var editing: UUID?
    @State private var editText = ""
    @State private var monitor: Any?
    @FocusState private var addFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let project = store.selected {
            list(project)
                .onAppear(perform: startKeys)
                .onDisappear(perform: stopKeys)
                .onChange(of: store.selectedID) {
                    leaving = []
                    cursor = nil
                    showDone = false
                    expanded = nil
                }
        } else {
            Text(L("No projects", "Aucun projet"))
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(EdgeInsets(top: 44, leading: 48, bottom: 24, trailing: 48))
        }
    }

    // Tâche en cours de glisser-déposer (voir Reorder.swift).
    @State private var dragging: UUID?
    // Tâche dépliée (sa description est visible) ; une seule à la fois. Un clic en dehors la replie.
    @State private var expanded: UUID?
    @State private var expandedFrame: CGRect?
    @State private var clickMonitor: Any?

    private func list(_ project: Project) -> some View {
        let open = openTasks(project)
        let done = doneTasks(project)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(project.name)
                    .font(.system(size: 24, weight: .semibold))
                    .padding(.bottom, 12)
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28)
                    TextField(L("New task", "Nouvelle tâche"), text: $draft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .focused($addFocused)
                        .onSubmit(add)
                }
                .frame(height: 40)
                .contentShape(Rectangle())
                .onTapGesture { addFocused = true }  // un clic n'importe où sur la ligne ouvre la saisie
                ForEach(open) { task in
                    row(task)
                }
                Spacer().frame(height: 16)
                if project.tasks.isEmpty {
                    Text(L("No tasks", "Aucune tâche"))
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.muted)
                        .padding(.leading, 36)
                }
                if !done.isEmpty {
                    FoldButton(count: done.count, open: showDone) { showDone.toggle() }
                    if showDone {
                        ForEach(done) { task in
                            row(task)
                        }
                    }
                }
            }
            .padding(EdgeInsets(top: 44, leading: 48, bottom: 24, trailing: 48))
        }
        .scrollContentBackground(.hidden)
        .onPreferenceChange(ExpandedFrameKey.self) { expandedFrame = $0 }
    }

    // Une tâche se glisse par n'importe quel endroit de sa ligne et prend sa nouvelle place
    // en direct, sans repère. Corbeille au survol pour la supprimer.
    private func row(_ task: TaskItem) -> some View {
        TaskRow(
            task: task,
            editText: editing == task.id ? $editText : nil,
            onEdit: { startEdit(task) },
            onCommit: commitEdit,
            onCancel: { editing = nil },
            onDelete: { delete(task) },
            expanded: expanded == task.id,
            onToggleExpand: {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    expanded = expanded == task.id ? nil : task.id
                }
            },
            onSaveNotes: { store.setNotes(task.id, to: $0) }
        ) { toggle(task) }
        .background {
            // Place de la tâche dépliée dans la fenêtre, pour savoir si un clic tombe en dehors.
            if expanded == task.id {
                GeometryReader { proxy in
                    Color.clear.preference(key: ExpandedFrameKey.self, value: proxy.frame(in: .global))
                }
            }
        }
        .reorderable(id: task.id, type: .blackcatTask, dragging: $dragging, start: store.beginMove) { dragged in
            guard leaving.isEmpty else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                _ = store.placeTask(dragged, at: task.id)
            }
        }
        .contextMenu {
            Button(L("Edit task", "Modifier la tâche")) { startEdit(task) }
            Button(L("Delete task", "Supprimer la tâche"), role: .destructive) { delete(task) }
        }
    }

    private func delete(_ task: TaskItem) {
        if cursor == task.id { cursor = nil }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            store.deleteTask(task.id)
        }
    }

    private func startEdit(_ task: TaskItem) {
        editText = task.text
        cursor = nil
        editing = task.id
    }

    // Un texte vidé ne supprime pas la tâche : on garde l'ancien.
    private func commitEdit() {
        guard let id = editing else { return }
        let text = editText.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { store.renameTask(id, to: text) }
        editing = nil
    }

    // Une tâche cochée reste barrée un instant à sa place avant de rejoindre les terminées.
    private func openTasks(_ project: Project) -> [TaskItem] {
        project.tasks.filter { !$0.done || leaving.contains($0.id) }
    }

    private func doneTasks(_ project: Project) -> [TaskItem] {
        project.tasks.filter { $0.done && !leaving.contains($0.id) }
    }

    private func visible() -> [TaskItem] {
        guard let project = store.selected else { return [] }
        return openTasks(project) + (showDone ? doneTasks(project) : [])
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        store.addTask(text)
        draft = ""
    }

    private func toggle(_ task: TaskItem) {
        let becomesDone = !task.done
        store.toggle(task.id)
        guard becomesDone else { return }
        leaving.insert(task.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                _ = leaving.remove(task.id)
            }
        }
    }

    private func startKeys() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event) ? nil : event
        }
        // Clic en dehors de la tâche dépliée : elle se replie (un clic sur une autre tâche
        // replie la première, puis déplie la nouvelle).
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if expanded != nil, let frame = expandedFrame, let content = event.window?.contentView {
                let p = event.locationInWindow
                if !frame.contains(CGPoint(x: p.x, y: content.bounds.height - p.y)) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { expanded = nil }
                }
            }
            return event
        }
    }

    private func stopKeys() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.window?.isKeyWindow == true else { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let items = visible()
        // ⌥↑ / ⌥↓ : déplacer la tâche sous le curseur.
        if mods == .option, !addFocused, !(event.window?.firstResponder is NSTextView),
           [125, 126].contains(event.keyCode), let id = cursor, let task = items.first(where: { $0.id == id }) {
            let group = items.filter { $0.done == task.done }
            guard let i = group.firstIndex(where: { $0.id == id }) else { return true }
            if event.keyCode == 126, i > 0 {
                store.moveTask(id, before: group[i - 1].id)
            } else if event.keyCode == 125, i < group.count - 1 {
                store.moveTask(id, before: i + 2 < group.count ? group[i + 2].id : nil)
            }
            return true
        }
        guard mods.intersection([.command, .control, .option]).isEmpty else { return false }
        if addFocused {
            guard event.keyCode == 125, let first = items.first else { return false }  // ↓
            addFocused = false
            cursor = first.id
            return true
        }
        // Une autre saisie en cours (nom de projet, clé API) garde ses touches.
        if event.window?.firstResponder is NSTextView { return false }
        let index = cursor.flatMap { id in items.firstIndex { $0.id == id } }
        switch event.keyCode {
        case 125:  // ↓
            guard !items.isEmpty else { return false }
            cursor = items[min((index ?? -1) + 1, items.count - 1)].id
        case 126:  // ↑
            guard let index else { return false }
            if index == 0 {
                cursor = nil
                addFocused = true
            } else {
                cursor = items[index - 1].id
            }
        case 49:  // Espace
            guard let index else { return false }
            toggle(items[index])
        case 36:  // Entrée : modifier la tâche sous le curseur
            guard let index else { return false }
            startEdit(items[index])
        case 51, 117:  // ⌫ et suppr
            guard let index else { return false }
            delete(items[index])
            let rest = items.filter { $0.id != items[index].id }
            cursor = rest.isEmpty ? nil : rest[min(index, rest.count - 1)].id
        default:
            return false
        }
        return true
    }
}

// Une modification en cours (tâche ou projet) : Échap l'annule au lieu de fermer la fenêtre.
@MainActor
enum InlineEdit {
    static var active = false
}

// Champ de modification en place. Entrée valide, Échap annule, un clic ailleurs valide.
struct InlineEditor: View {
    @Binding var text: String
    var size: CGFloat = 14
    let commit: () -> Void
    let cancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: size))
            .focused($focused)
            .onSubmit(commit)
            .onExitCommand(perform: cancel)
            .onChange(of: focused) { if !focused { commit() } }
            .onAppear {
                InlineEdit.active = true
                DispatchQueue.main.async { focused = true }
            }
            .onDisappear { InlineEdit.active = false }
    }
}

struct TaskRow: View {
    let task: TaskItem
    var compact = false
    var editText: Binding<String>? = nil
    var onEdit: (() -> Void)? = nil
    var onCommit: () -> Void = {}
    var onCancel: () -> Void = {}
    var onDelete: (() -> Void)? = nil
    var expanded = false
    var onToggleExpand: (() -> Void)? = nil
    var onSaveNotes: ((String) -> Void)? = nil
    let toggle: () -> Void
    @State private var hover = false
    @State private var trashHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                // Zone de clic large : toute la hauteur de la ligne, et quelques points
                // autour du rond, pour qu'un clic « juste à côté » coche quand même.
                Button(action: toggle) {
                    Ring(done: task.done, size: compact ? 15 : 18)
                        .frame(width: compact ? 26 : 28, height: compact ? 28 : 40)
                        .padding(.leading, compact ? 0 : 8)
                        .padding(.trailing, compact ? 4 : 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, compact ? 0 : -8)
                .accessibilityLabel(task.done ? L("Uncheck", "Décocher") : L("Check", "Cocher"))
                if let editText {
                    InlineEditor(text: editText, size: compact ? 13 : 14, commit: onCommit, cancel: onCancel)
                } else {
                    HStack(spacing: 6) {
                        LinkText(text: task.text, size: compact ? 13 : 14)
                            .lineLimit(compact ? 1 : nil)
                            .strikethrough(task.done, color: Theme.muted)
                            .foregroundStyle(task.done ? Theme.muted : Theme.ink)
                            .animation(.easeOut(duration: 0.16), value: task.done)
                        // Petit signe : cette tâche a une description, cachée tant qu'elle est repliée.
                        if !expanded && !task.notes.isEmpty {
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.muted)
                                .accessibilityLabel(L("Has a description", "A une description"))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: compact ? 28 : 40, alignment: .leading)
                    .contentShape(Rectangle())
                    // Un clic : déplier ou replier la description. Double-clic : modifier le titre.
                    .gesture(TapGesture(count: 2).onEnded { onEdit?() }
                        .exclusively(before: TapGesture().onEnded { onToggleExpand?() }))
                }
                if let onDelete, hover, editText == nil {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(trashHover ? Theme.danger : Theme.muted)
                            .frame(width: 32, height: compact ? 28 : 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { trashHover = $0 }
                    .accessibilityLabel(L("Delete task", "Supprimer la tâche"))
                }
            }
            .frame(minHeight: compact ? 28 : 40)
            if expanded, let onSaveNotes {
                NotesEditor(initial: task.notes, save: onSaveNotes)
                    .padding(.leading, 36)
                    .padding(.trailing, 32)
                    .padding(.bottom, 10)
            }
        }
        // Pas de cadre : ni au survol, ni sous la tâche choisie. La corbeille devient juste rouge.
        .onHover { hover = $0 }
    }
}

// La description d'une tâche dépliée. Vide : un champ « Ajouter une description ».
// Remplie : le texte, avec ses liens cliquables ; un clic dessus pour la modifier.
struct NotesEditor: View {
    let save: (String) -> Void
    @State private var text: String
    @State private var editing: Bool
    @FocusState private var focused: Bool

    init(initial: String, save: @escaping (String) -> Void) {
        self.save = save
        _text = State(initialValue: initial)
        _editing = State(initialValue: initial.isEmpty)
    }

    var body: some View {
        Group {
            if editing {
                TextField(L("Add a description", "Ajouter une description"), text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...20)
                    .focused($focused)
                    .onExitCommand { focused = false }
                    .onChange(of: focused) {
                        InlineEdit.active = focused  // Échap quitte la description, pas la fenêtre
                        if !focused { finish() }
                    }
            } else {
                LinkText(text: text, size: 13)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editing = true
                        DispatchQueue.main.async { focused = true }
                    }
            }
        }
        .onDisappear {
            InlineEdit.active = false
            save(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func finish() {
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        save(text)
        editing = text.isEmpty
    }
}

// Un texte dont les adresses web deviennent des liens cliquables (ouverts dans le navigateur).
struct LinkText: View {
    let text: String
    var size: CGFloat = 14

    var body: some View {
        Text(Self.linked(text))
            .font(.system(size: size))
            .tint(Theme.accent)
    }

    static func linked(_ string: String) -> AttributedString {
        var result = AttributedString(string)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        for match in detector.matches(in: string, range: NSRange(string.startIndex..., in: string)) {
            guard let url = match.url, let range = Range(match.range, in: string),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
        }
        return result
    }
}

struct Ring: View {
    let done: Bool
    var size: CGFloat = 18

    var body: some View {
        ZStack {
            Circle().fill(done ? Theme.accent : .clear)
            Circle().strokeBorder(done ? Theme.accent : Theme.control, lineWidth: 1.5)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .opacity(done ? 1 : 0)
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.16), value: done)
    }
}

struct FoldButton: View {
    let count: Int
    let open: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .animation(.easeOut(duration: 0.16), value: open)
                Text(L("Completed", "Terminées"))
                Text("\(count)").font(.system(size: 12)).monospacedDigit()
            }
            .font(.system(size: 13))
            .foregroundStyle(hover ? Theme.ink : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// Une tâche dans le menu du chat : on peut la cocher sans ouvrir la fenêtre.
struct MenuTaskRow: View {
    let store: TaskStore
    let projectID: UUID
    let taskID: UUID

    var body: some View {
        // Dans le menu, toute la ligne coche la tâche.
        if let task = store.projects.first(where: { $0.id == projectID })?.tasks.first(where: { $0.id == taskID }) {
            Button {
                store.toggle(taskID, in: projectID)
            } label: {
                HStack(spacing: 4) {
                    Ring(done: task.done, size: 15)
                        .frame(width: 26, height: 28)
                    Text(task.text)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .strikethrough(task.done, color: Theme.muted)
                        .foregroundStyle(task.done ? Theme.muted : Theme.ink)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(width: 280, height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.done ? L("Uncheck \(task.text)", "Décocher \(task.text)") : L("Check \(task.text)", "Cocher \(task.text)"))
        }
    }
}

// Transmet la place de la tâche dépliée (une seule à la fois).
struct ExpandedFrameKey: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}
