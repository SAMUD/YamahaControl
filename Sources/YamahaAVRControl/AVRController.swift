import Foundation

/// Zieleingänge, für die zusätzlich der Wiedergabestatus (Titel/Sender, Play/Pause) abgefragt wird.
private let playbackCapableInputs = ["net_radio", "usb", "server", "bluetooth", "spotify", "airplay", "tidal", "qobuz"]

@MainActor
final class AVRController: ObservableObject {
    @Published var isReachable: Bool = false
    @Published var status: AVRStatus?
    @Published var playInfo: AVRPlayInfo?
    @Published var features: AVRFeatures?
    @Published var availableInputs: [String] = []
    @Published var scenes: [AVRScene] = []
    @Published var presets: [AVRPresetEntry] = []
    @Published var lastErrorMessage: String?

    var nowPlayingBridge: NowPlayingBridge?

    private var client: AVRClient
    private var pollTask: Task<Void, Never>?
    let settings: SettingsStore

    var volumePercent: Double {
        guard let status, let volume = status.volume else { return 0 }
        let maxV = status.maxVolume ?? features?.mainVolumeRange?.max ?? 100
        guard maxV > 0 else { return 0 }
        return Double(volume) / Double(maxV)
    }

    init(settings: SettingsStore) {
        self.settings = settings
        self.client = AVRClient(host: settings.avrHost)
        startPolling()
    }

    func updateHost(_ host: String) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.avrHost = trimmed
        client.host = trimmed
        features = nil
        Task { await refreshAll() }
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollOnce()
                let interval = max(2, self.settings.pollIntervalSeconds)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func pollOnce() async {
        guard !settings.avrHost.isEmpty else {
            isReachable = false
            return
        }
        do {
            let s = try await client.getStatus()
            status = s
            isReachable = true
            lastErrorMessage = nil

            if features == nil {
                await loadFeatures()
            }

            if let input = s.input, playbackCapableInputs.contains(where: { input.contains($0) }) {
                playInfo = try? await client.getPlayInfo()
            } else {
                playInfo = nil
            }
            nowPlayingBridge?.update(with: playInfo)
        } catch {
            isReachable = false
            playInfo = nil
        }
    }

    func loadFeatures() async {
        do {
            let f = try await client.getFeatures()
            features = f
            availableInputs = f.mainZone?.inputList ?? []
            scenes = f.mainZone?.sceneList ?? []
        } catch {
            // Optionale Zusatzinfos – kein Abbruch, falls das Gerät getFeatures nicht liefert.
        }
    }

    func refreshAll() async {
        await pollOnce()
        await loadFeatures()
    }

    // MARK: Aktionen

    /// Wird von der Audiogeräte-Automatik aufgerufen: AVR einschalten (falls nötig) und danach
    /// auf den angegebenen Eingang wechseln. Der AVR braucht nach dem Einschalten kurz Zeit,
    /// bevor er weitere Befehle zuverlässig annimmt.
    func turnOnAndSelectInput(_ input: String) {
        guard !input.isEmpty else { return }
        Task {
            do {
                if status?.power != "on" {
                    try await client.setPower(true)
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                }
                try await client.setInput(input)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func togglePower() {
        let turningOn = !(status?.power == "on")
        Task {
            do {
                try await client.setPower(turningOn)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func setVolumePercent(_ pct: Double) {
        let maxV = status?.maxVolume ?? features?.mainVolumeRange?.max ?? 100
        let clamped = min(max(pct, 0), 1)
        let target = Int((clamped * Double(maxV)).rounded())
        Task {
            do {
                try await client.setVolume(target)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func toggleMute() {
        let target = !(status?.mute ?? false)
        Task {
            do {
                try await client.setMute(target)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func selectInput(_ input: String) {
        Task {
            do {
                try await client.setInput(input)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func recallScene(_ scene: AVRScene) {
        guard let str = scene.str else { return }
        Task {
            do {
                try await client.setScene(str)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func recallPreset(_ num: Int) {
        Task {
            do {
                try await client.recallPreset(num)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func playbackAction(_ action: String) {
        Task {
            do {
                try await client.setPlayback(action)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func loadPresetsIfNeeded() {
        guard presets.isEmpty else { return }
        Task {
            do {
                let list = try await client.getPresetInfo().presetInfo
                presets = list.enumerated().map { index, entry in
                    var e = entry
                    e.id = index + 1
                    return e
                }
            } catch {
                // Presets sind optional – still fehlschlagen.
            }
        }
    }

    private func reportError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }
}
