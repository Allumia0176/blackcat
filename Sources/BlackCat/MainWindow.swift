import AppKit
import Carbon.HIToolbox
import SwiftUI

// La fenêtre de l'app : les projets à gauche, la page à droite.
@MainActor
@Observable
final class WindowModel {
    enum Page { case tasks, settings }
    var page: Page = .tasks
    var pendingDelete: UUID?
}

@MainActor
final class MainWindowController {
    private let settings: Settings
    private let store: TaskStore
    private let model = WindowModel()
    private var window: NSWindow?

    init(settings: Settings, store: TaskStore) {
        self.settings = settings
        self.store = store
    }

    func show(_ page: WindowModel.Page) {
        model.page = page
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()  // devant, même si macOS n'a pas encore rendu l'app active
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 536),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "BlackCat"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false  // fermer la fenêtre laisse l'app tourner en fond
        window.contentMinSize = NSSize(width: 720, height: 460)
        Glass.makeGlassWindow(window, content: NSHostingView(rootView: RootView(model: model, settings: settings, store: store)))
        window.center()
        window.setFrameAutosaveName("BlackCat.main")
        store.undoManager = window.undoManager  // ⌘Z / ⇧⌘Z sur les tâches et les projets
        watchEscape(in: window)
        watchClicks(in: window)
        return window
    }

    // Un clic en dehors du champ en cours de saisie (nom de projet, titre, description) le termine :
    // le nom est validé s'il y en a un, sinon le champ se ferme. Sans ça, il restait ouvert.
    private var clickMonitor: Any?

    private func watchClicks(in window: NSWindow) {
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak window] event in
            let point = event.locationInWindow
            let target = event.window
            MainActor.assumeIsolated {
                guard let window, target === window, let editor = window.firstResponder as? NSTextView else { return }
                let field = (editor.isFieldEditor ? editor.delegate as? NSView : nil) ?? editor
                let rect = field.convert(field.bounds, to: nil)
                if !rect.insetBy(dx: -4, dy: -4).contains(point) { window.makeFirstResponder(nil) }
            }
            return event
        }
    }

    // Le raccourci choisi (Échap par défaut) ferme la fenêtre (l'app reste en fond), sauf pendant
    // l'enregistrement d'un raccourci ou dans la confirmation de suppression. Une autre touche seule
    // qu'Échap ne ferme pas pendant la saisie d'un texte, pour qu'on puisse l'écrire.
    private var escapeMonitor: Any?

    private func watchEscape(in window: NSWindow) {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self, weak window] event in
            let target = event.window
            let closed = MainActor.assumeIsolated { () -> Bool in
                guard let self, let window, target === window,
                      let shortcut = self.settings.closeShortcut, shortcut.matches(event) else { return false }
                let typing = window.firstResponder is NSTextView
                if shortcut.modifiers == 0 && shortcut.keyCode != UInt32(kVK_Escape) && typing { return false }
                guard !InlineEdit.active, !HotKeys.isRecording, !GlassMenu.isOpen,
                      self.model.pendingDelete == nil else { return false }
                window.performClose(nil)
                return true
            }
            return closed ? nil : event
        }
    }
}

