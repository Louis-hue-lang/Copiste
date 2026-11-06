import ServiceManagement
import SwiftUI

enum AppInfo {
    static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    static let repo = URL(string: "https://github.com/Louis-hue-lang/Copiste")!
    static let accent = Color(red: 0.36, green: 0.32, blue: 0.93)
}

enum Page: Hashable {
    case folder(UUID), general, about
}

// MARK: - Fenêtre principale

struct SettingsView: View {
    @ObservedObject var store: SnippetStore
    let history: ClipboardHistory
    @State private var page: Page?
    @State private var folderToDelete: SnippetFolder?

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } detail: {
            detail
        }
        .toolbar(removing: .sidebarToggle)
        .tint(AppInfo.accent)
        .frame(minWidth: 900, minHeight: 580)
        .onAppear {
            page = store.folders.first.map { .folder($0.id) } ?? .general
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $page) {
                Section("Dossiers") {
                    ForEach(store.folders) { folder in
                        HStack {
                            Label(folder.name.isEmpty ? "Sans nom" : folder.name, systemImage: "folder")
                            Spacer()
                            Text("\(folder.snippets.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .tag(Page.folder(folder.id))
                        .contextMenu {
                            Button("Supprimer le dossier…", role: .destructive) { folderToDelete = folder }
                        }
                    }
                    .onMove { store.folders.move(fromOffsets: $0, toOffset: $1) }
                }
                Section("Application") {
                    Label("Général", systemImage: "gearshape").tag(Page.general)
                    Label("À propos", systemImage: "info.circle").tag(Page.about)
                }
            }
            .listStyle(.sidebar)

            Divider()
            Button(action: addFolder) {
                Label("Nouveau dossier", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.borderless)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(
            "Supprimer « \(folderToDelete?.name ?? "") » ?",
            isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }),
            presenting: folderToDelete
        ) { folder in
            Button("Supprimer", role: .destructive) { deleteFolder(folder) }
        } message: { folder in
            Text(folder.snippets.isEmpty
                 ? "Le dossier est vide."
                 : "Ses \(folder.snippets.count) snippet(s) seront supprimés définitivement.")
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .folder(let id) where store.folder(id) != nil:
            FolderDetail(store: store, folderID: id, onDelete: { folderToDelete = store.folder(id) })
                .id(id)
        case .general:
            GeneralPage(history: history)
        case .about:
            AboutPage()
        default:
            ContentUnavailableView("Choisissez un dossier", systemImage: "folder",
                                   description: Text("ou créez-en un avec « Nouveau dossier »."))
        }
    }

    private func addFolder() {
        let folder = SnippetFolder(name: "Nouveau dossier")
        store.folders.append(folder)
        page = .folder(folder.id)
    }

    private func deleteFolder(_ folder: SnippetFolder) {
        page = .general
        store.folders.removeAll { $0.id == folder.id }
        page = store.folders.first.map { .folder($0.id) } ?? .general
    }
}

// MARK: - Dossier : liste des snippets + éditeur

struct FolderDetail: View {
    @ObservedObject var store: SnippetStore
    let folderID: UUID
    let onDelete: () -> Void
    @State private var snippetID: UUID?
    @State private var search = ""

    private var folder: SnippetFolder {
        store.folder(folderID) ?? SnippetFolder(name: "")
    }

    private var filtered: [Snippet] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return folder.snippets }
        return folder.snippets.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.content.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            listColumn.frame(width: 290)
            Divider()
            editor.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { snippetID = folder.snippets.first?.id }
    }

    private var listColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Nom du dossier", text: Binding(
                        get: { folder.name },
                        set: { var f = folder; f.name = $0; store.updateFolder(f) }
                    ))
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    Text(folder.snippets.count <= 1 ? "\(folder.snippets.count) snippet" : "\(folder.snippets.count) snippets")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Menu {
                    Button("Supprimer le dossier…", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            SearchField(text: $search)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)

            List(selection: $snippetID) {
                ForEach(filtered) { snippet in
                    SnippetRow(snippet: snippet)
                        .tag(snippet.id)
                        .contextMenu {
                            moveMenu(snippet.id)
                            Button("Supprimer", role: .destructive) { remove(snippet.id) }
                        }
                }
                .onMove(perform: search.isEmpty ? move : nil)
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if filtered.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "Dossier vide" : "Aucun résultat",
                        systemImage: search.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(search.isEmpty ? "Ajoutez un snippet avec le bouton +." : "")
                    )
                }
            }

            Divider()
            HStack {
                Button(action: add) { Label("Nouveau snippet", systemImage: "plus") }
                Spacer()
                Button { if let id = snippetID { remove(id) } } label: { Image(systemName: "trash") }
                    .disabled(snippetID == nil)
                    .help("Supprimer le snippet")
            }
            .buttonStyle(.borderless)
            .padding(12)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let sid = snippetID, let initial = store.snippet(sid, in: folderID) {
            SnippetEditor(snippet: Binding(
                get: { store.snippet(sid, in: folderID) ?? initial },
                set: { store.updateSnippet($0, in: folderID) }
            ))
            .id(sid)
        } else {
            ContentUnavailableView("Aucun snippet sélectionné", systemImage: "text.cursor",
                                   description: Text("Choisissez un snippet dans la liste ou créez-en un."))
        }
    }

    // MARK: Actions

    private func add() {
        var f = folder
        let snippet = Snippet(title: "Nouveau snippet", content: "")
        f.snippets.append(snippet)
        store.updateFolder(f)
        search = ""
        snippetID = snippet.id
    }

    private func remove(_ id: UUID) {
        var f = folder
        if snippetID == id { snippetID = nil }
        f.snippets.removeAll { $0.id == id }
        store.updateFolder(f)
    }

    private func move(_ offsets: IndexSet, _ destination: Int) {
        var f = folder
        f.snippets.move(fromOffsets: offsets, toOffset: destination)
        store.updateFolder(f)
    }

    @ViewBuilder
    private func moveMenu(_ id: UUID) -> some View {
        let others = store.folders.filter { $0.id != folderID }
        if !others.isEmpty {
            Menu("Déplacer vers") {
                ForEach(others) { target in
                    Button(target.name.isEmpty ? "Sans nom" : target.name) {
                        if snippetID == id { snippetID = nil }
                        store.moveSnippet(id, from: folderID, to: target.id)
                    }
                }
            }
        }
    }
}

