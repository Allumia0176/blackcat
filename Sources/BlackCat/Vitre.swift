import AppKit
import SwiftUI

// Le verre dessiné par l'app, d'après les maquettes « une seule vitre » validées le 27/10/2026
// (docs/design/Vitre-1 et Reglages-Verre). Le verre natif d'Apple, posé sur la fenêtre déjà en
// verre, s'affichait mal : tout ce verre-ci est donc dessiné.
//  - la vitre : posée sur le choix actif d'un groupe, elle glisse vers ce qu'on survole ;
//  - le verre de survol : plus léger, il apparaît sous ce qu'on survole, avec un petit gonflement.
// Les deux portent un reflet qui suit la souris.
struct GlassPane<S: InsettableShape>: View {
    enum Level { case vitre, survol }

    let shape: S
    var level: Level = .survol
    var glow: CGPoint? = nil  // position de la souris dans le verre, pour le reflet
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let vitre = level == .vitre
        shape
            .fill(Color.white.opacity(vitre ? (dark ? 0.16 : 0.5) : (dark ? 0.09 : 0.3)))
            .overlay {
                if let glow {
                    GeometryReader { proxy in
                        RadialGradient(
                            colors: [.white.opacity(dark ? 0.22 : 0.65), .white.opacity(0)],
                            center: UnitPoint(x: glow.x / max(proxy.size.width, 1), y: glow.y / max(proxy.size.height, 1)),
                            startRadius: 0, endRadius: 49)
                    }
                    .clipShape(shape)
                }
            }
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(vitre ? (dark ? 0.45 : 0.95) : (dark ? 0.35 : 0.85)),
                                            .white.opacity(dark ? 0.08 : 0.25)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .shadow(color: .black.opacity(vitre ? (dark ? 0.35 : 0.16) : (dark ? 0.25 : 0.08)),
                    radius: vitre ? 6 : 4, y: vitre ? 3 : 2)
            .allowsHitTesting(false)
    }
}

// Verre de survol sous un élément cliquable. `on` le garde affiché sans survol (curseur clavier,
// raccourci en cours d'enregistrement, page ouverte). `inflate` le déborde à gauche et à droite.
struct HoverGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var on = false
    var inflate: CGFloat = 0
    @State private var mouse: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shown = mouse != nil || on
        content
            .background {
                GlassPane(shape: shape, glow: mouse.map { CGPoint(x: $0.x + inflate, y: $0.y) })
                    .padding(.horizontal, -inflate)
                    .scaleEffect(shown || reduceMotion ? 1 : 0.94)
                    .animation(.spring(response: 0.32, dampingFraction: 0.55), value: shown)
                    .opacity(shown ? 1 : 0)
                    .animation(.easeOut(duration: 0.18), value: shown)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let point): mouse = point
                case .ended: mouse = nil
                }
            }
    }
}

extension View {
    func hoverGlass<S: InsettableShape>(_ shape: S, on: Bool = false, inflate: CGFloat = 0) -> some View {
        modifier(HoverGlass(shape: shape, on: on, inflate: inflate))
    }
}

// Ressort commun à toutes les vitres qui glissent (léger dépassement, comme les maquettes).
enum Vitre {
    static let spring = Animation.spring(response: 0.5, dampingFraction: 0.62)
}

// Interrupteur « goutte » : la bille s'étire jusqu'à l'autre bord puis s'y resserre ;
// allumée, elle devient bleue et brillante. Au survol, elle gonfle un peu.
struct DropSwitch: View {
    @Binding var isOn: Bool
    let label: String
    @State private var left: CGFloat
    @State private var right: CGFloat
    @State private var hover = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let width: CGFloat = 46
    private static let offLeft: CGFloat = 2, offRight: CGFloat = 22
    private static let onLeft: CGFloat = 24, onRight: CGFloat = 44

