import SwiftUI
import AppKit

@main
struct YamahaAVRControlApp: App {
    @StateObject private var settings: SettingsStore
    @StateObject private var controller: AVRController
    @StateObject private var audioTrigger: AudioTriggerController

    init() {
        let settingsStore = SettingsStore()
        let avrController = AVRController(settings: settingsStore)
        avrController.nowPlayingBridge = NowPlayingBridge(controller: avrController)
        let triggerController = AudioTriggerController(settings: settingsStore, avrController: avrController)

        _settings = StateObject(wrappedValue: settingsStore)
        _controller = StateObject(wrappedValue: avrController)
        _audioTrigger = StateObject(wrappedValue: triggerController)

        // Läuft als reine Menüleisten-App ohne Dock-Icon/Programmwechsler-Eintrag.
        // (Bei Auslieferung als .app-Bundle übernimmt zusätzlich LSUIElement in Info.plist diese Rolle.)
        NSApp.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(controller)
                .environmentObject(settings)
                .environmentObject(audioTrigger)
        } label: {
            MenuBarIconView(controller: controller)
        }
        .menuBarExtraStyle(.window)
    }
}
