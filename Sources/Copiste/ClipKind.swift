import AppKit

/// Type détecté d'un texte copié (icône dans le menu) et transformations proposées.
/// Tout est local et déterministe : pas d'IA.
enum ClipKind {
    case url, email, color, code, text

    static func detect(_ text: String) -> ClipKind {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil { return .url }
        if t.range(of: #"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$"#, options: .regularExpression) != nil { return .email }
        if t.range(of: #"^#([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$"#, options: .regularExpression) != nil { return .color }
        if t.contains("\n"), t.range(of: #"[{};]|=>|\bfunc\b|\bfunction\b|\bdef\b|\bimport\b"#, options: .regularExpression) != nil { return .code }
        return .text
    }

    var symbol: String {
        switch self {
        case .url: return "link"
        case .email: return "envelope"
        case .color: return "paintpalette"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "text.alignleft"
        }
    }
}

struct Transform {
    let title: String
    let apply: (String) -> String
    /// Si non nil, la transformation n'est proposée que pour ces types.
    var kinds: Set<ClipKind>? = nil
}

extension ClipKind: Hashable {}

enum Transforms {
    /// Transformations applicables à `text` (contextuelles selon son type).
    static func available(for text: String) -> [Transform] {
        let kind = ClipKind.detect(text)
        return all.filter { $0.kinds == nil || $0.kinds!.contains(kind) }
    }

    static let all: [Transform] = [
        Transform(title: "MAJUSCULES") { $0.uppercased() },
        Transform(title: "minuscules") { $0.lowercased() },
        Transform(title: "Première Lettre En Majuscule") { $0.capitalized },
        Transform(title: "Retirer les espaces en trop") { text in
            text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        },
        Transform(title: "Sur une seule ligne") { text in
            text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        },
        Transform(title: "Trier les lignes (A → Z)") { text in
            text.components(separatedBy: "\n").sorted {
                $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
            }.joined(separator: "\n")
        },
        Transform(title: "Retirer les lignes en double") { text in
            var seen = Set<String>()
            return text.components(separatedBy: "\n").filter { seen.insert($0).inserted }.joined(separator: "\n")
        },
        Transform(title: "Lien sans paramètres de suivi", apply: stripTracking, kinds: [.url]),
        Transform(title: "Couleur : hexadécimal → RGB", apply: hexToRGB, kinds: [.color]),
    ]

    private static let trackingPrefixes = ["utm_", "fbclid", "gclid", "mc_", "igshid", "ref_src", "_hsenc", "_hsmi"]

    static func stripTracking(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var comps = URLComponents(string: t) else { return text }
        comps.queryItems = comps.queryItems?.filter { item in
            !trackingPrefixes.contains { item.name.lowercased().hasPrefix($0) }
        }
        if comps.queryItems?.isEmpty == true { comps.queryItems = nil }
        return comps.string ?? text
    }

    static func hexToRGB(_ text: String) -> String {
        var hex = String(text.trimmingCharacters(in: .whitespacesAndNewlines).dropFirst())
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count >= 6, let v = UInt32(hex.prefix(6), radix: 16) else { return text }
        return "rgb(\((v >> 16) & 255), \((v >> 8) & 255), \(v & 255))"
    }
}
