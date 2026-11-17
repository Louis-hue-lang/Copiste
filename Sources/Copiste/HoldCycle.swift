import AppKit

/// Cycle « ⌘ maintenu + V » (option, désactivée par défaut).
///
/// - ⌘V rapide : collage normal (le ⌘V est retenu jusqu'au relâchement de V, puis renvoyé tel quel).
/// - ⌘V maintenu ~0,35 s : un panneau liste l'historique ; chaque appui sur V avance (⇧V recule),
///   relâcher ⌘ colle l'élément choisi, Échap annule, ⌫ supprime l'élément.
/// Nécessite l'autorisation Accessibilité (comme le reste de Copiste).
final class HoldCycle {
    static let defaultsKey = "holdCycleEnabled"
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: defaultsKey) }

    static let delayKey = "holdCycleDelay"
    static let defaultDelay = 0.35
    static let delayRange = 0.2...1.5
    /// Durée de maintien avant l'ouverture du panneau (réglable, relue à chaque appui).
    private var holdDelay: TimeInterval {
        let saved = UserDefaults.standard.object(forKey: Self.delayKey) as? Double ?? Self.defaultDelay
        return min(max(saved, Self.delayRange.lowerBound), Self.delayRange.upperBound)
    }
    private enum State { case idle, pending, cycling }

    private let history: ClipboardHistory
    private let panel = CyclePanel()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var holdTimer: Timer?
    private var state = State.idle
    private var index = 0

    private let kV = 9, kEscape = 53, kDelete = 51

    init(history: ClipboardHistory) { self.history = history }

    /// Active ou coupe le cycle selon le réglage. Réessaie tant que l'autorisation manque.
    func setEnabled(_ on: Bool) {
        retryTimer?.invalidate()
        retryTimer = nil
        if !on { stop(); return }
        if start() { return }
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.start() else { return }
            timer.invalidate()
        }
    }

    @discardableResult
    private func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<HoldCycle>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type, event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask), callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        runLoopSource = source
        return true
    }

    private func stop() {
        reset()
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil
        runLoopSource = nil
    }

    /// Retour à l'état de repos, sans coller.
    private func reset() {
        holdTimer?.invalidate()
        holdTimer = nil
        state = .idle
        panel.hide()
    }

    // MARK: - Événements

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            reset()
            return pass
        }
        // Nos propres ⌘V synthétiques (et ceux de Paster) ne doivent pas être interceptés.
        if event.getIntegerValueField(.eventSourceUserData) == Paster.marker { return pass }

        let flags = event.flags
        let key = Int(event.getIntegerValueField(.keyboardEventKeycode))

        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            switch state {
            case .idle:
                let plainCommand = flags.contains(.maskCommand)
                    && !flags.contains(.maskShift) && !flags.contains(.maskAlternate) && !flags.contains(.maskControl)
                guard key == kV, plainCommand, !isRepeat, !history.items.isEmpty else { return pass }
                state = .pending
                holdTimer = Timer.scheduledTimer(withTimeInterval: holdDelay, repeats: false) { [weak self] _ in
                    self?.openPanel()
                }
                return nil
            case .pending:
                if key == kV { return nil }
                // Une autre touche arrive avant la fin du délai : on rend d'abord son ⌘V à l'app.
                cancelPending(sendPaste: true, flags: flags)
                return pass
            case .cycling:
                guard !isRepeat else { return nil }
                if key == kV { move(flags.contains(.maskShift) ? -1 : 1) }
                else if key == kEscape { reset() }
                else if key == kDelete { deleteCurrent() }
                return nil
            }

        case .keyUp:
            switch state {
            case .pending where key == kV:
                cancelPending(sendPaste: true, flags: flags)
                return nil
            case .cycling:
                return nil
            default:
                return pass
            }

        case .flagsChanged:
            if !flags.contains(.maskCommand) {
                switch state {
                case .pending: cancelPending(sendPaste: true, flags: flags.union(.maskCommand))
                case .cycling: finish()
                case .idle: break
                }
            }
            return pass

        default:
            return pass
        }
    }

    private func cancelPending(sendPaste: Bool, flags: CGEventFlags) {
        holdTimer?.invalidate()
        holdTimer = nil
        state = .idle
        if sendPaste { Self.postCommandV(flags: flags) }
    }

    // MARK: - Panneau

    private func openPanel() {
        guard state == .pending else { return }
        state = .cycling
        index = 0
        panel.show(items: history.items, pinnedCount: history.pinned.count, selected: index)
    }

    private func move(_ delta: Int) {
        let count = history.items.count
        guard count > 0 else { return }
        index = (index + delta + count) % count
        panel.show(items: history.items, pinnedCount: history.pinned.count, selected: index)
    }

    private func deleteCurrent() {
        let items = history.items
        guard items.indices.contains(index) else { return }
        history.remove(items[index])
        let rest = history.items
        if rest.isEmpty { reset(); return }
        index = min(index, rest.count - 1)
        panel.show(items: rest, pinnedCount: history.pinned.count, selected: index)
    }

    private func finish() {
        let items = history.items
        let chosen = items.indices.contains(index) ? items[index] : nil
        reset()
        if let chosen { Paster.paste(chosen, history: history) }
    }

    /// Renvoie un ⌘V ordinaire à l'app au premier plan (marqué pour ne pas être réintercepté).
    private static func postCommandV(flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.userData = Paster.marker
        let combined = CGEventFlags(rawValue: flags.rawValue | CGEventFlags.maskCommand.rawValue)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        down?.flags = combined
        up?.flags = combined
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

/// Petit panneau flottant qui ne prend pas le focus : l'app visée garde la main.
final class CyclePanel {
    private var panel: NSPanel?
    private let stack = NSStackView()
    private let maxRows = 9

    func show(items: [String], pinnedCount: Int, selected: Int) {
        if panel == nil { build() }
        guard let panel else { return }
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Fenêtre glissante de 9 lignes autour de l'élément choisi.
        let start = max(0, min(selected - maxRows / 2, max(0, items.count - maxRows)))
        for i in start..<min(items.count, start + maxRows) {
            stack.addArrangedSubview(row(text: items[i], pinned: i < pinnedCount, selected: i == selected))
        }
        let hint = NSTextField(labelWithString: "V suivant · ⇧V précédent · ⌫ supprimer · Échap annuler · relâcher ⌘ pour coller")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)

        panel.contentView?.layoutSubtreeIfNeeded()
        let size = stack.fittingSize
        panel.setContentSize(NSSize(width: max(380, size.width + 24), height: size.height + 20))
        if !panel.isVisible { position(panel) }
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    /// Export de visuel (--snapshot).
    func snapshot(items: [String], pinnedCount: Int, selected: Int) -> NSImage? {
        show(items: items, pinnedCount: pinnedCount, selected: selected)
        panel?.orderOut(nil)
        guard let view = panel?.contentView else { return nil }
        view.layoutSubtreeIfNeeded()
        view.frame = NSRect(origin: .zero, size: panel!.frame.size)
        view.layoutSubtreeIfNeeded()
        return Snapshot.image(of: view)
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        var origin = NSPoint(x: mouse.x + 12, y: mouse.y - panel.frame.height - 12)
        origin.x = min(max(origin.x, area.minX + 8), area.maxX - panel.frame.width - 8)
        origin.y = min(max(origin.y, area.minY + 8), area.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(origin)
    }

    private func build() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let content = NSVisualEffectView()
        content.material = .hudWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 12
        content.layer?.masksToBounds = true

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
        ])
        panel.contentView = content
        self.panel = panel
    }

    private func row(text: String, pinned: Bool, selected: Bool) -> NSView {
        let symbol = pinned ? "pin.fill" : ClipKind.detect(text).symbol
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = selected ? .white : .secondaryLabelColor
        let label = NSTextField(labelWithString: SnippetMenu.label(text))
        label.lineBreakMode = .byTruncatingTail
        label.textColor = selected ? .white : .labelColor
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 6
        box.layer?.backgroundColor = selected ? NSColor.controlAccentColor.cgColor : NSColor.clear.cgColor
        for v in [icon, label] { v.translatesAutoresizingMaskIntoConstraints = false; box.addSubview(v) }
        box.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 376),
            box.heightAnchor.constraint(equalToConstant: 26),
            icon.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 8),
            icon.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(lessThanOrEqualTo: box.trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }
}
