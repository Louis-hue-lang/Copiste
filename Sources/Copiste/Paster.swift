import AppKit
import os

let log = Logger(subsystem: "fr.louisclauzier.copiste", category: "app")

enum Paster {
    /// Place le texte dans le presse-papier puis simule ⌘V dans l'app au premier plan.
    /// Nécessite l'autorisation Accessibilité.
    static func paste(_ text: String, history: ClipboardHistory) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        history.ignoreCurrent()

        let trusted = AXIsProcessTrusted()
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        log.info("paste: trusted=\(trusted, privacy: .public) frontmost=\(front, privacy: .public)")

        guard trusted else {
            showPermissionAlert()
            return
        }

        // Laisse le menu se fermer et le focus revenir à l'app cible.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let source = CGEventSource(stateID: .combinedSessionState)
            // Ignore le clavier physique pendant l'envoi (une touche ⌥ encore enfoncée ferait ⌥⌘V).
            source?.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitSystemDefinedEvents],
                state: .eventSuppressionStateSuppressionInterval
            )
            let vKey: CGKeyCode = 9 // touche V (même position en AZERTY et QWERTY)
            // 0x08 = bit « ⌘ gauche » : certaines apps l'exigent en plus du masque générique.
            let flags = CGEventFlags(rawValue: CGEventFlags.maskCommand.rawValue | 0x08)
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
            down?.flags = flags
            up?.flags = flags
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            log.info("paste: ⌘V envoyé (events ok=\(down != nil && up != nil, privacy: .public))")
        }
    }

    private static func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Copiste ne peut pas coller"
        alert.informativeText = "Le texte est dans le presse-papier (⌘V pour le coller).\n\nPour le collage automatique, autorisez Copiste dans Réglages Système › Confidentialité et sécurité › Contrôle de l'appareil (anciennement Accessibilité), puis relancez Copiste.\n\nSi Copiste y est déjà coché, supprimez-le avec −, puis ajoutez-le de nouveau."
        alert.addButton(withTitle: "Ouvrir les Réglages")
        alert.addButton(withTitle: "Plus tard")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }
}