    init(isOn: Binding<Bool>, label: String) {
        _isOn = isOn
        self.label = label
        _left = State(initialValue: isOn.wrappedValue ? Self.onLeft : Self.offLeft)
        _right = State(initialValue: isOn.wrappedValue ? Self.onRight : Self.offRight)
    }

    var body: some View {
        let dark = scheme == .dark
        let grow: CGFloat = hover ? 1.2 : 0
        Button {
            isOn.toggle()
        } label: {
            ZStack {
                Capsule()
                    .fill((isOn ? Theme.accent.opacity(dark ? 0.25 : 0.2) : (dark ? Color.white.opacity(0.12) : Color(white: 0.24).opacity(0.16)))
                        .shadow(.inner(color: .black.opacity(0.22), radius: 1.5, y: 1)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(hover ? 0.35 : 0), lineWidth: 1))
                    .animation(.easeOut(duration: 0.3), value: isOn)
                    .animation(.easeOut(duration: 0.18), value: hover)
                // Ombres et couleurs pleines passent par le style de remplissage : avec .shadow ou un
                // dégradé ombré, la bille était dessinée sur tout le rail.
                DropShape(left: left, right: right, grow: grow)
                    .fill(Color.white.shadow(.drop(color: .black.opacity(0.25), radius: 1.5, y: 1)))
                    .opacity(isOn ? 0 : 1)
                DropShape(left: left, right: right, grow: grow)
                    .fill(Theme.accent.shadow(.drop(color: Theme.accent.opacity(0.45), radius: 4, y: 2)))
                    .overlay {
                        DropShape(left: left, right: right, grow: grow)
                            .fill(RadialGradient(colors: [.white.opacity(0.6), .white.opacity(0)],
                                                 center: UnitPoint(x: (left + (right - left) * 0.35) / Self.width, y: 0.3),
                                                 startRadius: 0, endRadius: 10))
                    }
                    .opacity(isOn ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.3), value: isOn)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: hover)
            .frame(width: Self.width, height: 24)
            .padding(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .onChange(of: isOn) { move(on: isOn) }
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? L("on", "activé") : L("off", "désactivé"))
        .accessibilityAddTraits(.isToggle)
    }

    // Le bord avant part le premier, l'autre suit un peu plus tard : la goutte s'étire.
    private func move(on: Bool) {
        guard !reduceMotion else {
            left = on ? Self.onLeft : Self.offLeft
            right = on ? Self.onRight : Self.offRight
            return
        }
        let lead = Animation.timingCurve(0.5, 0, 0.2, 1, duration: 0.3)
        let follow = Animation.timingCurve(0.5, 0, 0.2, 1, duration: 0.42).delay(0.1)
        if on {
            withAnimation(lead) { right = Self.onRight }
            withAnimation(follow) { left = Self.onLeft }
        } else {
            withAnimation(lead) { left = Self.offLeft }
            withAnimation(follow) { right = Self.offRight }
        }
    }
}

// La bille, de son bord gauche à son bord droit, dans le rail (hauteur 20, centrée).
struct DropShape: Shape {
    var left: CGFloat
    var right: CGFloat
    var grow: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(left, right), grow) }
        set { left = newValue.first.first; right = newValue.first.second; grow = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let height = 20 + grow * 2
        let box = CGRect(x: left - grow, y: rect.midY - height / 2, width: max(right - left, 0) + grow * 2, height: height)
        return Capsule().path(in: box)
    }
}

