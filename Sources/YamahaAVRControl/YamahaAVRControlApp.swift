import SwiftUI
import AppKit

@main
struct YamahaAVRControlApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var controller: AVRController
    @StateObject private var audioTrigger: AudioTriggerController
    @StateObject private var volumeShortcuts: VolumeShortcutController
    /// Muss für die Lebensdauer der App gehalten werden, sonst greift App Nap wieder. Ohne das
    /// hier drosselt macOS die Hintergrund-Timer dieser Menüleisten-App (kein sichtbares Fenster,
    /// nie im Vordergrund), sodass der periodische AVR-Status-Poll teils erst nach sehr langer
    /// Verzögerung läuft – der Anzeige-Status (Ein/Aus, aktueller Eingang) hinkt dann hinterher,
    /// bis irgendeine App-Interaktion (z. B. Flyout öffnen) macOS kurz aus dem Nap-Zustand holt.
    // Bewusst NICHT .idleSystemSleepDisabled (bzw. .userInitiated, was das einschließt) – das
    // würde den Mac am Einschlafen hindern, was dem neuen "AVR beim Schlafengehen ausschalten"-
    // Feature direkt widerspräche. .userInitiatedAllowingIdleSystemSleep nimmt die App nur von
    // der Timer-Drosselung durch App Nap aus, lässt den Mac aber ganz normal schlafen.
    private let appNapToken = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep,
        reason: "Regelmäßige Statusabfrage des Yamaha AVR im Hintergrund"
    )

    init() {
        let settingsStore = SettingsStore()
        let avrController = AVRController(settings: settingsStore)
        avrController.nowPlayingBridge = NowPlayingBridge(controller: avrController)
        let triggerController = AudioTriggerController(settings: settingsStore, avrController: avrController)
        let volumeShortcutController = VolumeShortcutController(settings: settingsStore, avrController: avrController)

        _settings = StateObject(wrappedValue: settingsStore)
        _controller = StateObject(wrappedValue: avrController)
        _audioTrigger = StateObject(wrappedValue: triggerController)
        _volumeShortcuts = StateObject(wrappedValue: volumeShortcutController)

        // Läuft als reine Menüleisten-App ohne Dock-Icon/Programmwechsler-Eintrag.
        // (Bei Auslieferung als .app-Bundle übernimmt zusätzlich LSUIElement in Info.plist diese Rolle.)
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(controller)
                .environmentObject(settings)
                .environmentObject(audioTrigger)
                .environmentObject(volumeShortcuts)
        } label: {
            MenuBarIconView(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}
