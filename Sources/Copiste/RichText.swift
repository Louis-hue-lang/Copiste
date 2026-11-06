import AppKit
import SwiftUI

/// Mise en forme simple des pré-copies : gras, italique, souligné.
/// Le texte est stocké en RTF ; seules ces trois mises en forme sont conservées.
enum RichText {
    static let baseFont = NSFont.systemFont(ofSize: 14)
    private static let fm = NSFontManager.shared

    /// Ne garde que gras / italique / souligné, sur la police de base.
    static func normalized(_ source: NSAttributedString, forDisplay: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString(string: source.string)
        source.enumerateAttributes(in: NSRange(location: 0, length: source.length)) { attrs, range, _ in
            var font = baseFont
            if let f = attrs[.font] as? NSFont {
                let traits = fm.traits(of: f)
                if traits.contains(.boldFontMask) { font = fm.convert(font, toHaveTrait: .boldFontMask) }
                if traits.contains(.italicFontMask) { font = fm.convert(font, toHaveTrait: .italicFontMask) }
            }
            var clean: [NSAttributedString.Key: Any] = [.font: font]
            if let u = attrs[.underlineStyle] as? Int, u != 0 { clean[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if forDisplay { clean[.foregroundColor] = NSColor.textColor }
            out.setAttributes(clean, range: range)
        }
        return out
    }

    /// Texte affiché dans l'éditeur.
    static func attributed(text: String, rtf: Data?) -> NSAttributedString {
        if let rtf, let s = try? NSAttributedString(
            data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return normalized(s, forDisplay: true)
        }
        return NSAttributedString(string: text, attributes: [.font: baseFont, .foregroundColor: NSColor.textColor])
    }

    /// RTF à enregistrer, ou nil si le texte n'a aucune mise en forme.
    static func rtf(from s: NSAttributedString) -> Data? {
        let clean = normalized(s)
        guard hasFormatting(clean) else { return nil }
        return try? clean.data(from: NSRange(location: 0, length: clean.length),
                               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
    }

    static func hasFormatting(_ s: NSAttributedString) -> Bool {
        var found = false
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attrs, _, stop in
            let traits = (attrs[.font] as? NSFont).map { fm.traits(of: $0) } ?? []
            if traits.contains(.boldFontMask) || traits.contains(.italicFontMask)
                || (attrs[.underlineStyle] as? Int ?? 0) != 0 {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// Version HTML (navigateurs, Gmail…) : balises sans police, le texte prend le style de la destination.
    static func html(fromRTF rtf: Data) -> String? {
        guard let s = try? NSAttributedString(
            data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) else { return nil }
        var html = ""
        s.enumerateAttributes(in: NSRange(location: 0, length: s.length)) { attrs, range, _ in
            var run = (s.string as NSString).substring(with: range)
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            let traits = (attrs[.font] as? NSFont).map { fm.traits(of: $0) } ?? []
            if (attrs[.underlineStyle] as? Int ?? 0) != 0 { run = "<u>\(run)</u>" }
            if traits.contains(.italicFontMask) { run = "<i>\(run)</i>" }
            if traits.contains(.boldFontMask) { run = "<b>\(run)</b>" }
            html += run
        }
        return "<meta charset=\"utf-8\">" + html
    }

    /// Écrit le texte dans le presse-papier : texte brut, plus RTF et HTML s'il est mis en forme.
    static func write(text: String, rtf: Data?, to pb: NSPasteboard = .general) {
        pb.clearContents()
        pb.setString(text, forType: .string)
        if let rtf {
            pb.setData(rtf, forType: .rtf)
            if let html = html(fromRTF: rtf) { pb.setString(html, forType: .html) }
        }
    }
}

// MARK: - Éditeur

/// Fait le lien entre les boutons de mise en forme (SwiftUI) et le NSTextView.
final class RichTextController: ObservableObject {
    weak var textView: NSTextView?
    @Published var bold = false
    @Published var italic = false
    @Published var underline = false

    private let fm = NSFontManager.shared

    func toggleBold() { toggle(.boldFontMask) }
    func toggleItalic() { toggle(.italicFontMask) }

    private func toggle(_ trait: NSFontTraitMask) {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        let convert: (NSFont, Bool) -> NSFont = { font, remove in
            remove ? self.fm.convert(font, toNotHaveTrait: trait) : self.fm.convert(font, toHaveTrait: trait)
        }
        if range.length == 0 {
            let font = tv.typingAttributes[.font] as? NSFont ?? RichText.baseFont
            tv.typingAttributes[.font] = convert(font, fm.traits(of: font).contains(trait))
        } else {
            guard let storage = tv.textStorage, tv.shouldChangeText(in: range, replacementString: nil) else { return }
            var all = true
            storage.enumerateAttribute(.font, in: range) { v, _, _ in
                if !fm.traits(of: v as? NSFont ?? RichText.baseFont).contains(trait) { all = false }
            }
            storage.beginEditing()
            storage.enumerateAttribute(.font, in: range) { v, r, _ in
                storage.addAttribute(.font, value: convert(v as? NSFont ?? RichText.baseFont, all), range: r)
            }
            storage.endEditing()
            tv.didChangeText()
        }
        tv.window?.makeFirstResponder(tv)
        refresh()
    }

    func toggleUnderline() {
        guard let tv = textView else { return }
        let range = tv.selectedRange()
        if range.length == 0 {
            let on = (tv.typingAttributes[.underlineStyle] as? Int ?? 0) != 0
            tv.typingAttributes[.underlineStyle] = on ? 0 : NSUnderlineStyle.single.rawValue
        } else {
            guard let storage = tv.textStorage, tv.shouldChangeText(in: range, replacementString: nil) else { return }
            var all = true
            storage.enumerateAttribute(.underlineStyle, in: range) { v, _, _ in
                if (v as? Int ?? 0) == 0 { all = false }
            }
            if all { storage.removeAttribute(.underlineStyle, range: range) }
            else { storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            tv.didChangeText()
        }
        tv.window?.makeFirstResponder(tv)
        refresh()
    }

    /// Met à jour l'état des boutons selon la sélection.
    func refresh() {
        guard let tv = textView, let storage = tv.textStorage else { return }
        let range = tv.selectedRange()
        var attrs: [[NSAttributedString.Key: Any]] = []
        if range.length == 0 {
            attrs = [tv.typingAttributes]
        } else {
            storage.enumerateAttributes(in: range) { a, _, _ in attrs.append(a) }
        }
        let traits = attrs.map { ($0[.font] as? NSFont).map { fm.traits(of: $0) } ?? [] }
        bold = !traits.isEmpty && traits.allSatisfy { $0.contains(.boldFontMask) }
        italic = !traits.isEmpty && traits.allSatisfy { $0.contains(.italicFontMask) }
        underline = !attrs.isEmpty && attrs.allSatisfy { ($0[.underlineStyle] as? Int ?? 0) != 0 }
    }
}

/// NSTextView qui ne garde que gras / italique / souligné quand on colle du texte venu d'ailleurs.
final class FormattedTextView: NSTextView {
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let rich = pb.readObjects(forClasses: [NSAttributedString.self])?.first as? NSAttributedString {
            let clean = RichText.normalized(rich, forDisplay: true)
            let range = selectedRange()
            if shouldChangeText(in: range, replacementString: clean.string) {
                textStorage?.replaceCharacters(in: range, with: clean)
                didChangeText()
                setSelectedRange(NSRange(location: range.location + clean.length, length: 0))
            }
        } else {
            pasteAsPlainText(sender)
        }
    }
}

struct RichTextEditor: NSViewRepresentable {
    let initial: NSAttributedString
    let controller: RichTextController
    let onChange: (NSAttributedString) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = FormattedTextView.scrollableTextView()
        // scrollableTextView() crée un NSTextView : on le remplace par notre sous-classe.
        let old = scroll.documentView as! NSTextView
        let tv = FormattedTextView(frame: old.frame, textContainer: old.textContainer)
        tv.autoresizingMask = old.autoresizingMask
        tv.minSize = old.minSize
        tv.maxSize = old.maxSize
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        scroll.documentView = tv

        tv.isRichText = true
        tv.importsGraphics = false
        tv.usesFontPanel = false
        tv.usesRuler = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 6)
        tv.textStorage?.setAttributedString(initial)
        tv.typingAttributes = [.font: RichText.baseFont, .foregroundColor: NSColor.textColor]
        tv.delegate = context.coordinator

        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        controller.textView = tv
        controller.refresh()
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.onChange(tv.attributedString())
            parent.controller.refresh()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.controller.refresh()
        }
    }
}
