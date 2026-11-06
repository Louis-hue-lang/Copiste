import AppKit

/// Construit le menu (historique + dossiers de pré-copies) et colle l'élément choisi.
final class SnippetMenu: NSObject {
    private let store: SnippetStore
    private let history: ClipboardHistory
    private let openSettings: () -> Void

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

        let items = history.items
        if !items.isEmpty {
            menu.addItem(.sectionHeader(title: "Historique"))
            for (i, text) in items.prefix(9).enumerated() {
                menu.addItem(pasteItem(title: Self.label(text), text: text, key: "\(i + 1)"))
            }
            if items.count > 9 {
                let older = NSMenuItem(title: "Plus ancien", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for text in items.dropFirst(9) {
                    sub.addItem(pasteItem(title: Self.label(text), text: text))
                }
                older.submenu = sub
                menu.addItem(older)
            }
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
                let item = pasteItem(title: title, text: snippet.content)
                item.representedObject = snippet
                sub.addItem(item)
            }
            item.submenu = sub
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Gérer les pré-copies…", action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        if statusBar {
            menu.addItem(NSMenuItem(title: "Quitter Copiste", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        }
    }

    // MARK: - Actions

    @objc private func pick(_ sender: NSMenuItem) {
        if let snippet = sender.representedObject as? Snippet {
            Paster.paste(snippet.content, rtf: snippet.rtf, history: history)
        } else if let text = sender.representedObject as? String {
            Paster.paste(text, history: history)
        }
    }

    @objc private func settingsClicked() {
        openSettings()
    }

    // MARK: - Helpers

    private func pasteItem(title: String, text: String, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: key)
        item.keyEquivalentModifierMask = []
        item.target = self
        item.representedObject = text
        item.toolTip = String(text.prefix(500))
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    static func label(_ text: String) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: " ⏎ ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.count > 50 ? String(oneLine.prefix(50)) + "…" : oneLine
    }
}
