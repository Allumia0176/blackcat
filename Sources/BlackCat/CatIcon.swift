import AppKit

// Le chat de la barre des menus : toujours noir, les yeux suivent la souris
// et clignent de temps en temps : une paupière noire descend sur chaque œil. Les tracés reprennent l'icône validée,
// dessinée sur une grille de 24 × 24.
@MainActor
final class CatIcon {
    private weak var button: NSStatusBarButton?
    private var pupil = CGPoint.zero
    private var blinking = false
    private var lid: CGFloat = 0  // 0 : yeux ouverts, 1 : paupières baissées
    private var monitors: [Any] = []
    private var blinkTimer: Timer?
    private var lidTimer: Timer?

    // Pendant une correction, le chat ferme les yeux : il réfléchit.
    var busy = false {
        didSet { if busy != oldValue { moveLid() } }
    }

    init(button: NSStatusBarButton) {
        self.button = button
        redraw()
        let follow: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: follow) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            follow(event)
            return event
        }) {
            monitors.append(local)
        }
        scheduleBlink()
    }

    private func follow() {
        guard let button, let window = button.window else { return }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        let mouse = NSEvent.mouseLocation
        let target = Self.gaze(from: CGPoint(x: frame.midX, y: frame.midY), to: mouse)
        // Rien à redessiner tant que la pupille bouge de moins d'un vingtième de point.
        guard hypot(target.x - pupil.x, target.y - pupil.y) > 0.05 else { return }
        pupil = target
        redraw()
    }

    // Position des pupilles pour regarder `mouse` depuis `eyes` (coordonnées de l'écran).
    static func gaze(from eyes: CGPoint, to mouse: CGPoint) -> CGPoint {
        let dx = mouse.x - eyes.x
        let dy = eyes.y - mouse.y  // l'icône est dessinée de haut en bas
        let distance = hypot(dx, dy)
        guard distance > 0 else { return .zero }
        let reach = min(1, distance / 60) * 0.6
        return CGPoint(x: dx / distance * reach, y: dy / distance * reach)
    }

    private func scheduleBlink() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 2.5...6.5), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.blinking = true
                self.moveLid()
                Timer.scheduledTimer(withTimeInterval: 0.32, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        self.blinking = false
                        self.moveLid()
                        self.scheduleBlink()
                    }
                }
            }
        }
    }

    // La paupière tombe en 160 ms en accélérant, puis remonte en 220 ms en ralentissant,
    // redessinée image par image.
    private func moveLid() {
        lidTimer?.invalidate()
        let from = lid
        let to: CGFloat = blinking || busy ? 1 : 0
        guard from != to else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            lid = to
            redraw()
            return
        }
        let closing = to > from
        let duration = closing ? 0.16 : 0.22
        let start = Date()
        lidTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let t = min(1, Date().timeIntervalSince(start) / duration)
                let eased = closing ? t * t : 1 - (1 - t) * (1 - t) * (1 - t)
                self.lid = from + (to - from) * eased
                self.redraw()
                if t >= 1 { self.lidTimer?.invalidate() }
            }
        }
    }

    private func redraw() {
        button?.image = Self.image(pupil: pupil, lid: lid)
    }

    // Avec `badge`, le chat est posé sur un petit fond arrondi gris très clair,
    // pour rester visible quand la barre des menus est sombre.
    // Le chat entier, ou séparément le corps et la queue (pour animer la queue, voir CatDrop).
    enum Parts { case all, body, tail }

    static func image(pupil: CGPoint, lid: CGFloat = 0, height: CGFloat = 22, badge: Bool = false, parts: Parts = .all) -> NSImage {
        // Cadrage serré autour du chat (grille de 24 × 24).
        let crop = NSRect(x: 3.0, y: 1.5, width: 19.3, height: 21.8)
        let inset: CGFloat = badge ? 2.5 : 0
        let scale = (height - inset * 2) / crop.height
        let size = NSSize(width: (crop.width * scale + inset * 2).rounded(.up), height: height)
        let image = NSImage(size: size, flipped: true) { _ in
            if badge {
                NSColor(hex: 0xdcdce0).setFill()
                NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 6, yRadius: 6).fill()
            }
            let t = NSAffineTransform()
            t.translateX(by: (size.width - crop.width * scale) / 2, yBy: inset)
            t.scale(by: scale)
            t.translateX(by: -crop.minX, yBy: -crop.minY)
            t.concat()

            NSColor(hex: 0x0a0a0a).setFill()
            NSColor(hex: 0x0a0a0a).setStroke()

            let tail = NSBezierPath()
            tail.move(to: p(13, 15))
            tail.curve(to: p(18.7, 8.2), controlPoint1: p(16.5, 14.5), controlPoint2: p(18.6, 12))
            tail.curve(to: p(21.4, 5.4), controlPoint1: p(18.8, 6), controlPoint2: p(20, 4.9))
            tail.lineWidth = 1.5
            tail.lineCapStyle = .round
            if parts != .body { tail.stroke() }
            if parts == .tail { return true }

            let body = NSBezierPath()
            body.move(to: p(8, 10.6))
            body.curve(to: p(5.2, 19.6), controlPoint1: p(6, 12.8), controlPoint2: p(5, 16.2))
            body.curve(to: p(10, 23.2), controlPoint1: p(5.4, 22.4), controlPoint2: p(7.4, 23.2))
            body.curve(to: p(14.8, 19.6), controlPoint1: p(12.6, 23.2), controlPoint2: p(14.6, 22.4))
            body.curve(to: p(12, 10.6), controlPoint1: p(15, 16.2), controlPoint2: p(14, 12.8))
            body.close()
            body.fill()

            // Tête ronde et oreilles : chaque oreille part de deux points du cercle,
            // donc l'ensemble forme une seule silhouette.
            NSBezierPath(ovalIn: NSRect(x: 6, y: 3.4, width: 8, height: 8)).fill()
            for side in [-1.0, 1.0] {
                let ear = NSBezierPath()
                ear.move(to: p(10 + side * 3.86, 6.36))
                ear.curve(to: p(10 + side * 3.7, 1.8), controlPoint1: p(10 + side * 4.15, 4.8), controlPoint2: p(10 + side * 4.1, 3.2))
                ear.curve(to: p(10 + side * 1.37, 3.64), controlPoint1: p(10 + side * 3.1, 2.2), controlPoint2: p(10 + side * 2.3, 2.8))
                ear.close()
                ear.fill()
            }

            let whiskers = NSBezierPath()
            for (from, to) in [((6.8, 8.9), (3.4, 8.3)), ((6.8, 9.7), (3.5, 10.3)),
                               ((13.2, 8.9), (16.6, 8.3)), ((13.2, 9.7), (16.5, 10.3))] {
                whiskers.move(to: p(from.0, from.1))
                whiskers.line(to: p(to.0, to.1))
            }
            whiskers.lineWidth = 0.6
            whiskers.lineCapStyle = .round
            whiskers.stroke()

            // Yeux un peu plus grands que sur la maquette, pour qu'on les voie suivre la souris.
            // On ne dessine que la partie de l'œil sous la paupière : fermé, il ne reste aucun blanc.
            if lid < 1 {
                for x in [8.3, 11.7] {
                    let eye = NSRect(x: x - 1.45, y: 5.8, width: 2.9, height: 3.2)
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(ovalIn: eye).addClip()
                    let lidEdge = eye.minY + eye.height * lid
                    NSBezierPath(rect: NSRect(x: eye.minX, y: lidEdge, width: eye.width, height: eye.maxY - lidEdge)).addClip()
                    NSColor.white.setFill()
                    NSBezierPath(ovalIn: eye).fill()
                    NSColor(hex: 0x0a0a0a).setFill()
                    let center = p(x + pupil.x, 7.4 + pupil.y)
                    NSBezierPath(ovalIn: NSRect(x: center.x - 0.75, y: center.y - 0.75, width: 1.5, height: 1.5)).fill()
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
            return true
        }
        image.isTemplate = false  // il reste noir, même sur une barre sombre
        image.accessibilityDescription = "BlackCat"
        return image
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }
}
