import Foundation

/// Champ repéré dans un texte copié (montant, date, e-mail…), pour ne coller que celui-là.
struct ClipField {
    let label: String
    let value: String
}

/// Détection locale (NSDataDetector + expressions régulières), sans IA.
enum FieldExtractor {
    private static let maxFields = 12

    static func fields(in text: String) -> [ClipField] {
        var result: [ClipField] = []
        var seen = Set<String>()
        func add(_ label: String, _ value: String) {
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !v.isEmpty, seen.insert(v).inserted, result.count < maxFields else { return }
            result.append(ClipField(label: label, value: v))
        }

        for m in matches(#"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#, in: text) { add("E-mail", m) }
        for m in matches(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,4})?\b"#, in: text) where isValidIBAN(m) {
            add("IBAN", m)
        }
        let amount = #"(?:[€$£]\s?\d[\d  .,]*\d|\d[\d  .,]*\d\s?(?:€|EUR|\$|USD|£|GBP))"#
        for m in matches(amount, in: text) { add("Montant", m) }

        // Dates écrites en toutes lettres : NSDataDetector les rate selon la langue du système.
        let fr = "janvier|février|fevrier|mars|avril|mai|juin|juillet|août|aout|septembre|octobre|novembre|décembre|decembre"
        let en = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec"
        for m in matches(#"\b\d{1,2}(?:er)? (?:"# + fr + #")\.? \d{4}\b"#, in: text) { add("Date", m) }
        for m in matches(#"\b(?:"# + en + #")[a-z]*\.? \d{1,2}(?:st|nd|rd|th)?,? \d{4}\b"#, in: text) { add("Date", m) }

        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue
                                              | NSTextCheckingResult.CheckingType.link.rawValue
                                              | NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
            let ns = text as NSString
            for r in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let part = ns.substring(with: r.range)
                switch r.resultType {
                case .phoneNumber: add("Téléphone", part)
                case .date: add("Date", part)
                case .link:
                    if let url = r.url, url.scheme == "http" || url.scheme == "https" { add("Lien", part) }
                default: break
                }
            }
        }
        return result
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    /// Contrôle modulo 97 : évite de prendre n'importe quelle suite de lettres et chiffres pour un IBAN.
    static func isValidIBAN(_ raw: String) -> Bool {
        let iban = raw.replacingOccurrences(of: " ", with: "").uppercased()
        guard (15...34).contains(iban.count) else { return false }
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for ch in rearranged {
            guard let v = ch.isNumber ? ch.wholeNumberValue : (ch.isLetter ? Int(ch.asciiValue ?? 0) - 55 : nil),
                  v >= 0 else { return false }
            for digit in String(v) { remainder = (remainder * 10 + Int(String(digit))!) % 97 }
        }
        return remainder == 1
    }
}
