import Foundation
import AppKit

/// Schaltet den AVR automatisch ein und wechselt auf einen festgelegten Eingang, sobald am Mac
/// ein bestimmtes Audioausgabegerät als Standardausgabe aktiv wird (z. B. wenn der AVR selbst
/// als AirPlay-/USB-/HDMI-Ausgabegerät im Lautsprecher-Menü ausgewählt wird).
@MainActor
final class AudioTriggerController: NSObject, ObservableObject {
    @Published var availableAudioDevices: [AudioOutputMonitor.AudioDevice] = []

    private let monitor = AudioOutputMonitor()
    private let settings: SettingsStore
    private weak var avrController: AVRController?
    private var isCurrentlyOnTargetDevice = false

    init(settings: SettingsStore, avrController: AVRController) {
        self.settings = settings
        self.avrController = avrController
        super.init()
        availableAudioDevices = monitor.refreshDevices()

        monitor.onDefaultOutputChanged = { [weak self] device in
            self?.handleChange(device)
        }
        // Direkt beim Start prüfen, falls der Mac schon auf das Zielgerät eingestellt ist.
        handleChange(monitor.currentDefaultOutputDevice())

        // Bewusst screensDidWake statt didWake: macOS wacht während des Schlafs regelmäßig kurz
        // für Hintergrundaufgaben auf ("Power Nap"/"dark wake", z. B. Time Machine, Mail-Abruf),
        // wobei didWakeNotification ebenfalls feuert, der Bildschirm aber aus bleibt. Reagierte
        // die App darauf, schaltete sich der AVR sporadisch während des Schlafs des Mac ein –
        // screensDidWake feuert nur bei einem "echten", vom Nutzer bemerkten Aufwachen.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleScreensWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func refreshDevices() {
        availableAudioDevices = monitor.refreshDevices()
    }

    @objc private func handleScreensWake() {
        // Erzwingt hier (und nur hier, bei einem echten Aufwachen) einen erneuten Trigger, auch
        // wenn das Zielgerät die ganze Zeit über als Standardausgabe eingestellt blieb – der AVR
        // selbst geht im Schlafmodus des Mac oft in Standby, ohne dass sich an der
        // macOS-Geräteauswahl etwas ändert. Absichtlich NICHT beim bloßen Schlafengehen
        // zurückgesetzt, sonst würde ein vereinzeltes, während eines Dark Wake unverändert erneut
        // gemeldetes CoreAudio-Ereignis fälschlich wie eine neue Geräteauswahl aussehen.
        isCurrentlyOnTargetDevice = false
        handleChange(monitor.currentDefaultOutputDevice())
    }

    @objc private func handleSleep() {
        // Steht der AVR gerade auf dem für dieses MacBook konfigurierten Eingang, gehört er beim
        // Schlafengehen des Mac mit ausgeschaltet – der Mac ist dann ja auch nicht mehr die
        // Tonquelle. Andere Eingänge (z. B. wenn gerade jemand anderes Radio hört) bleiben unberührt.
        if settings.triggerEnabled, !settings.triggerInput.isEmpty,
           avrController?.status?.input == settings.triggerInput {
            avrController?.turnOff()
        }
    }

    private func handleChange(_ device: AudioOutputMonitor.AudioDevice?) {
        guard settings.triggerEnabled, !settings.triggerDeviceUID.isEmpty else {
            isCurrentlyOnTargetDevice = false
            return
        }

        let matchesTarget = device?.id == settings.triggerDeviceUID
        if matchesTarget && !isCurrentlyOnTargetDevice {
            avrController?.turnOnAndSelectInput(settings.triggerInput)
        }
        isCurrentlyOnTargetDevice = matchesTarget
    }
}
