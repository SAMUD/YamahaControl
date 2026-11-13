import Foundation
import AppKit
import Combine
import CoreGraphics

/// Schaltet den AVR automatisch ein und wechselt auf einen festgelegten Eingang, sobald am Mac
/// ein bestimmtes Audioausgabegerät aktiv wird (z. B. wenn der AVR selbst als AirPlay-/USB-/HDMI-
/// Ausgabegerät im Lautsprecher-Menü ausgewählt wird) und tatsächlich ein hörbares Audiosignal
/// anliegt (nicht nur digitale Stille von geöffneten Pro-Apps wie DaVinci Resolve).
@MainActor
final class AudioTriggerController: NSObject, ObservableObject {
    @Published var availableAudioDevices: [AudioOutputMonitor.AudioDevice] = []

    /// Maximale Zeit seit der letzten Maus-/Tastatureingabe, damit ein automatisches Einschalten
    /// als nutzerinitiiert gilt (verhindert nächtliche Fehltrigger durch Hintergrundtasks).
    private static let maxUserIdleSeconds: TimeInterval = 180

    private let monitor = AudioOutputMonitor()
    private let audioLevelMonitor = AudioLevelMonitor()
    private let settings: SettingsStore
    private weak var avrController: AVRController?
    private var cancellables = Set<AnyCancellable>()

    private var isCurrentlyOnTargetDevice = false
    /// True zwischen willSleep und dem nächsten echten (Bildschirm-)Aufwachen.
    private var isAsleep = false
    /// True zwischen screensDidSleep und screensDidWake. Verhindert Auto-Einschalten bei
    /// ausgeschaltetem Bildschirm (Mac evtl. wegen Hintergrundtasks wach), schaltet den AVR aber
    /// bewusst NICHT aus, wenn nur der Monitor ausgeht (z. B. beim Musikhören).
    private var isDisplayAsleep = false
    /// True, solange der Sperrbildschirm aktiv bzw. die Nutzersession inaktiv ist.
    private var isScreenLocked = false

    init(settings: SettingsStore, avrController: AVRController) {
        self.settings = settings
        self.avrController = avrController
        super.init()

        availableAudioDevices = monitor.refreshDevices()
        isScreenLocked = Self.checkScreenLocked()
        isDisplayAsleep = CGDisplayIsAsleep(CGMainDisplayID()) != 0

        monitor.onOutputActivityChanged = { [weak self] device, isRunning in
            self?.handleChange(device, isRunning: isRunning)
        }
        audioLevelMonitor.onAudioSignalDetected = { [weak self] in
            self?.handleAudioSignalDetected()
        }
        audioLevelMonitor.onPermissionDenied = { [weak self] in
            self?.evaluateCurrentState()
        }

        setupObservers(avrController: avrController)
        evaluateCurrentState()
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func refreshDevices() {
        availableAudioDevices = monitor.refreshDevices()
    }

    private func setupObservers(avrController: AVRController) {
        // Auf Änderungen von AVR-Erreichbarkeit, Power-Status und Trigger-Einstellungen reagieren,
        // damit der Audio-Stream-Monitor sofort gestoppt wird, wenn der AVR nicht erreichbar oder
        // bereits eingeschaltet ist – bzw. anläuft, sobald der AVR nach dem Aufwachen erreichbar wird.
        avrController.$isReachable
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.evaluateCurrentState() }
            }
            .store(in: &cancellables)

