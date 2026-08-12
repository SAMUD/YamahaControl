import Foundation

/// Schaltet den AVR automatisch ein und wechselt auf einen festgelegten Eingang, sobald am Mac
/// ein bestimmtes Audioausgabegerät als Standardausgabe aktiv wird (z. B. wenn der AVR selbst
/// als AirPlay-/USB-/HDMI-Ausgabegerät im Lautsprecher-Menü ausgewählt wird).
@MainActor
final class AudioTriggerController: ObservableObject {
    @Published var availableAudioDevices: [AudioOutputMonitor.AudioDevice] = []

    private let monitor = AudioOutputMonitor()
    private let settings: SettingsStore
    private weak var avrController: AVRController?
    private var isCurrentlyOnTargetDevice = false

    init(settings: SettingsStore, avrController: AVRController) {
        self.settings = settings
        self.avrController = avrController
        availableAudioDevices = monitor.refreshDevices()

        monitor.onDefaultOutputChanged = { [weak self] device in
            self?.handleChange(device)
        }
        // Direkt beim Start prüfen, falls der Mac schon auf das Zielgerät eingestellt ist.
        handleChange(monitor.currentDefaultOutputDevice())
    }

    func refreshDevices() {
        availableAudioDevices = monitor.refreshDevices()
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
