import AppKit
import os
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings()
    private let store = TaskStore()
    private lazy var mainWindow = MainWindowController(settings: settings, store: store)
    private var statusItem: NSStatusItem?
    private var cat: CatIcon?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            cat = CatIcon(button: button)
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item

        settings.onShortcutsChange = { [weak self] in self?.registerHotKeys() }
        registerHotKeys()
        NSApp.mainMenu = keyboardMenu()
        Language.shared.onChange = { [weak self] in
            MainActor.assumeIsolated { NSApp.mainMenu = self?.keyboardMenu() }
        }

        if !AXIsProcessTrusted() { firstLaunch.show() }
    }

    // L'app n'affiche pas de barre de menus, mais c'est ce menu qui fait marcher
    // ⌘C, ⌘V, ⌘X, ⌘A, ⌘Z dans les champs, ⌘W pour fermer la fenêtre et ⌘, pour les réglages.
    private func keyboardMenu() -> NSMenu {
        let main = NSMenu()
        let appMenu = NSMenu()
        let prefs = NSMenuItem(title: L("Settings…", "Réglages…"), action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        appMenu.addItem(prefs)
        appMenu.addItem(NSMenuItem(title: L("Quit BlackCat", "Quitter BlackCat"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let edit = NSMenu(title: L("Edit", "Édition"))
        edit.addItem(NSMenuItem(title: L("Undo", "Annuler"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: L("Redo", "Rétablir"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: L("Cut", "Couper"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: L("Copy", "Copier"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: L("Paste", "Coller"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: L("Select All", "Tout sélectionner"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        let windowMenu = NSMenu(title: L("Window", "Fenêtre"))
        windowMenu.addItem(NSMenuItem(title: L("Close", "Fermer"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: L("Minimize", "Réduire"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        for submenu in [appMenu, edit, windowMenu] {
            let item = NSMenuItem()
            item.submenu = submenu
            main.addItem(item)
        }
        return main
    }

    // Après l'accès : les réglages si la clé API manque encore, sinon les tâches.
    private lazy var firstLaunch = FirstLaunchController { [weak self] in
        guard let self else { return }
        mainWindow.show(settings.apiKey.isEmpty ? .settings : .tasks)
    }

    // Relancer l'app alors qu'elle tourne déjà ouvre la fenêtre.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show(.tasks)
        return false
    }

    private func registerHotKeys() {
        HotKeys.register(.correct, settings.correctShortcut) { [weak self] in self?.correctSelection() }
        HotKeys.register(.open, settings.openShortcut) { [weak self] in self?.mainWindow.show(.tasks) }
    }

    // Reconstruit à chaque ouverture, pour afficher les raccourcis du moment.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        addTaskPreview(to: menu)
        menu.addItem(item(L("Correct Selection", "Corriger la sélection"), #selector(correctFromMenu), settings.correctShortcut))
        menu.addItem(item(L("Open BlackCat", "Ouvrir BlackCat"), #selector(openTasks), settings.openShortcut))
        let prefs = NSMenuItem(title: L("Settings…", "Réglages…"), action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("Quit BlackCat", "Quitter BlackCat"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // Les premières tâches à faire, cochables depuis le menu.
    // Selon les réglages : le projet choisi (sinon celui en cours), et N tâches (0 = pas de liste).
    private func addTaskPreview(to menu: NSMenu) {
        let chosen = settings.menuProjectID.flatMap { id in store.projects.first { $0.id == id } }
        guard settings.menuTaskCount > 0, let project = chosen ?? store.selected else { return }
        let header = NSMenuItem(title: project.name, action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(string: project.name, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        header.isEnabled = false
        menu.addItem(header)
        let open = project.open.prefix(settings.menuTaskCount)
        if open.isEmpty {
            let empty = NSMenuItem(title: L("No tasks", "Aucune tâche"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for task in open {
            let row = NSMenuItem()
            let host = NSHostingView(rootView: MenuTaskRow(store: store, projectID: project.id, taskID: task.id))
            host.frame = NSRect(x: 0, y: 0, width: 280, height: 28)
            row.view = host
            menu.addItem(row)
        }
        menu.addItem(.separator())
    }

    private func item(_ title: String, _ action: Selector?, _ shortcut: Shortcut?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: shortcut?.keyEquivalent ?? "")
        item.target = self
        if let shortcut { item.keyEquivalentModifierMask = shortcut.flags }
        return item
    }

    // Depuis le menu du chat, macOS ignore la demande de passer au premier plan tant que le menu
    // se referme : on ouvre la fenêtre juste après.
    @objc private func openTasks() { showAfterMenu(.tasks) }
    @objc private func openSettings() { showAfterMenu(.settings) }

    private func showAfterMenu(_ page: WindowModel.Page) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.mainWindow.show(page) }
    }

    // Depuis le menu, le texte sélectionné est resté dans l'app d'avant : on la laisse
    // reprendre la main le temps que le menu se referme.
    @objc private func correctFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.correctSelection() }
    }

    private var correcting = false
    private let timing = Logger(subsystem: "ai.veronese.blackcat", category: "correction")

    private static func ms(since date: Date) -> String {
        "\(Int(Date().timeIntervalSince(date) * 1000)) ms"
    }

    private func correctSelection() {
        guard !correcting else { return }
        guard AXIsProcessTrusted() else {
            firstLaunch.show()
            return
        }
        correcting = true
        cat?.busy = true
        let overlay = CorrectionOverlay.shared
        overlay.dismiss()
        Task { @MainActor in
            let started = Date()
            var steps = ""
            defer {
                correcting = false
                cat?.busy = false
                CatDrop.shared.finish()
                // Temps de chaque étape, lisibles avec :
                // log show --last 1h --predicate 'subsystem == "ai.veronese.blackcat"'
                timing.notice("correction \(steps, privacy: .public), total \(Self.ms(since: started), privacy: .public)")
            }
            guard let grab = await TextAccess.selection() else {
                NSSound.beep()
                steps = "sans sélection"
                return
            }
            steps = "\(grab.text.count) caractères, lecture \(Self.ms(since: started))"
            CatDrop.shared.show(above: grab.bounds)
            let result: CorrectionResult
            let askedAt = Date()
            do {
                result = try await OpenAI.correct(grab.text, key: settings.apiKey)
                steps += ", OpenAI \(Self.ms(since: askedAt))"
            } catch {
                steps += ", OpenAI en échec après \(Self.ms(since: askedAt)) : \(error.localizedDescription)"
                if case OpenAIError.noKey = error { mainWindow.show(.settings) }
                overlay.showMessage(error.localizedDescription, near: grab.bounds)
                return
            }
            guard result.texte != grab.text else {
                overlay.showMessage(L("No mistakes", "Aucune faute"), near: grab.bounds)
                return
            }
            await TextAccess.replaceSelection(with: result.texte)

            // Les mots réellement changés, avec la raison de l'IA quand elle en a donné une.
            guard let changes = Diff.changes(from: grab.text, to: result.texte) else {
                if !result.corrections.isEmpty { overlay.showBubble(result.corrections, near: grab.bounds, rules: settings.dismissRules) }
                return
            }
            let explained = Diff.explain(changes, with: result.corrections)
            guard !explained.isEmpty else { return }

            // Soulignés si l'app dit où sont les mots, sinon bulle de repli.
            if let start = grab.range?.location, let element = grab.element {
                let items = explained.compactMap { item -> (rect: CGRect, range: CFRange, correction: Correction)? in
                    let range = CFRange(location: start + item.range.location, length: item.range.length)
                    return TextAccess.bounds(of: range, in: element).map { ($0, range, item.correction) }
                }
                if items.count == explained.count {
                    overlay.showUnderlines(items, in: element, rules: settings.dismissRules)
                    return
                }
            }
            overlay.showBubble(explained.map(\.correction), near: grab.bounds, rules: settings.dismissRules)
        }
    }
}
