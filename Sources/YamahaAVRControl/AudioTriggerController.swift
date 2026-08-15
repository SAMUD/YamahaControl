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

        // CoreAudio meldet beim Aufwachen aus dem Schlaf keine Änderung des Standard-
        // Ausgabegeräts, wenn dieses schon vorher eingestellt war – der AVR selbst geht im
        // Schlafmodus des Mac aber oft in Standby. Deshalb nach dem Aufwachen erneut prüfen und
        // (falls weiterhin das Zielgerät aktiv ist) den AVR erneut einschalten.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
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

    @objc private func handleWake() {
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
        // Erzwingt beim nächsten Aufwachen einen erneuten Trigger, auch wenn das Zielgerät die
        // ganze Zeit über als Standardausgabe eingestellt blieb.
        isCurrentlyOnTargetDevice = false
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
