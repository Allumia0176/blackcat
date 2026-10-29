import AppKit
import SwiftUI

// Ce qui s'affiche par-dessus l'app où l'on écrit : les soulignés bleus et leur
// infobulle au survol (correction validée), ou la bulle de repli quand l'app ne
// dit pas où sont les mots. Quand ça disparaît : selon les réglages (Rules).
@MainActor
final class CorrectionOverlay {
    static let shared = CorrectionOverlay()

    // Réglages « Masquer les explications… » de la section Correction.
    struct Rules {
        var seconds: TimeInterval?  // nil = jamais
        var onClick: Bool
        var onTyping: Bool
    }

    // Un mot souligné : sa place à l'écran, son explication, sa position dans le champ, son trait bleu.
    private struct Mark {
        var rect: CGRect
        let correction: Correction
        let range: CFRange?
        let panel: NSPanel
    }

    private var marks: [Mark] = []
    private var element: AXUIElement?
    private var tracker: Timer?
    private var ticks = 0
    private var misses = 0
    private var tip: NSPanel?
    private var tipIndex: Int?
    private var bubble: NSPanel?
    private var monitors: [Any] = []
    private var timeout: Timer?
    private var appSwitch: NSObjectProtocol?

    // Les soulignés sont ensuite surveillés en continu (track) : ils suivent leurs mots
    // s'ils bougent, et disparaissent si les mots changent ou s'en vont.
    func showUnderlines(_ items: [(rect: CGRect, range: CFRange, correction: Correction)], in element: AXUIElement?, rules: Rules) {
        dismiss()
        self.element = element
        marks = items.map { item in
            let panel = makePanel(lineFrame(item.rect))
            panel.backgroundColor = Theme.accentColor
            panel.orderFrontRegardless()
            return Mark(rect: item.rect, correction: item.correction, range: item.range, panel: panel)
        }
        watch(rules, underlines: true)
        tracker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { CorrectionOverlay.shared.track() }
        }
    }

    private func lineFrame(_ rect: CGRect) -> NSRect {
        NSRect(x: rect.minX, y: rect.minY - 2, width: rect.width, height: 1.5)
    }

    // Toutes les 0,1 s : la souris est-elle sur un mot ? Toutes les 0,4 s : les mots sont-ils
    // toujours là, au même endroit ? (Certaines apps ne signalent ni frappe ni changement.)
    private func track() {
        hover()
        ticks += 1
        guard ticks % 4 == 0, let element else { return }
        var lost = false
        for i in marks.indices {
            guard let range = marks[i].range else { continue }
            // Un texte différent à cette place : le mot a été modifié ou effacé.
            if let now = TextAccess.string(of: range, in: element), now != marks[i].correction.apres {
                dismiss()
                return
            }
            guard let rect = TextAccess.bounds(of: range, in: element) else {
                lost = true
                continue
            }
            if abs(rect.minX - marks[i].rect.minX) > 0.5 || abs(rect.minY - marks[i].rect.minY) > 0.5
                || abs(rect.width - marks[i].rect.width) > 0.5 {
                marks[i].rect = rect
                marks[i].panel.setFrame(lineFrame(rect), display: true)
                if tipIndex == i { hideTip() }
            }
        }
        // Le champ ne répond plus (fenêtre fermée, texte parti) deux fois de suite : on efface.
        misses = lost ? misses + 1 : 0
        if misses >= 2 { dismiss() }
    }

    func showBubble(_ corrections: [Correction], near anchor: CGRect?, rules: Rules) {
        showBubble(BubbleView(corrections: corrections, message: nil), near: anchor, rules: rules)
    }

    // Les messages courts (« Aucune faute », erreurs) suivent toujours la même règle.
    func showMessage(_ message: String, near anchor: CGRect?) {
        showBubble(BubbleView(corrections: [], message: message), near: anchor,
                   rules: Rules(seconds: 4, onClick: true, onTyping: true))
    }

    func dismiss() {
        marks.forEach { $0.panel.orderOut(nil) }
        marks = []
        element = nil
        tracker?.invalidate()
        tracker = nil
        ticks = 0
        misses = 0
        hideTip()
        bubble?.orderOut(nil)
        bubble = nil
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        timeout?.invalidate()
        timeout = nil
        if let appSwitch { NSWorkspace.shared.notificationCenter.removeObserver(appSwitch) }
        appSwitch = nil
    }

    private func showBubble(_ view: BubbleView, near anchor: CGRect?, rules: Rules) {
        dismiss()
        let panel = makeGlassPanel(view, above: anchor)
        panel.orderFrontRegardless()
        bubble = panel
        watch(rules, underlines: false)
    }

    // Au-dessus du texte visé, ou en dessous s'il n'y a pas la place ; sinon près de la souris.
    private func place(_ size: NSSize, above anchor: CGRect?) -> NSPoint {
        let target = anchor ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(target.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var y = target.maxY + 8
        if y + size.height > visible.maxY { y = target.minY - size.height - 8 }
        let x = min(max(target.minX - 12, visible.minX + 8), visible.maxX - size.width - 8)
        return NSPoint(x: x, y: max(y, visible.minY + 8))
    }

    private func watch(_ rules: Rules, underlines: Bool) {
        let close: (NSEvent) -> Void = { _ in MainActor.assumeIsolated { CorrectionOverlay.shared.dismiss() } }
        var masks: [NSEvent.EventTypeMask] = []
        if rules.onTyping { masks.append(.keyDown) }
        if rules.onClick { masks += [.leftMouseDown, .rightMouseDown] }
        // Le défilement déplace le texte : des soulignés ne seraient plus au bon endroit,
        // donc ils disparaissent toujours ; la bulle, elle, peut rester.
        if underlines { masks.append(.scrollWheel) }
        for mask in masks {
            if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: close) { monitors.append(m) }
        }
        appSwitch = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { _ in MainActor.assumeIsolated { CorrectionOverlay.shared.dismiss() } }
        if let seconds = rules.seconds {
            timeout = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                MainActor.assumeIsolated { CorrectionOverlay.shared.dismiss() }
            }
        }
    }

    private func hover() {
        let mouse = NSEvent.mouseLocation
        guard let index = marks.firstIndex(where: { $0.rect.insetBy(dx: -2, dy: -3).contains(mouse) }) else {
            hideTip()
            return
        }
        guard index != tipIndex else { return }
        hideTip()
        let panel = makeGlassPanel(TipView(correction: marks[index].correction), above: marks[index].rect)
        panel.orderFrontRegardless()
        tip = panel
        tipIndex = index
    }

    private func hideTip() {
        tip?.orderOut(nil)
        tip = nil
        tipIndex = nil
    }

    // Infobulle et bulle de repli : le contenu posé dans un vrai panneau de verre.
    private func makeGlassPanel<V: View>(_ view: V, above anchor: CGRect?) -> NSPanel {
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let panel = makePanel(NSRect(origin: place(size, above: anchor), size: size))
        panel.contentView = Glass.wrap(host, cornerRadius: 12)
        return panel
    }

    private func makePanel(_ frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        return panel
    }
}

struct CorrectionRow: View {
    let correction: Correction

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(correction.apres)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.accent)
                Text(correction.avant)
                    .font(.system(size: 13))
                    .strikethrough(color: Theme.muted)
                    .foregroundStyle(Theme.muted)
            }
            Text(correction.raison)
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TipView: View {
    let correction: Correction

    var body: some View {
        CorrectionRow(correction: correction)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 240)
            .card()
    }
}

struct BubbleView: View {
    let corrections: [Correction]
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            ForEach(Array(corrections.enumerated()), id: \.offset) { _, correction in
                CorrectionRow(correction: correction)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 300, alignment: .leading)
        .card()
    }
}

extension View {
    // Le fond vient du verre du panneau (CorrectionOverlay.makeGlassPanel).
    func card() -> some View {
        fixedSize(horizontal: false, vertical: true)
    }
}