struct SnippetRow: View {
    let snippet: Snippet

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(snippet.title.isEmpty ? "Sans titre" : snippet.title)
                .fontWeight(.medium)
                .lineLimit(1)
            Text(preview)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var preview: String {
        let text = snippet.content.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Vide" : text
    }
}

struct SnippetEditor: View {
    @Binding var snippet: Snippet
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Titre du snippet", text: $snippet.title)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 22)
                .padding(.top, 22)
            Text("Titre affiché dans le menu")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .padding(.top, 4)

            TextEditor(text: $snippet.content)
                .font(.system(size: 14))
                .lineSpacing(3)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(nsColor: .separatorColor)))
                .padding(18)

            HStack {
                Text("\(snippet.content.count) caractères")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet.content, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copié" : "Copier", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .disabled(snippet.content.isEmpty)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
        }
    }
}

struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher", text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Général

struct GeneralPage: View {
    let history: ClipboardHistory
    @State private var trusted = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var historyCleared = false
    private let refresh = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                AppHeader()

                Card("Raccourcis", systemImage: "keyboard") {
                    ShortcutRow("Ouvrir le menu", keys: ["⌥", "⌘", "V"])
                    Divider()
                    ShortcutRow("Ouvrir le menu sous la souris", keys: ["⌥", "clic droit"])
                    Divider()
                    ShortcutRow("Coller un élément de l'historique (menu ouvert)", keys: ["1", "…", "9"])
                }

                Card("Autorisation", systemImage: "lock.shield") {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: trusted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(trusted ? .green : .orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(trusted ? "Tout est prêt" : "Autorisation nécessaire").fontWeight(.semibold)
                            Text(trusted
                                 ? "Copiste peut coller pour vous et répondre au ⌥ + clic droit."
                                 : "Activez Copiste dans Réglages Système › Confidentialité et sécurité › Contrôle de l'appareil (ou Accessibilité). S'il y est déjà coché, supprimez-le avec −, ajoutez-le de nouveau, puis relancez Copiste.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        if !trusted {
                            Button("Ouvrir les Réglages") {
                                NSWorkspace.shared.open(URL(string:
                                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }

                Card("Démarrage", systemImage: "power") {
                    Toggle(isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin)) {
                        Text("Lancer Copiste à l'ouverture de session")
                    }
                    .toggleStyle(.switch)
                    if let loginError {
                        Text(loginError).font(.caption).foregroundStyle(.red)
                    }
                }

                Card("Historique", systemImage: "clock.arrow.circlepath") {
                    HStack(alignment: .center, spacing: 12) {
                        Text("Les 30 derniers textes copiés, gardés en mémoire uniquement et effacés à la fermeture. Les mots de passe des gestionnaires sont ignorés.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button(historyCleared ? "Historique vidé" : "Vider l'historique") {
                            history.clear()
                            historyCleared = true
                        }
                        .disabled(historyCleared)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onReceive(refresh) { _ in trusted = AXIsProcessTrusted() }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Impossible de modifier le lancement automatique : \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - À propos

struct AboutPage: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text("Copiste").font(.largeTitle.weight(.bold))
            Text("Version \(AppInfo.version)").foregroundStyle(.secondary)
            Text("Un historique du presse-papier et des textes favoris rangés en dossiers,\nà portée de ⌥ + clic droit.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            HStack(spacing: 10) {
                Link(destination: AppInfo.repo) {
                    Label("Code source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: AppInfo.repo.appendingPathComponent("issues")) {
                    Label("Signaler un problème", systemImage: "ladybug")
                }
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
            Text("Logiciel libre, licence MIT.").font(.caption).foregroundStyle(.tertiary).padding(.top, 6)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Composants

struct AppHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text("Copiste").font(.title.weight(.bold))
                Text("Votre presse-papier, en mieux.").foregroundStyle(.secondary)
                Text("Version \(AppInfo.version)").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }
}

struct Card<Content: View>: View {
    let title: String
    let systemImage: String
    let content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)))
        }
    }
}

struct ShortcutRow: View {
    let label: String
    let keys: [String]

    init(_ label: String, keys: [String]) {
        self.label = label
        self.keys = keys
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    if key == "…" {
                        Text("à").foregroundStyle(.secondary).font(.callout)
                    } else {
                        KeyCap(key)
                    }
                }
            }
        }
    }
}

struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .frame(minWidth: 24, minHeight: 22)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
            .shadow(color: .black.opacity(0.12), radius: 0, y: 1)
    }
}
