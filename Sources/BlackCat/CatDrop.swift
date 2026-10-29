import AppKit
import QuartzCore

// Pendant une correction (variante A validée le 27/10/2026) : un petit chat tombe d'en haut
// et atterrit au-dessus du texte sélectionné, remue la queue pendant que l'IA travaille,
// puis repart d'un saut. Il ne capte aucun clic, et ses yeux suivent la souris.
@MainActor
final class CatDrop {
    static let shared = CatDrop()

    private let catSize = NSSize(width: 40, height: 46)
    private let fallHeight: CGFloat = 220
    private var panel: NSPanel?
    private var cat: CALayer?
    private var body: CALayer?
    private var scale: CGFloat = 2
    private var pupil = CGPoint.zero
    private var monitors: [Any] = []
    private var shownAt = Date.distantPast

    func show(above anchor: CGRect?) {
        removeNow()
        // Les pieds du chat se posent sur le haut de la sélection, à gauche ; sinon près de la souris.
        let target = anchor ?? CGRect(origin: NSEvent.mouseLocation, size: .zero)
        let feet = NSPoint(x: target.minX + 8, y: target.maxY + 1)
        let frame = NSRect(x: feet.x, y: feet.y, width: catSize.width, height: catSize.height + fallHeight)

        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let host = NSView(frame: NSRect(origin: .zero, size: frame.size))
        host.wantsLayer = true
        let scale = NSScreen.screens.first { $0.frame.contains(feet) }?.backingScaleFactor ?? 2

        let cat = CALayer()
        cat.anchorPoint = CGPoint(x: 0.5, y: 0)  // écrasement à l'atterrissage depuis les pieds
        cat.bounds = CGRect(origin: .zero, size: catSize)
        cat.position = CGPoint(x: catSize.width / 2, y: 0)
        let tail = imageLayer(CatIcon.image(pupil: .zero, height: catSize.height, parts: .tail), scale)
        // Pivot de la queue : sa base, au point (13 ; 15) de la grille du chat.
        tail.anchorPoint = CGPoint(x: (13 - 3) / 19.3, y: 1 - (15 - 1.5) / 21.8)
        tail.position = CGPoint(x: tail.anchorPoint.x * catSize.width, y: tail.anchorPoint.y * catSize.height)
        pupil = gaze(panelOrigin: frame.origin)
        let body = imageLayer(CatIcon.image(pupil: pupil, height: catSize.height, parts: .body), scale)
        body.position = CGPoint(x: catSize.width / 2, y: catSize.height / 2)
        cat.addSublayer(tail)
        cat.addSublayer(body)
        host.layer?.addSublayer(cat)
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        self.cat = cat
        self.body = body
        self.scale = scale
        shownAt = Date()
        watchMouse()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let now = CACurrentMediaTime()
        let fall = CABasicAnimation(keyPath: "position.y")
        fall.fromValue = fallHeight
        fall.toValue = 0
        fall.duration = 0.45
        fall.timingFunction = CAMediaTimingFunction(name: .easeIn)
        cat.add(fall, forKey: "fall")

        let squash = CAKeyframeAnimation(keyPath: "transform")
        squash.values = [CATransform3DIdentity, CATransform3DMakeScale(1.1, 0.84, 1), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        squash.keyTimes = [0, 0.3, 1]
        squash.beginTime = now + 0.45
        squash.duration = 0.25
        cat.add(squash, forKey: "squash")

        let swish = CABasicAnimation(keyPath: "transform.rotation.z")
        swish.fromValue = 0.08   // un peu vers la tête, sans passer devant les moustaches
        swish.toValue = -0.24    // puis vers l'extérieur
        swish.duration = 0.55
        swish.autoreverses = true
        swish.repeatCount = .infinity
        swish.beginTime = now + 0.7
        swish.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        tail.add(swish, forKey: "swish")
    }

    // Fin de la correction : le chat repart d'un saut. On le laisse au moins se poser avant.
    func finish() {
        guard let cat else { return }
        let wait = max(0, 0.75 - Date().timeIntervalSince(shownAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self, self.cat === cat else { return }
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                self.removeNow()
                return
            }
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated {
                    if self?.cat === cat { self?.removeNow() }
                }
            }
            let jump = CABasicAnimation(keyPath: "position.y")
            jump.toValue = 46
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.toValue = 0
            let leave = CAAnimationGroup()
            leave.animations = [jump, fade]
            leave.duration = 0.35
            leave.timingFunction = CAMediaTimingFunction(name: .easeIn)
            leave.fillMode = .forwards
            leave.isRemovedOnCompletion = false
            cat.add(leave, forKey: "leave")
            CATransaction.commit()
        }
    }

    private func removeNow() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel?.orderOut(nil)
        panel = nil
        cat = nil
        body = nil
    }

    // Regard depuis la tête du chat posé : (10 ; 7,4) sur sa grille de 24, cadrée sur (3 ; 1,5 ; 19,3 ; 21,8).
    private func gaze(panelOrigin: CGPoint) -> CGPoint {
        let head = CGPoint(x: panelOrigin.x + (10 - 3) / 19.3 * catSize.width,
                           y: panelOrigin.y + (1 - (7.4 - 1.5) / 21.8) * catSize.height)
        return CatIcon.gaze(from: head, to: NSEvent.mouseLocation)
    }

    private func watchMouse() {
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
    }

    private func follow() {
        guard let panel, let body else { return }
        let target = gaze(panelOrigin: panel.frame.origin)
        guard hypot(target.x - pupil.x, target.y - pupil.y) > 0.05 else { return }
        pupil = target
        CATransaction.begin()
        CATransaction.setDisableActions(true)  // pas de fondu entre deux regards
        body.contents = CatIcon.image(pupil: pupil, height: catSize.height, parts: .body).layerContents(forContentsScale: scale)
        CATransaction.commit()
    }

    private func imageLayer(_ image: NSImage, _ scale: CGFloat) -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: catSize)
        layer.contentsScale = scale
        layer.contents = image.layerContents(forContentsScale: scale)
        return layer
    }
}
