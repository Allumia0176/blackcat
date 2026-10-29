import AppKit
import ApplicationServices
import SwiftUI

// Le premier lancement : demander l'accès « Accessibilité », sans lequel l'app
// ne peut ni lire ni remplacer le texte sélectionné. La fenêtre voit toute seule
// le moment où l'accès est donné.
@MainActor
@Observable
final class AccessModel {
    var granted = AXIsProcessTrusted()
}

@MainActor
final class FirstLaunchController {
    private let model = AccessModel()
    private var window: NSWindow?
    private var poll: Timer?
    private let onContinue: () -> Void

    init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    func show() {
        model.granted = AXIsProcessTrusted()
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        poll?.invalidate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.model.granted = true
                self.poll?.invalidate()
                self.poll = nil
                self.window?.makeKeyAndOrderFront(nil)
                NSApp.activate()
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let view = FirstLaunchView(model: model) {
            // Ajoute l'app à la liste de macOS et ouvre directement le bon réglage.
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        } finish: { [weak self] in
            self?.close()
            self?.onContinue()
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        Glass.makeGlassWindow(window, content: host)
        window.setContentSize(size)
        window.center()
        return window
    }

    private func close() {
        poll?.invalidate()
        poll = nil
        window?.orderOut(nil)
    }
}

struct FirstLaunchView: View {
    @Bindable var model: AccessModel
    let openSettings: () -> Void
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.granted {
                Text(L("Access granted", "Accès autorisé"))
                    .font(.system(size: 17, weight: .semibold))
                DarkButton(title: L("Continue", "Continuer"), action: finish)
                    .padding(.top, 8)
            } else {
                Text(L("Allow BlackCat", "Autoriser BlackCat"))
                    .font(.system(size: 17, weight: .semibold))
                Text(L("To correct the selected text, BlackCat needs macOS Accessibility access.", "Pour corriger le texte sélectionné, BlackCat a besoin de l'accès Accessibilité de macOS."))
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                DarkButton(title: L("Open System Settings", "Ouvrir les Réglages Système"), action: openSettings)
                    .padding(.top, 8)
            }
        }
        .foregroundStyle(Theme.ink)
        .padding(EdgeInsets(top: 48, leading: 32, bottom: 32, trailing: 32))
        .frame(width: 440, alignment: .leading)
    }
}

// Bouton principal presque noir (blanc cassé en mode sombre), comme sur la maquette.
struct DarkButton: View {
    let title: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.window)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Theme.ink.opacity(hover ? 0.88 : 1), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .onHover { hover = $0 }
    }
}
