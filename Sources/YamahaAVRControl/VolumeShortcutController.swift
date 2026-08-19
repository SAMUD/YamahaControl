import Foundation

/// Verbindet den globalen Tastenkombinations-Beobachter mit den Einstellungen und dem
/// AVR-Controller. Der Beobachter läuft nur, solange `settings.volumeShortcutsEnabled` aktiv ist
/// – `applyEnabledState()` muss nach jeder Änderung dieser Einstellung erneut aufgerufen werden
/// (siehe SettingsView), damit die App nicht unnötig systemweit Tastendrücke beobachtet, wenn
/// das Feature ausgeschaltet ist.
@MainActor
final class VolumeShortcutController: ObservableObject {
    /// Solange nicht `nil`, läuft gerade eine Aufnahme für "lauter" (true) oder "leiser" (false) –
    /// die Einstellungen-Ansicht kann das für ein "Drücke eine Taste…"-Label nutzen.
    @Published private(set) var isRecording: Bool? // true = lauter, false = leiser, nil = keine Aufnahme

    private let monitor = VolumeShortcutMonitor()
    private let settings: SettingsStore
    private weak var avrController: AVRController?

    init(settings: SettingsStore, avrController: AVRController) {
        self.settings = settings
        self.avrController = avrController
        monitor.onVolumeUp = { [weak self] in self?.step(up: true) }
        monitor.onVolumeDown = { [weak self] in self?.step(up: false) }
        syncCombos()
        if settings.volumeShortcutsEnabled {
            VolumeShortcutMonitor.requestAccessibilityIfNeeded()
        }
        applyEnabledState()
    }

    func applyEnabledState() {
        if settings.volumeShortcutsEnabled {
            syncCombos()
            monitor.start()
        } else {
            monitor.stop()
        }
    }

    private func syncCombos() {
        monitor.volumeUpCombo = settings.volumeUpCombo
        monitor.volumeDownCombo = settings.volumeDownCombo
    }

    func startRecording(up: Bool) {
        isRecording = up
        monitor.beginCapture { [weak self] combo in
            guard let self else { return }
            if up {
                self.settings.volumeUpCombo = combo
            } else {
                self.settings.volumeDownCombo = combo
            }
            self.isRecording = nil
            self.syncCombos()
            // Aufnahme lief unabhängig vom normalen Beobachter – ihn ggf. wieder (mit dem neuen
            // Stand) starten, falls das Feature aktiv ist.
            self.applyEnabledState()
        }
    }

    func cancelRecording() {
        monitor.endCapture()
        isRecording = nil
        applyEnabledState()
    }

    private func step(up: Bool) {
        let delta = up ? settings.volumeShortcutStepDB : -settings.volumeShortcutStepDB
        avrController?.adjustVolumeByDB(delta)
    }
}
