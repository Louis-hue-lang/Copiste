import AppKit
import Combine

/// Copiste dans AlyNotch (onglet « Extensions ») : derniers éléments copiés, pré-copies, actions rapides.
/// Facultatif : sans AlyNotch, le client réessaie en silence toutes les 5 s et rien ne change pour Copiste.
final class NotchBridge {
    static let defaultsKey = "alynotchEnabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: defaultsKey) as? Bool ?? true }

    private let store: SnippetStore
    private let history: ClipboardHistory
    private let openSettings: () -> Void
    private var notch: AlyNotchExtension?
    private var storeChanges: AnyCancellable?
    private var refreshPending = false
    /// Textes de l'historique tels qu'affichés, pour retrouver celui qui est cliqué.
    private var shownHistory: [String] = []

    init(store: SnippetStore, history: ClipboardHistory, openSettings: @escaping () -> Void) {
        self.store = store
        self.history = history
        self.openSettings = openSettings
    }

    func setEnabled(_ enabled: Bool) {
        enabled ? start() : stop()
    }

    private func start() {
        guard notch == nil else { return }
        let notch = AlyNotchExtension(id: "fr.louisclauzier.copiste", name: "Copiste", symbol: "list.clipboard",
                                      repository: "Louis-hue-lang/Copiste")
        notch.onEvent = { [weak self] event in self?.handle(event) }
        self.notch = notch
        storeChanges = store.objectWillChange.sink { [weak self] _ in self?.scheduleRefresh() }
        history.onChange = { [weak self] in self?.scheduleRefresh() }
        refresh()
        notch.start()
    }

    private func stop() {
        guard let notch else { return }
        notch.stop()
        self.notch = nil
        storeChanges = nil
        history.onChange = nil
    }

    // MARK: - Panneau

    /// Regroupe les changements rapprochés (frappe dans l'éditeur, copies successives).
    private func scheduleRefresh() {
        guard !refreshPending else { return }
        refreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshPending = false
            self?.refresh()
        }
    }

    private func refresh() {
        guard let notch else { return }
        typealias Item = AlyNotchExtension.Item
        var items: [Item] = []

        shownHistory = Array(history.items.prefix(3))
        if shownHistory.isEmpty {
            items.append(.text(id: "history-empty", title: "Rien de copié pour l'instant",
                               subtitle: "Ce que tu copies apparaîtra ici.", symbol: "clock"))
        }
        for (i, text) in shownHistory.enumerated() {
            items.append(.row(id: "history:\(i)", title: SnippetMenu.label(text), subtitle: i == 0 ? "Dernière copie" : nil,
                              symbol: "clock", detail: "Copier"))
        }

        items.append(.divider(id: "divider"))

        let snippets = store.folders.flatMap { folder in folder.snippets.map { (folder, $0) } }
        if snippets.isEmpty {
            items.append(.text(id: "snippets-empty", title: "Aucune pré-copie", symbol: "text.quote"))
        }
        for (folder, snippet) in snippets.prefix(4) {
            items.append(.row(id: "snippet:\(snippet.id.uuidString)",
                              title: snippet.title.isEmpty ? SnippetMenu.label(snippet.content) : snippet.title,
                              subtitle: folder.name.isEmpty ? nil : folder.name,
                              symbol: snippet.rtf == nil ? "text.quote" : "textformat", detail: "Copier"))
        }

        items.append(.button(id: "manage", title: "Gérer les pré-copies", symbol: "folder", prominent: true))
        if !shownHistory.isEmpty {
            items.append(.button(id: "clear-history", title: "Vider l'historique", symbol: "trash"))
        }
        notch.setView(title: "Copiste", items: items)
    }

    // MARK: - Événements

    private func handle(_ event: AlyNotchExtension.Event) {
        switch (event.type, event.item) {
        case ("opened", _):
            refresh()
        case ("action", "manage"?):
            openSettings()
        case ("action", "clear-history"?):
            history.clear()
        case ("action", let item?) where item.hasPrefix("history:"):
            guard let i = Int(item.dropFirst("history:".count)), shownHistory.indices.contains(i) else { return }
            copy(text: shownHistory[i], rtf: nil)
        case ("action", let item?) where item.hasPrefix("snippet:"):
            guard let id = UUID(uuidString: String(item.dropFirst("snippet:".count))),
                  let snippet = store.folders.lazy.flatMap(\.snippets).first(where: { $0.id == id }) else { return }
            copy(text: snippet.content, rtf: snippet.rtf, title: snippet.title)
        default:
            break
        }
    }

    /// Copie sans coller : le clic a lieu dans le notch, l'app cible n'a pas forcément le focus.
    private func copy(text: String, rtf: Data?, title: String = "") {
        RichText.write(text: text, rtf: rtf)
        history.ignoreCurrent()
        notch?.showBanner(title: "Copié dans le presse-papier",
                          subtitle: title.isEmpty ? SnippetMenu.label(text) : title,
                          symbol: "checkmark.circle.fill", duration: 2)
    }
}