        avrController.$status
            .map { $0?.power }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.evaluateCurrentState() }
            }
            .store(in: &cancellables)

        settings.$triggerEnabled
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.evaluateCurrentState() }
            }
            .store(in: &cancellables)

        settings.$triggerDeviceUID
            .dropFirst()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.evaluateCurrentState() }
            }
            .store(in: &cancellables)

        let wsCenter = NSWorkspace.shared.notificationCenter
        // Bewusst screensDidWake statt didWake: Dark-Wakes (Power Nap) lassen den Bildschirm aus.
        wsCenter.addObserver(self, selector: #selector(handleScreensWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(handleScreensSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(handleSessionResignActive), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        wsCenter.addObserver(self, selector: #selector(handleSessionBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        let distCenter = DistributedNotificationCenter.default()
        distCenter.addObserver(self, selector: #selector(handleScreenLocked), name: NSNotification.Name("com.apple.screenIsLocked"), object: nil)
        distCenter.addObserver(self, selector: #selector(handleScreenUnlocked), name: NSNotification.Name("com.apple.screenIsUnlocked"), object: nil)
    }

    // MARK: System-Events

    @objc private func handleScreensWake() {
        logTrigger("screensDidWake – prüfe Präsenz & Zielgerät neu")
        isAsleep = false
        isDisplayAsleep = false
        isScreenLocked = Self.checkScreenLocked()
        isCurrentlyOnTargetDevice = false
        evaluateCurrentState()
    }

    @objc private func handleScreensSleep() {
        logTrigger("screensDidSleep – pausiere Auto-Einschalten (AVR bleibt an, falls aktiv)")
        isDisplayAsleep = true
        audioLevelMonitor.stop()
    }

    @objc private func handleSleep() {
        logTrigger("willSleep – sperre Auto-Trigger bis zum echten Aufwachen")
        isAsleep = true
        audioLevelMonitor.stop()
        // Steht der AVR gerade auf dem für dieses MacBook konfigurierten Eingang, gehört er beim
        // Schlafengehen des Mac mit ausgeschaltet – der Mac ist dann ja auch nicht mehr die
        // Tonquelle. Andere Eingänge (z. B. wenn gerade jemand anderes Radio hört) bleiben unberührt.
        if settings.triggerEnabled, !settings.triggerInput.isEmpty,
           avrController?.status?.input == settings.triggerInput {
            avrController?.turnOff()
        }
    }

    @objc private func handleScreenLocked() {
        logTrigger("Bildschirm gesperrt – pausiere Auto-Trigger")
        isScreenLocked = true
        audioLevelMonitor.stop()
    }

    @objc private func handleScreenUnlocked() {
        logTrigger("Bildschirm entsperrt – prüfe Zielgerät neu")
        isScreenLocked = Self.checkScreenLocked()
        evaluateCurrentState()
    }

    @objc private func handleSessionResignActive() {
        isScreenLocked = true
        audioLevelMonitor.stop()
    }

    @objc private func handleSessionBecomeActive() {
        isScreenLocked = Self.checkScreenLocked()
        evaluateCurrentState()
    }

    // MARK: Auswertung

    private func evaluateCurrentState() {
        handleChange(monitor.currentDefaultOutputDevice(), isRunning: monitor.currentDefaultOutputIsRunning())
    }

    private func handleChange(_ device: AudioOutputMonitor.AudioDevice?, isRunning: Bool) {
        guard !isAsleep else {
            audioLevelMonitor.stop()
            return
        }
        guard !isDisplayAsleep, CGDisplayIsAsleep(CGMainDisplayID()) == 0 else {
            audioLevelMonitor.stop()
            return
        }
        guard !isScreenLocked, !Self.checkScreenLocked() else {
            audioLevelMonitor.stop()
            return
        }
        guard settings.triggerEnabled, !settings.triggerDeviceUID.isEmpty else {
            isCurrentlyOnTargetDevice = false
            audioLevelMonitor.stop()
            return
        }

        let matchesTarget = device?.id == settings.triggerDeviceUID && isRunning
        guard matchesTarget else {
            isCurrentlyOnTargetDevice = false
            audioLevelMonitor.stop()
            return
        }

        guard !isCurrentlyOnTargetDevice else {
            audioLevelMonitor.stop()
            return
        }

        // Wenn der AVR nicht erreichbar ist, darf der Audiostream ausdrücklich NICHT abgehört werden.
        guard let avr = avrController, avr.isReachable else {
            audioLevelMonitor.stop()
            return
        }

        // Ist der AVR bereits eingeschaltet, gibt es nichts zu tun und nichts abzuhören.
        if avr.status?.power == "on" {
            isCurrentlyOnTargetDevice = true
            audioLevelMonitor.stop()
            return
        }

        // Keine automatische Einschaltung, wenn am Mac schon länger keine Nutzereingabe stattfand.
        let idleSeconds = Self.secondsSinceLastUserInput()
        guard idleSeconds <= Self.maxUserIdleSeconds else {
            logTrigger("Nutzer inaktiv (\(Int(idleSeconds)) s) – ignoriere Audio-Aktivität")
            audioLevelMonitor.stop()
            return
        }

        if audioLevelMonitor.permissionDenied {
            triggerAVR(reason: "Zielgerät aktiv am Spielen (\(device?.name ?? "?"), ohne Pegelprüfung) – schalte AVR ein")
        } else {
            // Erst bei echtem Audiosignal (> Stille) einschalten, damit z. B. ein geöffnetes
            // DaVinci Resolve ohne laufendes Playback den AVR nicht sofort weckt.
            audioLevelMonitor.start()
        }
    }

    private func handleAudioSignalDetected() {
        guard !isAsleep, !isDisplayAsleep, CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }
        guard !isScreenLocked, !Self.checkScreenLocked() else { return }
        guard settings.triggerEnabled, !settings.triggerDeviceUID.isEmpty else { return }
        guard !isCurrentlyOnTargetDevice else { return }
        guard let avr = avrController, avr.isReachable, avr.status?.power != "on" else { return }
        guard monitor.currentDefaultOutputDevice()?.id == settings.triggerDeviceUID,
              monitor.currentDefaultOutputIsRunning() else { return }
        guard Self.secondsSinceLastUserInput() <= Self.maxUserIdleSeconds else { return }

        triggerAVR(reason: "Echtes Audiosignal auf Zielgerät erkannt – schalte AVR ein")
    }

    private func triggerAVR(reason: String) {
        logTrigger(reason)
        avrController?.turnOnAndSelectInput(settings.triggerInput)
        isCurrentlyOnTargetDevice = true
        audioLevelMonitor.stop()
    }

    // MARK: System-Status-Helfer

    private static func checkScreenLocked() -> Bool {
        guard let dict = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return (dict["CGSSessionScreenIsLocked"] as? Bool) == true
    }

    private static func secondsSinceLastUserInput() -> TimeInterval {
        let eventTypes: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown,
            .keyDown, .scrollWheel, .flagsChanged
        ]
        return eventTypes
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? .infinity
    }

    private func logTrigger(_ message: String) {
        FileHandle.standardError.write(Data("YamahaAVRControl [AudioTrigger]: \(message)\n".utf8))
    }
}