struct RootView: View {
    @Bindable var model: WindowModel
    let settings: Settings
    @Bindable var store: TaskStore

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, store: store)
                .frame(width: 230)
            Rectangle().fill(Theme.line).frame(width: 1)
            Group {
                switch model.page {
                case .settings:
                    ScrollView {
                        SettingsView(settings: settings, store: store)
                            .padding(EdgeInsets(top: 44, leading: 48, bottom: 24, trailing: 48))
                    }
                case .tasks:
                    TasksView(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(Theme.ink)  // pas de fond : c'est le verre de la fenêtre
        .overlay {
            if let id = model.pendingDelete, let project = store.projects.first(where: { $0.id == id }) {
                DeleteDialog(project: project) {
                    model.pendingDelete = nil
                } confirm: {
                    store.deleteProject(id)
                    model.pendingDelete = nil
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct Sidebar: View {
    @Bindable var model: WindowModel
    @Bindable var store: TaskStore
    @State private var creating = false
    @State private var newName = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var newHover = false
    @State private var gearHover = false
    @FocusState private var newFocused: Bool
    @State private var listMouse: CGPoint?  // souris sur la liste des projets

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BlackCat")
                .font(.system(size: 13, weight: .semibold))
                .padding(EdgeInsets(top: 50, leading: 10, bottom: 18, trailing: 10))
            ScrollView {
                // Une seule vitre pour la liste (maquette Vitre-1, validée le 27/10/2026) : posée sur
                // le projet ouvert, elle glisse vers le projet survolé et revient quand la souris s'en va.
                // Sur la page Réglages, aucun projet n'est ouvert : elle n'apparaît qu'au survol.
                ZStack(alignment: .topLeading) {
                let selectedIndex = model.page == .tasks ? store.projects.firstIndex(where: { $0.id == store.selected?.id }) : nil
                let hoveredIndex = listMouse.flatMap { point -> Int? in
                    let index = Int(point.y / 34)
                    return point.y >= 0 && index < store.projects.count ? index : nil
                }
                if let index = hoveredIndex ?? selectedIndex {
                    SelectionCapsule(
                        trigger: selectedIndex ?? -1,
                        glow: hoveredIndex == nil ? nil : listMouse.map { CGPoint(x: $0.x, y: $0.y - CGFloat(index) * 34) }
                    )
                        .frame(height: 32)
                        .offset(y: CGFloat(index) * 34)
                        .animation(reduceMotion ? nil : Vitre.spring, value: index)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
                VStack(spacing: 2) {
                    ForEach(store.projects) { project in
                        if renaming == project.id {
                            InlineEditor(text: $renameText, commit: commitRename, cancel: { renaming = nil })
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .background(Theme.active, in: Capsule())
                        } else {
                            ProjectRow(
                                name: project.name,
                                count: project.open.count,
                                selected: model.page == .tasks && store.selected?.id == project.id
                            ) {
                                withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.62)) {
                                    store.selectedID = project.id
                                    model.page = .tasks
                                }
                            } ask: {
                                model.pendingDelete = project.id
                            } rename: {
                                renameText = project.name
                                renaming = project.id
                            }
                            // Glissé, le projet prend sa nouvelle place en direct (Reorder.swift).
                            .reorderable(id: project.id, type: .blackcatProject, dragging: $dragging, start: store.beginMove) { dragged in
                                withAnimation(.easeOut(duration: 0.16)) {
                                    _ = store.placeProject(dragged, at: project.id)
                                }
                            }
                        }
                    }
                    if creating {
                        TextField(L("Project name", "Nom du projet"), text: $newName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .focused($newFocused)
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .background(Theme.active, in: Capsule())
                            .onSubmit(commit)
                            .onExitCommand { creating = false }
                            .onChange(of: newFocused) { if !newFocused { commit() } }
                    }
                }
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): listMouse = point
                    case .ended: listMouse = nil
                    }
                }
                }
                .animation(.easeOut(duration: 0.18), value: listMouse == nil)
                // Marge intérieure pour que la capsule, quand elle s'étire et avec son ombre,
                // ne soit pas rognée par les bords de la liste…
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            // … compensée ici : les projets restent exactement à la même place à l'écran.
            .padding(.horizontal, -10)
            .padding(.vertical, -8)
            .scrollIndicators(.never)
            HStack(spacing: 4) {
                Button {
                    newName = ""
                    creating = true
                    DispatchQueue.main.async { newFocused = true }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus").font(.system(size: 12))
                        Text(L("New project", "Nouveau projet")).font(.system(size: 14))
                    }
                    .foregroundStyle(newHover ? Theme.ink : Theme.muted)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    .hoverGlass(Capsule())
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { newHover = $0 }
                Button {
                    model.page = model.page == .settings ? .tasks : .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(model.page == .settings || gearHover ? Theme.ink : Theme.muted)
                        .frame(width: 32, height: 32)
                        .hoverGlass(Circle(), on: model.page == .settings)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { gearHover = $0 }
                .accessibilityLabel(L("Settings", "Réglages"))
            }
            .padding(.top, 8)
        }
        .padding(EdgeInsets(top: 0, leading: 10, bottom: 10, trailing: 10))
        .frame(maxHeight: .infinity)
    }

    private func commit() {
        guard creating else { return }
        creating = false
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.addProject(name)
        model.page = .tasks
    }

    // Projet en cours de glisser-déposer.
    @State private var dragging: UUID?

    // Un nom vidé garde l'ancien.
    private func commitRename() {
        guard let id = renaming else { return }
        let name = renameText.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { store.renameProject(id, to: name) }
        renaming = nil
    }
}

// La vitre de la liste des projets (Vitre.swift), avec le reflet qui suit la souris ;
// elle s'étire un instant à chaque changement de projet ouvert.
struct SelectionCapsule: View {
    let trigger: Int
    var glow: CGPoint? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = reduceMotion
        GlassPane(shape: Capsule(), level: .vitre, glow: glow)
            .keyframeAnimator(initialValue: CGSize(width: 1, height: 1), trigger: trigger) { content, scale in
                content.scaleEffect(x: still ? 1 : scale.width, y: still ? 1 : scale.height)
            } keyframes: { _ in
                KeyframeTrack(\.height) {
                    CubicKeyframe(1.22, duration: 0.14)
                    CubicKeyframe(0.92, duration: 0.16)
                    CubicKeyframe(1, duration: 0.25)
                }
                KeyframeTrack(\.width) {
                    CubicKeyframe(0.96, duration: 0.14)
                    CubicKeyframe(1.03, duration: 0.16)
                    CubicKeyframe(1, duration: 0.25)
                }
            }
    }
}

// Au survol, la corbeille remplace le nombre de tâches à faire. Double-clic : renommer.
struct ProjectRow: View {
    let name: String
    let count: Int
    let selected: Bool
    let pick: () -> Void
    let ask: () -> Void
    let rename: () -> Void
    @State private var hover = false
    @State private var trashHover = false

    var body: some View {
        HStack(spacing: 0) {
            // Un geste plutôt qu'un bouton : un bouton garderait le clic et empêcherait
            // de glisser le projet pour le déplacer.
            HStack {
                Text(name).font(.system(size: 14, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 8)
                if !hover && count > 0 {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .contentShape(Rectangle())
            .onTapGesture(perform: pick)
            .simultaneousGesture(TapGesture(count: 2).onEnded(rename))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { pick() }
            .contextMenu {
                Button(L("Rename project", "Renommer le projet"), action: rename)
                Button(L("Delete project", "Supprimer le projet"), role: .destructive, action: ask)
            }
            if hover {
                Button(action: ask) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(trashHover ? Theme.danger : Theme.muted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { trashHover = $0 }
                .padding(.trailing, 2)
                .accessibilityLabel(L("Delete project", "Supprimer le projet"))
            }
        }
        // Plus de fond gris : le projet ouvert est posé sur la capsule de verre (Sidebar).
        .padding(.horizontal, 2)
        .onHover { hover = $0 }
    }
}

struct DeleteDialog: View {
    let project: Project
    let cancel: () -> Void
    let confirm: () -> Void

    var body: some View {
        let lost = project.open.count
        ZStack {
            Color.black.opacity(0.25)
                .onTapGesture(perform: cancel)
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Delete “\(project.name)”?", "Supprimer « \(project.name) » ?"))
                    .font(.system(size: 14, weight: .semibold))
                if lost > 0 {
                    Text(lost == 1 ? L("1 open task will be deleted.", "1 tâche à faire sera supprimée.") : L("\(lost) open tasks will be deleted.", "\(lost) tâches à faire seront supprimées."))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                HStack(spacing: 8) {
                    Spacer()
                    Button(action: cancel) {
                        Text(L("Cancel", "Annuler"))
                            .font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .background(Theme.track, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
                    Button(action: confirm) {
                        Text(L("Delete", "Supprimer"))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .background(Theme.danger, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 14)
            }
            .padding(20)
            .frame(width: 300)
            .background(Theme.window, in: RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.25), radius: 25, y: 18)
        }
    }
}
