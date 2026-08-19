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
    /// True zwischen willSleep und dem nächsten echten (Bildschirm-)Aufwachen. CoreAudio meldet
    /// während des Schlafs gelegentlich eigenständig einen Wechsel des Standard-Ausgabegeräts
    /// (z. B. wenn eine AirPlay-Route bei einem kurzen Dark-Wake neu aufgebaut und dabei kurz das
    /// Zielgerät erneut als Default gemeldet wird) – unabhängig von jeder Wake-Notification. Der
    /// vorherige Fix sicherte nur den expliziten Wake-Handler gegen Dark-Wakes ab, nicht diesen
    /// Callback selbst, weshalb der AVR trotzdem sporadisch im Schlaf anging. Während dieses Flags
    /// wird jede Geräteänderung ignoriert; nach dem echten Aufwachen wird einmal gezielt neu geprüft.
    private var isAsleep = false

    init(settings: SettingsStore, avrController: AVRController) {
        self.settings = settings
        self.avrController = avrController
        super.init()
        availableAudioDevices = monitor.refreshDevices()

        monitor.onOutputActivityChanged = { [weak self] device, isRunning in
            self?.handleChange(device, isRunning: isRunning)
        }
        // Direkt beim Start prüfen, falls der Mac schon auf das Zielgerät eingestellt ist und
        // dort bereits aktiv etwas läuft.
        handleChange(monitor.currentDefaultOutputDevice(), isRunning: monitor.currentDefaultOutputIsRunning())

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
        logTrigger("screensDidWake – Sperre aufgehoben, prüfe Zielgerät neu")
        // Erzwingt hier (und nur hier, bei einem echten Aufwachen) einen erneuten Trigger, auch
        // wenn das Zielgerät die ganze Zeit über als Standardausgabe eingestellt blieb – der AVR
        // selbst geht im Schlafmodus des Mac oft in Standby, ohne dass sich an der
        // macOS-Geräteauswahl etwas ändert. Absichtlich NICHT beim bloßen Schlafengehen
        // zurückgesetzt, sonst würde ein vereinzeltes, während eines Dark Wake unverändert erneut
        // gemeldetes CoreAudio-Ereignis fälschlich wie eine neue Geräteauswahl aussehen.
        isAsleep = false
        isCurrentlyOnTargetDevice = false
        handleChange(monitor.currentDefaultOutputDevice(), isRunning: monitor.currentDefaultOutputIsRunning())
    }

    @objc private func handleSleep() {
        logTrigger("willSleep – sperre Auto-Trigger bis zum echten Aufwachen")
        isAsleep = true
        // Steht der AVR gerade auf dem für dieses MacBook konfigurierten Eingang, gehört er beim
        // Schlafengehen des Mac mit ausgeschaltet – der Mac ist dann ja auch nicht mehr die
        // Tonquelle. Andere Eingänge (z. B. wenn gerade jemand anderes Radio hört) bleiben unberührt.
        if settings.triggerEnabled, !settings.triggerInput.isEmpty,
           avrController?.status?.input == settings.triggerInput {
            avrController?.turnOff()
        }
    }

    private func handleChange(_ device: AudioOutputMonitor.AudioDevice?, isRunning: Bool) {
        // Während des Schlafs komplett ignorieren: CoreAudio meldet gelegentlich unabhängig von
        // jeder Wake-Notification (z. B. bei einer kurz neu aufgebauten AirPlay-Route während
        // eines Dark Wake) das Zielgerät erneut als Default, obwohl der Mac weiterhin schläft. Der
        // Zustand wird beim echten Aufwachen ohnehin über handleScreensWake neu bewertet.
        guard !isAsleep else {
            logTrigger("Geräteänderung während Schlaf ignoriert (\(device?.name ?? "kein Gerät"))")
            return
        }
        guard settings.triggerEnabled, !settings.triggerDeviceUID.isEmpty else {
            isCurrentlyOnTargetDevice = false
            return
        }

        // Bewusst nicht schon auslösen, sobald das Zielgerät nur als Standardausgabe ausgewählt
        // ist – das passiert z. B. schon beim bloßen Einstecken einer Dockingstation zum Laden,
        // ganz ohne dass etwas abgespielt wird. Erst wenn dort tatsächlich Ton läuft
        // (kAudioDevicePropertyDeviceIsRunningSomewhere), heißt das "der Nutzer macht aktiv etwas".
        let matchesTarget = device?.id == settings.triggerDeviceUID && isRunning
        if matchesTarget && !isCurrentlyOnTargetDevice {
            logTrigger("Zielgerät aktiv am Spielen (\(device?.name ?? "?")) – schalte AVR ein")
            avrController?.turnOnAndSelectInput(settings.triggerInput)
        }
        isCurrentlyOnTargetDevice = matchesTarget
    }

    private func logTrigger(_ message: String) {
        FileHandle.standardError.write(Data("YamahaAVRControl [AudioTrigger]: \(message)\n".utf8))
    }
}
