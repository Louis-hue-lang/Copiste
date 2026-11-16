// AlyNotchExtension.swift — client des extensions AlyNotch (protocole 1). Licence MIT.
// Copie ce fichier dans ton app (macOS 13+, aucune dépendance). Ton app reste indépendante :
// si AlyNotch n'est pas lancé, le client réessaie discrètement toutes les 5 secondes.

import Foundation

public final class AlyNotchExtension: @unchecked Sendable {
    public struct Item: Encodable, Sendable {
        public var id: String
        public var type: String
        public var title: String?
        public var subtitle: String?
        public var symbol: String?
        public var prominent: Bool?
        public var detail: String?

        public static func text(id: String, title: String? = nil, subtitle: String? = nil, symbol: String? = nil) -> Item {
            Item(id: id, type: "text", title: title, subtitle: subtitle, symbol: symbol)
        }
        public static func row(id: String, title: String, subtitle: String? = nil, symbol: String? = nil, detail: String? = nil) -> Item {
            Item(id: id, type: "row", title: title, subtitle: subtitle, symbol: symbol, detail: detail)
        }
        public static func button(id: String, title: String, symbol: String? = nil, prominent: Bool = false) -> Item {
            Item(id: id, type: "button", title: title, symbol: symbol, prominent: prominent)
        }
        public static func field(id: String, placeholder: String, button: String = "OK") -> Item {
            Item(id: id, type: "field", title: button, detail: placeholder)
        }
        public static func divider(id: String = UUID().uuidString) -> Item {
            Item(id: id, type: "divider")
        }
    }

    public struct BannerAction: Encodable, Sendable {
        public var id: String
        public var title: String
        public var prominent: Bool?
        public init(id: String, title: String, prominent: Bool? = nil) {
            self.id = id; self.title = title; self.prominent = prominent
        }
    }

    public struct Event: Decodable, Sendable {
        /// « action » (ligne, bouton, bouton de bannière), « submit » (champ), « opened » (panneau affiché).
        public var type: String
        public var item: String?
        public var value: String?
    }

    /// Appelé sur la file principale.
    public var onEvent: (@Sendable (Event) -> Void)?

    private let manifest: [String: String]
    private let session = URLSession(configuration: .ephemeral)
    private var connection: (base: URL, token: String)?
    private var lastView: Data?
    private var lastCompact: Data?
    private var task: Task<Void, Never>?

    public init(id: String, name: String, symbol: String? = nil, version: String? = nil, repository: String? = nil) {
        var manifest = ["id": id, "name": name]
        manifest["symbol"] = symbol
        manifest["version"] = version ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        manifest["bundleID"] = Bundle.main.bundleIdentifier
        manifest["repository"] = repository
        self.manifest = manifest
    }

    private var id: String { manifest["id"]! }

    /// Se connecte (et se reconnecte) à AlyNotch, puis attend les événements.
    public func start() {
        guard task == nil else { return }
        task = Task.detached { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await self.register()
                    if let view = self.lastView { try? await self.post("extensions/\(self.id)/view", view) }
                    if let compact = self.lastCompact { try? await self.post("extensions/\(self.id)/compact", compact) }
                    while !Task.isCancelled {
                        let events = try await self.pollEvents()
                        for event in events {
                            DispatchQueue.main.async { self.onEvent?(event) }
                        }
                    }
                } catch {
                    self.connection = nil
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        Task { try? await post("extensions/\(id)/unregister", Data()) }
    }

    public func setView(title: String? = nil, items: [Item]) {
        struct View: Encodable { var title: String?; var items: [Item] }
        guard let data = try? JSONEncoder().encode(View(title: title, items: items)) else { return }
        lastView = data
        Task { try? await post("extensions/\(id)/view", data) }
    }

    /// Indicateur près de l'encoche ; `nil` partout pour l'effacer.
    public func setCompact(symbol: String?, text: String?) {
        var object: [String: String] = [:]
        object["symbol"] = symbol
        object["text"] = text
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        lastCompact = (symbol == nil && text == nil) ? nil : data
        Task { try? await post("extensions/\(id)/compact", symbol == nil && text == nil ? Data() : data) }
    }

    public func showBanner(title: String, subtitle: String? = nil, symbol: String? = nil, actions: [BannerAction] = [], duration: Double? = nil) {
        struct Banner: Encodable { var title: String; var subtitle: String?; var symbol: String?; var actions: [BannerAction]; var duration: Double? }
        guard let data = try? JSONEncoder().encode(Banner(title: title, subtitle: subtitle, symbol: symbol, actions: actions, duration: duration)) else { return }
        Task { try? await post("extensions/\(id)/banner", data) }
    }

    private struct Failure: Error {}

    private func loadConnection() throws -> (base: URL, token: String) {
        if let connection { return connection }
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AlyNotch/extensions/connection.json")
        guard let data = try? Data(contentsOf: file),
              let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = (info["baseURL"] as? String).flatMap(URL.init(string:)),
              let token = info["token"] as? String else { throw Failure() }
        connection = (base, token)
        return (base, token)
    }

    private func register() async throws {
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try await post("register", data)
    }

    @discardableResult
    private func post(_ path: String, _ body: Data) async throws -> Data {
        let (base, token) = try loadConnection()
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue(token, forHTTPHeaderField: "X-AlyNotch-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure() }
        return data
    }

    private func pollEvents() async throws -> [Event] {
        let (base, token) = try loadConnection()
        var request = URLRequest(url: base.appendingPathComponent("extensions/\(id)/events").appending(queryItems: [URLQueryItem(name: "wait", value: "25")]))
        request.timeoutInterval = 40
        request.setValue(token, forHTTPHeaderField: "X-AlyNotch-Token")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure() }
        struct Batch: Decodable { var events: [Event] }
        return try JSONDecoder().decode(Batch.self, from: data).events
    }
}
