import Foundation

struct Snippet: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    /// Texte brut (aperçu, recherche, collage sans mise en forme).
    var content: String
    /// Mise en forme (gras, italique, souligné) en RTF ; nil pour du texte simple.
    var rtf: Data? = nil
}

struct SnippetFolder: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var snippets: [Snippet] = []
}

/// Pré-copies (« snippets » dans le code) rangées en dossiers, sauvegardés en JSON dans
/// ~/Library/Application Support/Copiste/snippets.json
final class SnippetStore: ObservableObject {
    @Published var folders: [SnippetFolder] = [] {
        didSet { save() }
    }

    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Copiste", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("snippets.json")

        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([SnippetFolder].self, from: data) {
            folders = saved
        } else {
            folders = [SnippetFolder(name: "Exemples", snippets: [
                Snippet(title: "Formule de politesse", content: "Bien cordialement,\n[Votre nom]")
            ])]
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(folders) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    // MARK: - Accès par identifiant (évite les crashs d'index dans SwiftUI)

    func folder(_ id: UUID) -> SnippetFolder? {
        folders.first { $0.id == id }
    }

    func updateFolder(_ folder: SnippetFolder) {
        guard let i = folders.firstIndex(where: { $0.id == folder.id }) else { return }
        folders[i] = folder
    }

    func snippet(_ id: UUID, in folderID: UUID) -> Snippet? {
        folder(folderID)?.snippets.first { $0.id == id }
    }

    func updateSnippet(_ snippet: Snippet, in folderID: UUID) {
        guard let f = folders.firstIndex(where: { $0.id == folderID }),
              let s = folders[f].snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        folders[f].snippets[s] = snippet
    }

    func moveSnippet(_ id: UUID, from source: UUID, to target: UUID) {
        guard let f = folders.firstIndex(where: { $0.id == source }),
              let t = folders.firstIndex(where: { $0.id == target }),
              let s = folders[f].snippets.firstIndex(where: { $0.id == id }) else { return }
        var copy = folders
        let snippet = copy[f].snippets.remove(at: s)
        copy[t].snippets.append(snippet)
        folders = copy
    }
}
