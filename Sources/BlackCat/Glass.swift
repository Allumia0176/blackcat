import AppKit

// Le vrai Liquid Glass de macOS 26 : le contenu est posé DANS la vue de verre
// (jamais à côté), et AppKit se charge de garder le texte lisible quel que soit le fond.
@MainActor
enum Glass {
    static func wrap(_ content: NSView, cornerRadius: CGFloat) -> NSGlassEffectView {
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        return glass
    }

    // Une fenêtre dont tout le fond est en verre : on retire son fond opaque.
    static func makeGlassWindow(_ window: NSWindow, content: NSView) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = wrap(content, cornerRadius: 0)  // la fenêtre arrondit elle-même ses coins
    }
}
