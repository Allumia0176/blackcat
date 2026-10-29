import AppKit
import Carbon.HIToolbox
import SwiftUI

// La page Réglages, telle que validée dans les maquettes.
struct SettingsView: View {
    @Bindable var settings: Settings
    let store: TaskStore
    @FocusState private var keyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Settings", "Réglages"))
                .font(.system(size: 24, weight: .semibold))
                .padding(.bottom, 4)
            // Une section par partie de l'app ; les réglages à venir s'ajoutent dans la leur.
            VStack(alignment: .leading, spacing: 0) {
                SettingSection(L("General", "Général"))
                SettingRow(L("Language", "Langue")) {
                    SegmentedPicker(selection: Binding(get: { Language.shared.french }, set: { Language.shared.french = $0 }),
                                    label: L("Language", "Langue"), options: [(false, "English"), (true, "Français")], width: 80)
                }
                SettingRow(L("Appearance", "Apparence")) {
                    AppearancePicker(selection: $settings.appearance)
                }
                SettingRow(L("Open at login", "Ouvrir au démarrage du Mac")) {
                    DropSwitch(isOn: $settings.launchAtLogin, label: L("Open at login", "Ouvrir au démarrage du Mac"))
                }
                SettingSection("Correction")
                SettingRow(L("API key", "Clé API")) {
                    SecureField("", text: $settings.apiKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($keyFocused)
                        .padding(.horizontal, 10)
                        .frame(width: 220, height: 28)
                        // Le clic sur la marge autour du texte donne aussi la main au champ,
                        // sans gêner la saisie ni le clic droit sur le champ lui-même.
                        .background(Color.clear.contentShape(Rectangle()).onTapGesture { keyFocused = true })
                        .glassField(on: keyFocused)
                        .accessibilityLabel(L("API key", "Clé API"))
                }
                SettingRow(L("Shortcut to correct", "Raccourci pour corriger")) {
                    ShortcutField(shortcut: $settings.correctShortcut)
                }
                SettingRow(L("Hide explanations after", "Masquer les explications après")) {
                    SegmentedPicker(selection: $settings.explainSeconds, label: L("Hide explanations after", "Masquer les explications après"),
                                    options: [(10, "10 s"), (30, "30 s"), (60, "1 min"), (300, "5 min"), (0, L("Never", "Jamais"))])
                }
                SettingRow(L("Hide when I click elsewhere", "Masquer au clic ailleurs")) {
                    DropSwitch(isOn: $settings.hideOnClick, label: L("Hide when I click elsewhere", "Masquer au clic ailleurs"))
                }
                SettingRow(L("Hide when I type", "Masquer quand j'écris")) {
                    DropSwitch(isOn: $settings.hideOnTyping, label: L("Hide when I type", "Masquer quand j'écris"))
                }
                SettingSection(L("Tasks", "Tâches"))
                SettingRow(L("Shortcut to open tasks", "Raccourci pour ouvrir les tâches")) {
                    ShortcutField(shortcut: $settings.openShortcut)
                }
                SettingRow(L("Shortcut to close tasks", "Raccourci pour fermer les tâches")) {
                    ShortcutField(shortcut: $settings.closeShortcut, plainKey: true)
                }
                SettingRow(L("Project shown in the cat menu", "Projet affiché dans le menu du chat")) {
                    GlassMenuPicker(selection: $settings.menuProjectID, label: L("Project shown in the cat menu", "Projet affiché dans le menu du chat"),
                                    options: [(UUID?.none, L("Current project", "Projet en cours"))] + store.projects.map { (Optional($0.id), $0.name) })
                }
                SettingRow(L("Tasks shown in the cat menu", "Tâches affichées dans le menu du chat")) {
                    SegmentedPicker(selection: $settings.menuTaskCount, label: L("Tasks shown in the cat menu", "Tâches affichées dans le menu du chat"),
                                    options: [(0, L("None", "Aucune")), (3, "3"), (5, "5"), (10, "10")])
                }
            }
            .frame(maxWidth: 540)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Titre d'une section de réglages : petit, gris, sans cadre ; 44 points de vide au-dessus
// pour bien séparer les sections (choisi le 27/10/2026).
struct SettingSection: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.muted)
            .padding(.top, 44)
            .padding(.bottom, 6)
    }
}

