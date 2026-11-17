import AppKit

/// Construit le menu (historique + dossiers de pré-copies) et colle l'élément choisi.
final class SnippetMenu: NSObject {
    private let store: SnippetStore
    private let history: ClipboardHistory
    private let openSettings: () -> Void
    var openSearch: (() -> Void)?
    private static let historyTag = 7001

    init(store: SnippetStore, history: ClipboardHistory, openSettings: @escaping () -> Void) {
        self.store = store
        self.history = history
        self.openSettings = openSettings
    }

    /// Affiche le menu sous le pointeur de la souris, sans activer Copiste :
    /// l'app au premier plan garde le focus et reçoit le collage.
    func showAtMouse() {
        let menu = NSMenu()
        fill(menu, statusBar: false)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    func fill(_ menu: NSMenu, statusBar: Bool) {
        menu.removeAllItems()

        var number = 0
        func key() -> String { number += 1; return number <= 9 ? "\(number)" : "" }

        if !history.pinned.isEmpty {
            menu.addItem(.sectionHeader(title: "Épinglés"))
            for text in history.pinned {
                let item = pasteItem(title: Self.label(text), text: text, key: key())
                item.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Épinglé")
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        let recent = history.recent
        if !recent.isEmpty {
            menu.addItem(.sectionHeader(title: "Historique"))
            var overflow: [String] = []
            for text in recent {
                if number < 9 {
                    menu.addItem(pasteItem(title: Self.label(text), text: text, key: key()))
                } else {
                    overflow.append(text)
                }
            }
            if !overflow.isEmpty {
                let older = NSMenuItem(title: "Plus ancien", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for text in overflow { sub.addItem(pasteItem(title: Self.label(text), text: text)) }
                older.submenu = sub
                menu.addItem(older)
            }
        }

        if !history.images.isEmpty {
            let imagesItem = NSMenuItem(title: "Images (\(history.images.count))", action: nil, keyEquivalent: "")
            imagesItem.image = NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil)
            let sub = NSMenu()
            for (i, clip) in history.images.enumerated() {
                let size = clip.pixelSize.map { " — \(Int($0.width))×\(Int($0.height))" } ?? ""
                let entry = NSMenuItem(title: "Image \(i + 1)\(size)", action: #selector(pick(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = clip
                entry.image = Self.thumbnail(clip.image)
                sub.addItem(entry)
            }
            imagesItem.submenu = sub
            menu.addItem(imagesItem)
        }

        if !history.items.isEmpty || !history.images.isEmpty {
            if let latest = history.recent.first ?? history.pinned.first {
                let transform = NSMenuItem(title: "Transformer la dernière copie", action: nil, keyEquivalent: "")
                transform.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
                let sub = NSMenu()
                for t in Transforms.available(for: latest) {
                    let entry = NSMenuItem(title: t.title, action: #selector(transformPick(_:)), keyEquivalent: "")
                    entry.target = self
                    entry.representedObject = t.apply(latest)
                    entry.toolTip = String(t.apply(latest).prefix(300))
                    sub.addItem(entry)
                }
                transform.submenu = sub
                menu.addItem(transform)
            }
            if let latest = history.recent.first ?? history.pinned.first {
                let trimmed = latest.trimmingCharacters(in: .whitespacesAndNewlines)
                let fields = FieldExtractor.fields(in: latest).filter { $0.value != trimmed }
                if !fields.isEmpty {
                    let only = NSMenuItem(title: "Coller seulement…", action: nil, keyEquivalent: "")
                    only.image = NSImage(systemSymbolName: "text.viewfinder", accessibilityDescription: nil)
                    let sub = NSMenu()
                    for f in fields {
                        let entry = NSMenuItem(title: "\(f.label) : \(Self.label(f.value))", action: #selector(transformPick(_:)), keyEquivalent: "")
                        entry.target = self
                        entry.representedObject = f.value
                        sub.addItem(entry)
                    }
                    only.submenu = sub
                    menu.addItem(only)
                }
            }
            menu.addItem(disabled("⇧ clic : épingler · ⌘ clic : supprimer"))
            menu.addItem(.separator())
        }

        menu.addItem(.sectionHeader(title: "Pré-copies"))
        if store.folders.isEmpty {
            menu.addItem(disabled("Aucun dossier"))
        }
        for folder in store.folders {
            let item = NSMenuItem(title: folder.name.isEmpty ? "Sans nom" : folder.name, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            let sub = NSMenu()
            if folder.snippets.isEmpty { sub.addItem(disabled("(vide)")) }
            for snippet in folder.snippets {
                let title = snippet.title.isEmpty ? Self.label(snippet.content) : snippet.title
                let item = pasteItem(title: title, text: snippet.content, isSnippet: true)
                item.tag = 0
                item.representedObject = snippet
                sub.addItem(item)
            }
            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let search = NSMenuItem(title: "Rechercher…", action: #selector(searchClicked), keyEquivalent: "f")
        search.keyEquivalentModifierMask = [.option, .command]
        search.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        search.target = self
        menu.addItem(search)
        let settings = NSMenuItem(title: "Gérer les pré-copies…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        if statusBar {
            menu.addItem(NSMenuItem(title: "Quitter Copiste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        }
    }

    // MARK: - Actions

    @objc private func transformPick(_ sender: NSMenuItem) {
        if let text = sender.representedObject as? String { Paster.paste(text, history: history) }
    }

    @objc private func pick(_ sender: NSMenuItem) {
        if let clip = sender.representedObject as? ClipImage {
            if NSEvent.modifierFlags.contains(.command) { history.removeImage(clip.id) }
            else { Paster.pasteImage(clip.png, history: history) }
            return
        }
        // Un élément de l'historique accepte des raccourcis au clic : ⇧ épingle / désépingle, ⌘ supprime.
        if let text = sender.representedObject as? String, sender.tag == Self.historyTag {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) { history.remove(text); return }
            if flags.contains(.shift) {
                history.pinned.contains(text) ? history.unpin(text) : history.pin(text)
                return
            }
        }
        if let snippet = sender.representedObject as? Snippet {
            Paster.paste(snippet.content, rtf: snippet.rtf, history: history)
        } else if let text = sender.representedObject as? String {
            Paster.paste(text, history: history)
        }
    }

    @objc private func searchClicked() { openSearch?() }

    @objc private func settingsClicked() {
        openSettings()
    }

    // MARK: - Helpers

    private func pasteItem(title: String, text: String, key: String = "", isSnippet: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = []
        item.target = self
        item.representedObject = text
        item.toolTip = String(text.prefix(500))
        item.tag = Self.historyTag
        if !isSnippet { item.image = NSImage(systemSymbolName: ClipKind.detect(text).symbol, accessibilityDescription: nil) }
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Vignette de 40 pt de haut maximum pour le menu.
    static func thumbnail(_ image: NSImage?) -> NSImage? {
        guard let image, image.size.width > 0, image.size.height > 0 else { return nil }
        let scale = min(56 / image.size.width, 40 / image.size.height, 1)
        let size = NSSize(width: max(1, image.size.width * scale), height: max(1, image.size.height * scale))
        let thumb = NSImage(size: size)
        thumb.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        thumb.unlockFocus()
        return thumb
    }

    static func label(_ text: String) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ⏎ ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.count > 50 ? String(oneLine.prefix(50)) + "…" : oneLine
    }
}