// Champ cliquable (clé, raccourci) : creux gris, verre au survol.
extension View {
    func glassField(on: Bool = false) -> some View {
        hoverGlass(RoundedRectangle(cornerRadius: 9, style: .continuous), on: on)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

// Menu déroulant en verre : un bouton, et sous lui une liste en verre avec sa propre vitre.
struct GlassMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let label: String
    let options: [(Value, String)]
    @State private var anchor = ScreenAnchor()
    @State private var open = false

    var body: some View {
        let current = options.first { $0.0 == selection }?.1 ?? options.first?.1 ?? ""
        Button(action: show) {
            HStack(spacing: 8) {
                Text(current).font(.system(size: 13)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .hoverGlass(Capsule(), on: open)
            .background(Theme.well, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background(AnchorReader(anchor: anchor))
        .accessibilityLabel(label)
        .accessibilityValue(current)
        .onDisappear { if open { GlassMenu.close() } }
    }

    private func show() {
        guard let rect = anchor.screenRect else { return }
        let chosen = options.firstIndex { $0.0 == selection } ?? 0
        let binding = $selection
        let values = options.map(\.0)
        open = true
        GlassMenu.show(below: rect, rows: options.count, onClose: { open = false }) {
            GlassMenuList(items: options.map(\.1), chosen: chosen) { index in
                binding.wrappedValue = values[index]
                GlassMenu.close()
            }
        }
    }
}

struct GlassMenuList: View {
    let items: [String]
    let chosen: Int
    let pick: (Int) -> Void
    @State private var mouse: CGPoint?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let rowHeight: CGFloat = 28

    var body: some View {
        let hovered = mouse.map { min(max(Int($0.y / Self.rowHeight), 0), items.count - 1) }
        let at = hovered ?? chosen
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Button {
                    pick(index)
                } label: {
                    Text(item)
                        .font(.system(size: 13, weight: index == chosen ? .semibold : .regular))
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: Self.rowHeight, maxHeight: Self.rowHeight, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(index == chosen ? .isSelected : [])
            }
        }
        .background(alignment: .top) {
            GlassPane(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), level: .vitre,
                      glow: hovered == nil ? nil : mouse.map { CGPoint(x: $0.x, y: $0.y - CGFloat(at) * Self.rowHeight) })
                .frame(height: Self.rowHeight)
                .offset(y: CGFloat(at) * Self.rowHeight)
                .animation(reduceMotion ? nil : Vitre.spring, value: at)
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): mouse = point
            case .ended: mouse = nil
            }
        }
        .padding(5)
        .foregroundStyle(Theme.ink)
    }
}

// La fenêtre flottante du menu en verre. Un clic ailleurs ou Échap la ferme.
@MainActor
enum GlassMenu {
    private static var panel: NSPanel?
    private static var monitors: [Any] = []
    private static var onClose: (() -> Void)?

    static var isOpen: Bool { panel != nil }

    static func show<Content: View>(below rect: NSRect, rows: Int, onClose: @escaping () -> Void,
                                    @ViewBuilder content: () -> Content) {
        close()
        let width: CGFloat = 220
        let height = CGFloat(rows) * GlassMenuList.rowHeight + 10
        let frame = NSRect(x: rect.maxX - width, y: rect.minY - 6 - height, width: width, height: height)
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isReleasedWhenClosed = false
        panel.contentView = Glass.wrap(NSHostingView(rootView: content()), cornerRadius: 12)
        panel.orderFront(nil)
        self.panel = panel
        self.onClose = onClose

        // Clic hors du menu : il se ferme, et ce clic ne fait rien d'autre (comme un menu du Mac).
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in
            let outside = MainActor.assumeIsolated { event.window !== GlassMenu.panel }
            guard outside else { return event }
            MainActor.assumeIsolated { GlassMenu.close() }
            return nil
        }) { monitors.append(local) }
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated { GlassMenu.close() }
            return nil
        }) { monitors.append(keys) }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { _ in
            MainActor.assumeIsolated { GlassMenu.close() }
        }) { monitors.append(global) }
    }

    static func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.orderOut(nil)
        panel = nil
        let done = onClose
        onClose = nil
        done?()
    }
}

// Retient la vue AppKit sous un élément SwiftUI, pour connaître sa place à l'écran au moment du clic.
@MainActor
final class ScreenAnchor {
    weak var view: NSView?

    var screenRect: NSRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

struct AnchorReader: NSViewRepresentable {
    let anchor: ScreenAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}
