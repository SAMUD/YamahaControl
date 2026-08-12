import Foundation
import Combine

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
    }
}