// Une ligne de réglage, sans trait de séparation.
struct SettingRow<Control: View>: View {
    let label: String
    let control: Control

    init(_ label: String, @ViewBuilder control: () -> Control) {
        self.label = label
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 24) {
            Text(label).font(.system(size: 14))
            Spacer(minLength: 0)
            control
        }
        .frame(minHeight: 52)
    }
}

struct AppearancePicker: View {
    @Binding var selection: Settings.Appearance

    var body: some View {
        SegmentedPicker(selection: $selection, label: L("Appearance", "Apparence"),
                        options: [(.auto, "Auto"), (.light, L("Light", "Clair")), (.dark, L("Dark", "Sombre"))], width: 64)
    }
}

// Choix en segments : une seule vitre, posée sur le choix actif (en gras), qui glisse
// vers l'option survolée et revient quand la souris s'en va.
struct SegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let label: String
    let options: [(Value, String)]
    var width: CGFloat = 56
    @State private var mouse: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let chosen = options.firstIndex { $0.0 == selection } ?? 0
        let hovered = mouse.map { min(max(Int($0.x / width), 0), options.count - 1) }
        let at = hovered ?? chosen
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let on = index == chosen
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: 13, weight: on ? .semibold : .regular))
                        .lineLimit(1)
                        .fixedSize()  // jamais de texte coupé
                        .foregroundStyle(on ? Theme.ink : Theme.muted)
                        .frame(width: width, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .background(alignment: .leading) {
            GlassPane(shape: RoundedRectangle(cornerRadius: 9, style: .continuous), level: .vitre,
                      glow: hovered == nil ? nil : mouse.map { CGPoint(x: $0.x - CGFloat(at) * width, y: $0.y) })
                .frame(width: width, height: 26)
                .offset(x: CGFloat(at) * width)
                .animation(reduceMotion ? nil : Vitre.spring, value: at)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): mouse = point
            case .ended: mouse = nil
            }
        }
        .padding(2)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

// Clic dans le champ, puis la combinaison voulue. Échap annule, sauf avec `plainKey`
// (touche seule permise) : Échap devient alors le raccourci, et un clic ailleurs annule.
struct ShortcutField: View {
    @Binding var shortcut: Shortcut?
    var plainKey = false
    @State private var recording = false
    @State private var monitor: Any?
    @State private var clearHover = false

    var body: some View {
        HStack(spacing: 4) {
            Button(action: start) {
                Text(recording ? L("Type the shortcut", "Tapez le raccourci") : (shortcut?.display ?? L("Choose", "Choisir")))
                    .font(.system(size: 13))
                    .foregroundStyle(recording || shortcut == nil ? Theme.muted : Theme.ink)
                    .frame(width: 150, height: 28)
                    .glassField(on: recording)  // le verre reste pendant qu'on tape le raccourci
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if shortcut != nil && !recording {
                Button {
                    shortcut = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(clearHover ? Theme.ink : Theme.muted)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { clearHover = $0 }  // pas de verre sur la croix, elle fonce juste
                .accessibilityLabel(L("Remove shortcut", "Retirer le raccourci"))
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        guard !recording else { return }
        recording = true
        HotKeys.suspend(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            if event.type == .leftMouseDown {
                stop()
                return event
            }
            if plainKey {
                shortcut = Shortcut(anyKey: event)
                stop()
            } else if event.keyCode == UInt16(kVK_Escape) {
                stop()
            } else if let captured = Shortcut(event: event) {
                shortcut = captured
                stop()
            }
            return nil
        }
    }

    private func stop() {
        recording = false
        HotKeys.suspend(false)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
