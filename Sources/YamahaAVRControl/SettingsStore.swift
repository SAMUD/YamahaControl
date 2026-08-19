import Foundation
import Combine
import AppKit

final class SettingsStore: ObservableObject {
    @Published var avrHost: String {
        didSet { UserDefaults.standard.set(avrHost, forKey: "avrHost") }
    }
    @Published var pollIntervalSeconds: Double {
        didSet { UserDefaults.standard.set(pollIntervalSeconds, forKey: "pollIntervalSeconds") }
    }
    @Published var favoriteInputs: [String] {
        didSet { UserDefaults.standard.set(favoriteInputs, forKey: "favoriteInputs") }
    }

    /// Sicherheits-Obergrenze für den Lautstärkeregler (0.05–1.0), damit ein versehentlicher
    /// Klick daneben nicht auf volle Lautstärke springen kann.
    @Published var maxVolumeCap: Double {
        didSet { UserDefaults.standard.set(maxVolumeCap, forKey: "maxVolumeCap") }
    }

    /// Automatik: AVR einschalten + Eingang wählen, sobald dieses macOS-Audioausgabegerät aktiv wird.
    @Published var triggerEnabled: Bool {
        didSet { UserDefaults.standard.set(triggerEnabled, forKey: "triggerEnabled") }
    }
    @Published var triggerDeviceUID: String {
        didSet { UserDefaults.standard.set(triggerDeviceUID, forKey: "triggerDeviceUID") }
    }
    @Published var triggerInput: String {
        didSet { UserDefaults.standard.set(triggerInput, forKey: "triggerInput") }
    }

    /// Simuliert einen verbundenen, eingeschalteten AVR mit Beispieldaten – rein zum Betrachten
    /// der UI, ohne echtes Gerät im Netzwerk. Es werden dabei keine Netzwerkanfragen gestellt.
    @Published var demoModeEnabled: Bool {
        didSet { UserDefaults.standard.set(demoModeEnabled, forKey: "demoModeEnabled") }
    }

    /// Systemweite, vom Nutzer selbst aufgenommene Tastenkombination zur Lautstärkesteuerung –
    /// eigene Kombination, nicht die physischen Mac-Lautstärketasten. Braucht die Berechtigung
    /// „Eingabeüberwachung“. `nil` = nicht festgelegt.
    @Published var volumeShortcutsEnabled: Bool {
        didSet { UserDefaults.standard.set(volumeShortcutsEnabled, forKey: "volumeShortcutsEnabled") }
    }
    @Published var volumeUpCombo: KeyCombo? {
        didSet { saveCombo(volumeUpCombo, keyKey: "volumeUpKeyCode", flagsKey: "volumeUpFlags") }
    }
    @Published var volumeDownCombo: KeyCombo? {
        didSet { saveCombo(volumeDownCombo, keyKey: "volumeDownKeyCode", flagsKey: "volumeDownFlags") }
    }
    /// Lautstärkeänderung pro Tastendruck, in dB.
    @Published var volumeShortcutStepDB: Double {
        didSet { UserDefaults.standard.set(volumeShortcutStepDB, forKey: "volumeShortcutStepDB") }
    }

    private func saveCombo(_ combo: KeyCombo?, keyKey: String, flagsKey: String) {
        let defaults = UserDefaults.standard
        if let combo {
            defaults.set(Int(combo.keyCode), forKey: keyKey)
            defaults.set(combo.modifierFlags.rawValue, forKey: flagsKey)
        } else {
            defaults.removeObject(forKey: keyKey)
            defaults.removeObject(forKey: flagsKey)
        }
    }

    private static func loadCombo(keyKey: String, flagsKey: String) -> KeyCombo? {
        let defaults = UserDefaults.standard
        guard let keyCode = defaults.object(forKey: keyKey) as? Int else { return nil }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: flagsKey)))
        return KeyCombo(keyCode: UInt16(keyCode), modifierFlags: flags)
    }

    init() {
        avrHost = UserDefaults.standard.string(forKey: "avrHost") ?? ""
        pollIntervalSeconds = UserDefaults.standard.object(forKey: "pollIntervalSeconds") as? Double ?? 5
        favoriteInputs = UserDefaults.standard.stringArray(forKey: "favoriteInputs")
            ?? ["hdmi1", "hdmi2", "net_radio", "bluetooth"]
        maxVolumeCap = UserDefaults.standard.object(forKey: "maxVolumeCap") as? Double ?? 0.7
        triggerEnabled = UserDefaults.standard.bool(forKey: "triggerEnabled")
        triggerDeviceUID = UserDefaults.standard.string(forKey: "triggerDeviceUID") ?? ""
        triggerInput = UserDefaults.standard.string(forKey: "triggerInput") ?? ""
        demoModeEnabled = UserDefaults.standard.bool(forKey: "demoModeEnabled")
        volumeShortcutsEnabled = UserDefaults.standard.bool(forKey: "volumeShortcutsEnabled")
        volumeUpCombo = Self.loadCombo(keyKey: "volumeUpKeyCode", flagsKey: "volumeUpFlags")
        volumeDownCombo = Self.loadCombo(keyKey: "volumeDownKeyCode", flagsKey: "volumeDownFlags")
        volumeShortcutStepDB = UserDefaults.standard.object(forKey: "volumeShortcutStepDB") as? Double ?? 0.5
    }
}
