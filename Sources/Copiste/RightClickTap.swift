import AppKit

/// Intercepte ⌥ + clic droit dans toutes les apps et l'empêche d'atteindre l'app visée,
/// pour afficher le menu de Copiste à la place. Nécessite l'autorisation Accessibilité.
final class RightClickTap {
    var onTrigger: () -> Void = {}
    private var tap: CFMachPort?
    private var swallowNextUp = false

    var isRunning: Bool { tap != nil }

    /// Renvoie false si l'autorisation Accessibilité n'est pas encore accordée.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.rightMouseUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<RightClickTap>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type, event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        // .commonModes : le tap continue de répondre pendant qu'un menu est ouvert.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        return true
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }

        case .rightMouseDown:
            let flags = event.flags
            let onlyOption = flags.contains(.maskAlternate)
                && !flags.contains(.maskCommand)
                && !flags.contains(.maskControl)
                && !flags.contains(.maskShift)
            if onlyOption {
                swallowNextUp = true
                // Asynchrone : le menu est modal et ne doit pas bloquer le callback du tap.
                DispatchQueue.main.async { [weak self] in self?.onTrigger() }
                return nil
            }

        case .rightMouseUp:
            if swallowNextUp {
                swallowNextUp = false
                return nil
            }

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
