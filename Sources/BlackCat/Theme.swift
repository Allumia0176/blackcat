import AppKit
import SwiftUI

// Couleurs des maquettes validées (docs/design), clair puis sombre.
enum Theme {
    static let window = dynamic(0xffffff, 0x1d1d20)
    static let ink = dynamic(0x0a0a0a, 0xf2f2f3)
    static let muted = dynamic(0x6b6b6b, 0xa1a1a6)
    // Sur le verre, les fonds et les traits sont translucides pour laisser voir à travers.
    static let line = translucent(0.10, 0.12)
    static let active = translucent(0.08, 0.14)
    static let hover = translucent(0.04, 0.08)
    static let track = dynamic(0xececee, 0x2c2c30)
    // Creux translucide des champs et des choix posés sur le verre (maquette Reglages-Verre).
    static let well = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.12)
            : NSColor(white: 0.5, alpha: 0.16)
    })
    static let segment = dynamic(0xffffff, 0x4a4a50)
    static let knob = dynamic(0xffffff, 0xe8e8ea)
    static let accent = dynamic(0x1d5fbf, 0x7aa7ff)
    static let control = dynamic(0xc2c2c2, 0x5c5c62)
    static let danger = dynamic(0xc4242a, 0xe5566f)
    static let bubble = dynamic(0xffffff, 0x232327)
    static let bubbleLine = dynamic(0xe2e2e2, 0x34343a)
    static let accentColor = dynamicNS(0x1d5fbf, 0x7aa7ff)

    // Noir léger en clair, blanc léger en sombre.
    private static func translucent(_ light: CGFloat, _ dark: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(white: 1, alpha: dark)
                : NSColor(white: 0, alpha: light)
        })
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: dynamicNS(light, dark))
    }

    private static func dynamicNS(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}
