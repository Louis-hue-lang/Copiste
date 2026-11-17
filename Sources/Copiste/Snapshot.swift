import AppKit

/// Export des visuels du README : `Copiste --snapshot <dossier>`.
/// Dessine les vrais panneaux avec des données fictives, dans un dossier temporaire :
/// les données de l'utilisateur ne sont ni lues ni modifiées.
enum Snapshot {
    static func run(into outDir: URL) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("copiste-snapshot-\(UUID().uuidString)")
        let history = ClipboardHistory(directory: tmp)
        let store = SnippetStore(directory: tmp)
        store.folders = [
            SnippetFolder(name: "Signatures", snippets: [
                Snippet(title: "Cordialement", content: "Bien cordialement,\nMarie Durand"),
                Snippet(title: "Signature complète", content: "Marie Durand — Responsable des ventes\n01 23 45 67 89"),
            ]),
            SnippetFolder(name: "Réponses types", snippets: [
                Snippet(title: "Accusé de réception", content: "Bonjour, nous avons bien reçu votre message et revenons vers vous sous 48 h."),
                Snippet(title: "Demande de RIB", content: "Pourriez-vous m'envoyer votre RIB pour finaliser le règlement ?"),
            ]),
        ]
        history.loadDemo(
            pinned: ["Bien cordialement,\nMarie Durand", "FR76 3000 6000 0112 3456 7890 189"],
            recent: [
                "https://exemple.fr/offre/2026?id=42",
                "Facture 2291 : 1 240,00 € à régler avant le 14 septembre 2026",
                "marie.durand@exemple.fr",
                "#4F8EF7",
                "func coller() {\n    pressePapier.valider()\n}",
                "Réunion de lancement jeudi à 14 h, salle Moulin",
                "01 23 45 67 89",
            ])

        write(SearchPanel(store: store, history: history).snapshot(query: ""), "recherche.png", in: outDir)
        write(CyclePanel().snapshot(items: history.items, pinnedCount: history.pinned.count, selected: 3),
              "cycle.png", in: outDir)
        try? FileManager.default.removeItem(at: tmp)
    }

    /// Rend une vue en image 2x, sur un fond opaque arrondi avec ombre portée.
    static func image(of view: NSView) -> NSImage? {
        view.appearance = NSAppearance(named: .aqua)
        // Hors écran, le flou du HUD se rend en gris : on le remplace par un fond clair uni.
        if let effect = view as? NSVisualEffectView {
            effect.material = .contentBackground
            effect.state = .inactive
        }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let size = view.bounds.size
        guard size.width > 0, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)

        let margin: CGFloat = 28
        let total = NSSize(width: size.width + margin * 2, height: size.height + margin * 2)
        let out = NSImage(size: total)
        out.lockFocus()
        let card = NSRect(x: margin, y: margin, width: size.width, height: size.height)
        let path = NSBezierPath(roundedRect: card, xRadius: 12, yRadius: 12)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = NSSize(width: 0, height: -6)
        shadow.set()
        NSColor(white: 0.97, alpha: 1).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        rep.draw(in: card)
        NSGraphicsContext.restoreGraphicsState()
        out.unlockFocus()
        return out
    }

    private static func write(_ image: NSImage?, _ name: String, in dir: URL) {
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("échec :", name); return }
        try? png.write(to: dir.appendingPathComponent(name))
        print(name)
    }
}
