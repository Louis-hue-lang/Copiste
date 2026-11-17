import AppKit

/// Panneau de recherche (⌥⌘F) : filtre en direct l'historique, les épinglés et les pré-copies.
/// Le panneau ne prend pas la main à l'app au premier plan : Entrée colle directement dedans.
final class SearchPanel: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private struct Entry {
        let title: String
        let text: String
        let rtf: Data?
        let symbol: String
        let origin: String
        /// Texte dans lequel on cherche (sans accents ni casse).
        let haystack: String
    }

    private final class KeyPanel: NSPanel {
        override var canBecomeKey: Bool { true }
    }

    private let store: SnippetStore
    private let history: ClipboardHistory
    private var panel: NSPanel?
    private let field = NSSearchField()
    private let table = NSTableView()
    private var all: [Entry] = []
    private var shown: [Entry] = []

    init(store: SnippetStore, history: ClipboardHistory) {
        self.store = store
        self.history = history
    }

    func toggle() {
        if panel?.isVisible == true { close() } else { show() }
    }

    // MARK: - Export de visuel (--snapshot)

    func snapshot(query: String) -> NSImage? {
        all = buildEntries()
        if panel == nil { buildPanel() }
        field.stringValue = query
        refilter()
        guard let view = panel?.contentView else { return nil }
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 352)
        return Snapshot.image(of: view)
    }

    // MARK: - Affichage

    private func show() {
        all = buildEntries()
        if panel == nil { buildPanel() }
        field.stringValue = ""
        refilter()
        guard let panel else { return }
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - panel.frame.width / 2, y: f.midY + f.height * 0.1))
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    private func close() {
        panel?.orderOut(nil)
    }

    private func buildPanel() {
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .closable],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        field.placeholderString = "Rechercher dans l'historique et les pré-copies…"
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 30
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(rowDoubleClicked)
        table.allowsEmptySelection = false

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let content = NSVisualEffectView()
        content.material = .hudWindow
        content.state = .active
        content.addSubview(field)
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            field.topAnchor.constraint(equalTo: content.topAnchor, constant: 34),
            field.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            field.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        panel.contentView = content
        self.panel = panel
    }

    // MARK: - Données

    private static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    private func buildEntries() -> [Entry] {
        var list: [Entry] = []
        for text in history.pinned {
            list.append(Entry(title: SnippetMenu.label(text), text: text, rtf: nil, symbol: "pin.fill",
                              origin: "Épinglé", haystack: Self.fold(text)))
        }
        for text in history.recent {
            list.append(Entry(title: SnippetMenu.label(text), text: text, rtf: nil,
                              symbol: ClipKind.detect(text).symbol, origin: "Historique", haystack: Self.fold(text)))
        }
        for folder in store.folders {
            for s in folder.snippets {
                let title = s.title.isEmpty ? SnippetMenu.label(s.content) : s.title
                list.append(Entry(title: title, text: s.content, rtf: s.rtf, symbol: "folder",
                                  origin: folder.name.isEmpty ? "Pré-copie" : folder.name,
                                  haystack: Self.fold(s.title + "\n" + s.content)))
            }
        }
        return list
    }

    private func refilter() {
        let terms = Self.fold(field.stringValue).split(separator: " ").map(String.init)
        shown = terms.isEmpty ? all : all.filter { e in terms.allSatisfy { e.haystack.contains($0) } }
        table.reloadData()
        if !shown.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false) }
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { shown.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let e = shown[row]
        let cell = NSTableCellView()
        let icon = NSImageView(image: NSImage(systemSymbolName: e.symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        let title = NSTextField(labelWithString: e.title)
        title.lineBreakMode = .byTruncatingTail
        let origin = NSTextField(labelWithString: e.origin)
        origin.textColor = .secondaryLabelColor
        origin.font = .systemFont(ofSize: 11)
        origin.setContentHuggingPriority(.required, for: .horizontal)
        origin.setContentCompressionResistancePriority(.required, for: .horizontal)
        for v in [icon, title, origin] {
            v.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(v)
        }
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            title.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            title.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            origin.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
            origin.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            origin.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    @objc private func rowDoubleClicked() { pasteSelected() }

    // MARK: - Clavier

    func controlTextDidChange(_ obj: Notification) { refilter() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)): move(1); return true
        case #selector(NSResponder.moveUp(_:)): move(-1); return true
        case #selector(NSResponder.insertNewline(_:)): pasteSelected(); return true
        case #selector(NSResponder.cancelOperation(_:)): close(); return true
        default: return false
        }
    }

    private func move(_ delta: Int) {
        guard !shown.isEmpty else { return }
        let next = max(0, min(shown.count - 1, table.selectedRow + delta))
        table.selectRowIndexes([next], byExtendingSelection: false)
        table.scrollRowToVisible(next)
    }

    private func pasteSelected() {
        let row = table.selectedRow
        guard shown.indices.contains(row) else { return }
        let e = shown[row]
        close()
        Paster.paste(e.text, rtf: e.rtf, history: history)
    }
}
