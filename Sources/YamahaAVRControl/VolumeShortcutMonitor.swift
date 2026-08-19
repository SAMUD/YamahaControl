import AppKit
import ApplicationServices

/// Eine Tastenkombination: Tastencode + Modifier (Ctrl/Option/Cmd/Shift), z. B. für die
/// Lautstärke-Tastenkombination.
struct KeyCombo: Equatable {
    var keyCode: UInt16
    var modifierFlags: NSEvent.ModifierFlags

    /// Lesbare Darstellung, z. B. "⌃⌥↑" oder "F13".
    var displayString: String {
        var parts = ""
        if modifierFlags.contains(.control) { parts += "⌃" }
        if modifierFlags.contains(.option) { parts += "⌥" }
        if modifierFlags.contains(.shift) { parts += "⇧" }
        if modifierFlags.contains(.command) { parts += "⌘" }
        parts += Self.keyLabels[keyCode] ?? "Taste \(keyCode)"
        return parts
    }

    /// Anzeige-Namen für die gängigsten Tasten (Pfeiltasten, Buchstaben, Zahlen, Funktionstasten).
    /// Alles andere fällt auf "Taste <Code>" zurück – reicht, um zu erkennen, was aufgenommen wurde.
    private static let keyLabels: [UInt16: String] = [
        123: "←", 124: "→", 125: "↓", 126: "↑",
        49: "Leertaste", 36: "Enter", 48: "Tab", 51: "Rückschritt", 53: "Esc",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I",
        38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O", 35: "P", 12: "Q",
        15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W", 7: "X", 16: "Y", 6: "Z",
        29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9"
    ]
}

/// Beobachtet eine vom Nutzer selbst festgelegte, systemweite Tastenkombination für Lautstärke
/// rauf/runter – bewusst konfigurierbar statt einer festen Vorgabe wie ⌃⌥↑/↓, weil solche
/// Kombinationen leicht mit anderer Software kollidieren (z. B. Fenstermanager oder
/// Tastatur-Herstellersoftware, die selbst systemweit Tasten abfängt). Braucht die Berechtigung
/// „Eingabeüberwachung“ (Systemeinstellungen ▸ Datenschutz & Sicherheit) – macOS erlaubt globales
/// Beobachten von Tastendrücken nur damit. Beim allerersten Start trägt macOS die App automatisch
/// (aber deaktiviert) in diese Liste ein; der Nutzer muss sie dort manuell aktivieren.
///
/// Wichtig: Das hier ist ein reiner *Beobachter* (`NSEvent.addGlobalMonitorForEvents`), kein
/// Event-Tap – er kann eine Kombination nicht "kapern"/unterdrücken. Fängt eine andere
/// systemweit lauschende App (z. B. ein Fenstermanager oder Tastatur-Treibersoftware) dieselbe
/// Kombination bereits vorher ab, kommt sie hier nie an; das zeigt sich beim Aufnehmen dann
/// einfach dadurch, dass nichts aufgenommen wird.
final class VolumeShortcutMonitor {
    var onVolumeUp: (() -> Void)?
    var onVolumeDown: (() -> Void)?

    private var monitor: Any?
    private var localMonitor: Any?
    private var captureMonitor: Any?

    var volumeUpCombo: KeyCombo?
    var volumeDownCombo: KeyCombo?

    /// Löst die Bedienungshilfen-Freigabeaufforderung aus, falls die App noch nicht vertraut ist –
    /// genau einmal pro App-Start aufrufen (z. B. beim Erstellen des Controllers), nicht bei jedem
    /// `start()`, sonst poppt der Dialog bei jeder Aktion (z. B. jeder Kombinations-Aufnahme)
    /// erneut auf, ohne dass eine gerade erst in den Einstellungen erteilte Freigabe im laufenden
    /// Prozess schon ankäme (das braucht einen Neustart der App).
    static func requestAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        AXIsProcessTrustedWithOptions(options)
    }

    /// Braucht wie `beginCapture` sowohl einen globalen als auch einen lokalen Monitor: Ist die
    /// eigene App gerade fokussiert (z. B. das Flyout oder die Einstellungen offen), sieht ein
    /// reiner globaler Monitor die Tastendrücke nicht – die App soll aber auch dann reagieren.
    ///
    /// Wichtig (an einem echten Gerät verifiziert, in Apples eigener Doku zu
    /// `NSEvent.addGlobalMonitorForEvents` erwähnt): Für **Tastatur**-Ereignisse reicht die
    /// Berechtigung „Eingabeüberwachung“ (kTCCServiceListenEvent) allein NICHT – zusätzlich muss
    /// die App für „Bedienungshilfen“/Accessibility freigegeben sein (`AXIsProcessTrusted()`),
    /// sonst kommen die Monitor-Closures zwar (nicht-nil) zurück, feuern aber nie.
    ///
    /// Die Freigabe-Aufforderung wird bewusst nicht hier ausgelöst: `start()` läuft bei jeder
    /// Änderung (z. B. nach jeder Tastenkombinations-Aufnahme) erneut, und der laufende Prozess
    /// merkt eine frisch erteilte Freigabe ohnehin erst nach einem Neustart – ein Aufruf pro
    /// `start()` hätte den Dialog bei jeder Aktion erneut gezeigt. `requestAccessibilityIfNeeded()`
    /// übernimmt das stattdessen genau einmal.
    func start() {
        stop()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let combo = KeyCombo(keyCode: event.keyCode, modifierFlags: flags)
            guard let self, combo == self.volumeUpCombo || combo == self.volumeDownCombo else { return event }
            self.handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        localMonitor = nil
    }

    private var captureLocalMonitor: Any?

    /// Wartet auf den nächsten Tastendruck (mit mindestens einem Modifier, damit nicht aus
    /// Versehen z. B. die reine Leertaste aufgenommen wird) und liefert ihn per `completion`.
    /// Läuft unabhängig vom normalen `start()`/`stop()`-Zustand.
    ///
    /// Braucht sowohl einen globalen als auch einen lokalen Monitor: Während der Aufnahme hat
    /// meist das eigene Einstellungsfenster den Tastatur-Fokus (der Nutzer hat ja gerade erst auf
    /// „Aufnehmen“ geklickt) – dann geht der Tastendruck als *lokales* Ereignis an die eigene App,
    /// das `addGlobalMonitorForEvents` (das ausschließlich Ereignisse an *andere* Apps sieht)
    /// niemals bekäme.
    func beginCapture(completion: @escaping (KeyCombo) -> Void) {
        endCapture()
        let handler: (NSEvent) -> Void = { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.isEmpty else { return }
            self?.endCapture()
            completion(KeyCombo(keyCode: event.keyCode, modifierFlags: flags))
        }
        captureMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler)
        captureLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handler(event)
            return nil // Innerhalb der eigenen App abfangen, damit z. B. Cmd+Buchstabe keine Menübefehle auslöst.
        }
    }

    func endCapture() {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
        }
        captureMonitor = nil
        if let captureLocalMonitor {
            NSEvent.removeMonitor(captureLocalMonitor)
        }
        captureLocalMonitor = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let combo = KeyCombo(keyCode: event.keyCode, modifierFlags: flags)
        if combo == volumeUpCombo {
            onVolumeUp?()
        } else if combo == volumeDownCombo {
            onVolumeDown?()
        }
    }
}
