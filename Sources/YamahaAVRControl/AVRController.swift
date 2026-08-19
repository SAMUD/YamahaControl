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
    /// Im Net-Radio-Menü des AVR unter "Radio ▸ Favoriten" (bzw. "Radio ▸ Favorites") angelegte
    /// Sender – anders als `presets`, die klassischen nummerierten Preset-Speicherplätze, die
    /// separat (und oft ungenutzt) existieren.
    @Published var netRadioFavorites: [AVRListItem] = []
    @Published var lastErrorMessage: String?

    /// Abfolge von Listen-Indizes, mit der man vom Menü-Wurzelverzeichnis aus zum zuletzt
    /// gefundenen Favoriten-Ordner navigiert (z. B. [0, 0] für "Radio" ▸ "Favoriten"). Wird beim
    /// Abspielen eines Favoriten erneut durchlaufen, weil die Navigation zwischenzeitlich wieder
    /// auf die Wurzel zurückgesetzt wird.
    private var netRadioFavoritesPath: [Int] = []
    private var isLoadingNetRadioFavorites = false
    /// True während einer mehrschrittigen Net-Radio-Menü-Navigation (Favoriten laden/abspielen).
    /// Der AVR scheint HTTP-Anfragen nicht wirklich parallel zu verarbeiten – ein Status-Poll, der
    /// mitten in die Select-Sequenz platzt, kann dort offenbar Befehle durcheinanderbringen.
    /// Solange das hier true ist, pausiert der periodische Hintergrund-Poll, damit die Sequenz die
    /// Verbindung exklusiv für sich hat.
    private var isNavigatingMenu = false

    var nowPlayingBridge: NowPlayingBridge?

    private var client: AVRClient
    private var pollTask: Task<Void, Never>?
    private var volumeSendTask: Task<Void, Never>?
    /// Zuletzt per `setVolumePercent` *angefragte* (nicht zwangsläufig vom AVR schon bestätigte)
    /// Roh-Lautstärke. Basis für `adjustVolumeByDB`, damit sich schnell aufeinanderfolgende
    /// Tastendrücke richtig aufaddieren statt wegen des Sende-Debounce vom selben, noch nicht
    /// bestätigten Stand auszugehen.
    private var lastRequestedRawVolume: Int?
    /// Anzahl aufeinanderfolgender fehlgeschlagener Abfragen. Erst nach mehreren Fehlschlägen in
    /// Folge wird "nicht erreichbar" angezeigt, damit ein einzelner verlorener Request (z. B.
    /// während der AVR gerade eine andere Anfrage verarbeitet) nicht sofort zum Flackern führt.
    private var consecutiveFailures = 0
    let settings: SettingsStore

    // MARK: Demo-Modus (simulierter AVR, keine echten Netzwerkaufrufe)

    private var demoPower = true
    private var demoVolume = 35
    private var demoMute = false
    private var demoInput = "net_radio"
    private var demoPlayback = "play"
    private var demoStationName = "Demo Radio FM"

    var volumePercent: Double {
        guard let status, let volume = status.volume else { return 0 }
        let maxV = status.maxVolume ?? Int(features?.mainVolumeRange?.max ?? 100)
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
        if settings.demoModeEnabled {
            applyDemoState()
            return
        }
        guard !settings.avrHost.isEmpty else {
            isReachable = false
            return
        }
        guard !isNavigatingMenu else { return }
        do {
            let s = try await client.getStatus()
            status = s
            isReachable = true
            consecutiveFailures = 0
            lastErrorMessage = nil

            // Solange keine Eingänge/Szenen bekannt sind, bei jedem Poll erneut versuchen – ein
            // einzelner fehlgeschlagener oder unvollständiger getFeatures-Aufruf (z. B. kurz nach
            // dem Einschalten) darf die Favoriten/Szenen nicht dauerhaft leer lassen.
            if features == nil || availableInputs.isEmpty {
                await loadFeatures()
            }

            if let input = s.input, playbackCapableInputs.contains(where: { input.contains($0) }) {
                playInfo = try? await client.getPlayInfo()
                if input.contains("net_radio") {
                    loadPresetsIfNeeded()
                    loadNetRadioFavoritesIfNeeded()
                }
            } else {
                playInfo = nil
            }
            nowPlayingBridge?.update(with: playInfo)
        } catch {
            consecutiveFailures += 1
            // Erst nach zwei Fehlschlägen in Folge als "nicht erreichbar" melden, um Flackern bei
            // vereinzelten Timeouts (z. B. während der AVR gerade eine Lautstärkeänderung verarbeitet)
            // zu vermeiden.
            if consecutiveFailures >= 2 {
                isReachable = false
                playInfo = nil
            }
        }
    }

    func loadFeatures() async {
        do {
            let f = try await client.getFeatures()
            features = f
            // Fallback auf die erste Zone, falls das Gerät keine Zone mit id == "main" meldet.
            let zone = f.mainZone ?? f.zone?.first
            availableInputs = zone?.inputList ?? []

            if let count = zone?.sceneNum, count > 0 {
                // Auf 4 begrenzt: entspricht den dedizierten SCENE-Tasten auf Fernbedienung/Gerät,
                // auch wenn das Gerät intern mehr Szenen-Speicherplätze unterstützt (scene_num).
                scenes = (1...min(count, 4)).map { AVRScene(num: $0, text: "Szene \($0)") }
            } else {
                scenes = []
            }
        } catch {
            FileHandle.standardError.write(Data("YamahaAVRControl: getFeatures fehlgeschlagen: \(error)\n".utf8))
        }
    }

    func refreshAll() async {
        await pollOnce()
        await loadFeatures()
    }

    /// Fragt den Status wiederholt ab (bis zu ~3 s), bis er eine erwartete Änderung wirklich
    /// zeigt, statt nur einmal direkt nach dem Befehl nachzusehen. Der AVR braucht nach manchen
    /// Befehlen (z. B. Eingangswechsel mit Relais-/HDMI-Umschaltung) sichtbar einen Moment, bis
    /// getStatus den neuen Wert zurückliefert – ein einzelner, zu früher Poll zeigte bislang kurz
    /// noch den alten Stand, der erst beim nächsten periodischen Poll korrigiert wurde.
    private func pollUntilConfirmed(_ isDone: @escaping (AVRStatus?) -> Bool) async {
        await pollOnce()
        var attempts = 0
        while !isDone(status), attempts < 6 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await pollOnce()
            attempts += 1
        }
    }

    /// Füllt alle veröffentlichten Eigenschaften mit plausiblen Beispieldaten, damit sich die
    /// komplette UI (Lautstärke, Eingänge, Szenen, Wiedergabe, Presets) ohne echten AVR im
    /// Netzwerk ansehen und bedienen lässt. Es werden dabei keine HTTP-Anfragen gestellt.
    private func applyDemoState() {
        isReachable = true
        lastErrorMessage = nil

        let inputList = [
            "hdmi1", "hdmi2", "hdmi3", "hdmi4", "av1", "av2",
            "net_radio", "bluetooth", "usb", "server", "tuner", "tv", "spotify", "airplay"
        ]
        if features == nil {
            let zone = AVRFeatureZone(
                id: "main",
                inputList: inputList,
                rangeSteps: [VolumeRange(id: "volume", min: 0, max: 100, step: 1)],
                sceneNum: 4
            )
            features = AVRFeatures(zone: [zone])
            availableInputs = inputList
            scenes = [
                AVRScene(num: 1, text: "Kino"),
                AVRScene(num: 2, text: "Musik")
            ]
        }
        if presets.isEmpty {
            presets = [
                AVRPresetEntry(input: "net_radio", text: "Radio Eins", id: 1),
                AVRPresetEntry(input: "net_radio", text: "Jazz FM", id: 2),
                AVRPresetEntry(input: "net_radio", text: "Klassik Radio", id: 3)
            ]
        }

        status = AVRStatus(
            power: demoPower ? "on" : "standby",
            volume: demoVolume,
            maxVolume: 100,
            mute: demoMute,
            input: demoInput,
            inputText: demoInput.replacingOccurrences(of: "_", with: " ").capitalized,
            soundProgram: nil
        )

        if demoPower, playbackCapableInputs.contains(where: { demoInput.contains($0) }) {
            playInfo = AVRPlayInfo(
                input: demoInput,
                playback: demoPlayback,
                artist: "Demo Artist",
                album: "Demo Album",
                track: "Demo Track",
                station: demoInput == "net_radio" ? demoStationName : nil,
                albumArtUrl: nil
            )
        } else {
            playInfo = nil
        }
        nowPlayingBridge?.update(with: playInfo)
    }

    // MARK: Aktionen

    /// Wird von der Audiogeräte-Automatik aufgerufen: AVR einschalten und auf den angegebenen
    /// Eingang wechseln. Tut bewusst nichts, wenn der AVR bereits an ist – läuft dort schon etwas
    /// anderes (z. B. ein Film über HDMI), soll die Automatik das nicht durch einen Eingangswechsel
    /// unterbrechen, nur weil am Mac zufällig dieses Ausgabegerät aktiv wurde.
    func turnOnAndSelectInput(_ input: String) {
        if settings.demoModeEnabled {
            guard !demoPower else { return }
            demoPower = true
            if !input.isEmpty { demoInput = input }
            applyDemoState()
            return
        }
        guard status?.power != "on" else { return }
        Task {
            do {
                try await client.setPower(true)
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                // Eingang ist optional: Wenn in den Einstellungen keiner gewählt wurde, soll die
                // Automatik den AVR trotzdem einschalten, statt komplett zu nichts zu tun.
                if !input.isEmpty {
                    try await client.setInput(input)
                    await pollUntilConfirmed { $0?.input == input }
                } else {
                    await pollUntilConfirmed { $0?.power == "on" }
                }
            } catch { reportError(error) }
        }
    }

    /// Wird von der Audiogeräte-Automatik beim Schlafengehen des Mac aufgerufen.
    func turnOff() {
        if settings.demoModeEnabled {
            demoPower = false
            applyDemoState()
            return
        }
        guard status?.power == "on" else { return }
        Task {
            do {
                try await client.setPower(false)
                await pollUntilConfirmed { $0?.power != "on" }
            } catch { reportError(error) }
        }
    }

    func togglePower() {
        if settings.demoModeEnabled {
            demoPower.toggle()
            applyDemoState()
            return
        }
        let turningOn = !(status?.power == "on")
        Task {
            do {
                try await client.setPower(turningOn)
                await pollUntilConfirmed { ($0?.power == "on") == turningOn }
            } catch { reportError(error) }
        }
    }

    /// Wird bei jeder Reglerbewegung aufgerufen. Sendet nicht bei jedem einzelnen Pixel-Schritt
    /// sofort eine Netzwerkanfrage (das überlastet den AVR beim Ziehen und führt zu Timeouts /
    /// Race-Conditions zwischen mehreren gleichzeitigen Anfragen, was den Regler hin- und
    /// herspringen lässt), sondern verwirft eine bereits wartende Anfrage und startet danach eine
    /// neue, leicht verzögerte. `immediate: true` (z. B. beim Loslassen des Reglers oder per
    /// Mausrad) sendet sofort.
    func setVolumePercent(_ pct: Double, immediate: Bool = false) {
        let maxV = status?.maxVolume ?? Int(features?.mainVolumeRange?.max ?? 100)
        let clamped = min(max(pct, 0), 1)
        let target = Int((clamped * Double(maxV)).rounded())
        lastRequestedRawVolume = target
        if settings.demoModeEnabled {
            demoVolume = target
            applyDemoState()
            return
        }
        volumeSendTask?.cancel()
        volumeSendTask = Task { [weak self] in
            guard let self else { return }
            if !immediate {
                try? await Task.sleep(nanoseconds: 90_000_000)
                if Task.isCancelled { return }
            }
            do {
                try await self.client.setVolume(target)
                if Task.isCancelled { return }
                await self.pollOnce()
            } catch {
                if !Task.isCancelled { self.reportError(error) }
            }
        }
    }

    /// Ändert die Lautstärke um den angegebenen dB-Betrag (positiv = lauter, negativ = leiser) –
    /// für die eigene Tastenkombination (⌃⌥↑/⌃⌥↓). Rechnet den dB-Wert über die vom AVR
    /// gemeldete dB-pro-Stufe-Auflösung (`actual_volume_db` aus getFeatures, an einem echten
    /// RX-A2070 verifiziert: 0,5 dB je Roh-Lautstärke-Einheit) in Roh-Lautstärke-Einheiten um.
    /// Rechnet dabei vom zuletzt *angefragten* statt zuletzt *bestätigten* Wert weiter, damit
    /// schnell aufeinanderfolgende Tastendrücke (gehaltene Taste) sich richtig aufaddieren,
    /// statt wegen des Sende-Debounce mehrfach vom selben veralteten Stand auszugehen.
    func adjustVolumeByDB(_ deltaDB: Double) {
        let maxV = status?.maxVolume ?? Int(features?.mainVolumeRange?.max ?? 100)
        guard maxV > 0 else { return }
        let base = lastRequestedRawVolume ?? status?.volume ?? 0
        let dbPerRawUnit = features?.mainZone?.rangeSteps?.first(where: { $0.id == "actual_volume_db" })?.step ?? 0.5
        guard dbPerRawUnit > 0 else { return }
        let rawStep = max(1, Int((abs(deltaDB) / dbPerRawUnit).rounded()))
        let signedStep = deltaDB >= 0 ? rawStep : -rawStep
        let newRaw = min(max(base + signedStep, 0), maxV)
        setVolumePercent(Double(newRaw) / Double(maxV), immediate: false)
    }

    func toggleMute() {
        if settings.demoModeEnabled {
            demoMute.toggle()
            applyDemoState()
            return
        }
        let target = !(status?.mute ?? false)
        Task {
            do {
                try await client.setMute(target)
                await pollUntilConfirmed { ($0?.mute ?? false) == target }
            } catch { reportError(error) }
        }
    }

    func selectInput(_ input: String) {
        if settings.demoModeEnabled {
            demoInput = input
            applyDemoState()
            return
        }
        Task {
            do {
                try await client.setInput(input)
                await pollUntilConfirmed { $0?.input == input }
            } catch { reportError(error) }
        }
    }

    func recallScene(_ scene: AVRScene) {
        if settings.demoModeEnabled {
            demoPower = true
            applyDemoState()
            return
        }
        Task {
            do {
                try await client.recallScene(scene.num)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func recallPreset(_ num: Int) {
        if settings.demoModeEnabled {
            if let preset = presets.first(where: { $0.id == num }), let text = preset.text {
                demoStationName = text
            }
            demoInput = "net_radio"
            applyDemoState()
            return
        }
        Task {
            do {
                try await client.recallPreset(num)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func playbackAction(_ action: String) {
        if settings.demoModeEnabled {
            switch action {
            case "play": demoPlayback = "play"
            case "pause": demoPlayback = "pause"
            default: break
            }
            applyDemoState()
            return
        }
        Task {
            do {
                try await client.setPlayback(action)
                await pollOnce()
            } catch { reportError(error) }
        }
    }

    func loadPresetsIfNeeded() {
        guard presets.isEmpty, !settings.demoModeEnabled else { return }
        Task {
            do {
                let list = try await client.getPresetInfo().presetInfo
                presets = list.enumerated().map { index, entry in
                    var e = entry
                    e.id = index + 1
                    return e
                }
            } catch {
                FileHandle.standardError.write(Data("YamahaAVRControl: getPresetInfo fehlgeschlagen: \(error)\n".utf8))
            }
        }
    }

    /// Sucht im Net-Radio-Menü nach einem Ordner "Favoriten"/"Favorites" (unabhängig von der
    /// Geräte-/Menüsprache) und listet dessen Inhalt. Verifiziert an einem echten RX-A2070: Die
    /// Favoriten liegen dort unter "Radio ▸ Favoriten", nicht in den klassischen Presets.
    /// Navigiert danach zurück zur Menü-Wurzel, damit der Gerätezustand unverändert bleibt (z. B.
    /// falls gerade jemand am Gerät selbst im Menü unterwegs ist).
    func loadNetRadioFavoritesIfNeeded() {
        guard netRadioFavorites.isEmpty, !isLoadingNetRadioFavorites, !settings.demoModeEnabled else { return }
        isLoadingNetRadioFavorites = true
        isNavigatingMenu = true
        Task {
            defer {
                isLoadingNetRadioFavorites = false
                isNavigatingMenu = false
            }
            do {
                netRadioLog("--- Favoriten-Suche gestartet ---")
                var path: [Int] = []
                var list = try await returnToNetRadioRoot()
                netRadioLog("Wurzel: \(describe(list))")
                // Bis zu drei Ebenen tief nach einem Ordner mit "favorit" im Namen suchen; wird er
                // nicht direkt gefunden, probeweise in den ersten Ordner der Ebene absteigen
                // (typische vTuner-Struktur: Wurzel ▸ "Radio" ▸ "Favoriten").
                for _ in 0..<3 {
                    let previousTexts = Set(list.listInfo.compactMap { $0.text })
                    if let favItem = list.listInfo.first(where: { ($0.text ?? "").lowercased().contains("favorit") }) {
                        path.append(favItem.index)
                        netRadioLog("Wähle Favoriten-Ordner an, Index \(favItem.index) (\(favItem.text ?? "?"))")
                        list = try await selectAndAwaitContent(favItem.index, previousTexts: previousTexts)
                        netRadioLog("Nach Auswahl: \(describe(list))")
                        break
                    } else if let first = list.listInfo.first {
                        path.append(first.index)
                        netRadioLog("Steige ab in Index \(first.index) (\(first.text ?? "?"))")
                        list = try await selectAndAwaitContent(first.index, previousTexts: previousTexts)
                        netRadioLog("Nach Abstieg: \(describe(list))")
                    } else {
                        break
                    }
                }
                netRadioFavoritesPath = path
                netRadioFavorites = list.listInfo
                netRadioLog("Pfad zu Favoriten: \(path), \(list.listInfo.count) Sender gefunden")
                for _ in 0..<(list.menuLayer ?? path.count) {
                    _ = try? await client.returnList()
                }
                netRadioLog("--- Favoriten-Suche beendet, zurück zur Wurzel ---")
            } catch {
                FileHandle.standardError.write(Data("YamahaAVRControl: Net-Radio-Favoriten laden fehlgeschlagen: \(error)\n".utf8))
            }
        }
    }

    func playNetRadioFavorite(_ item: AVRListItem) {
        if settings.demoModeEnabled { return }
        isNavigatingMenu = true
        Task {
            defer { isNavigatingMenu = false }
            do {
                netRadioLog("--- Sender abspielen gestartet: Ziel-Index \(item.index) (\(item.text ?? "?")), Pfad \(netRadioFavoritesPath) ---")
                var currentList = try await returnToNetRadioRoot()
                netRadioLog("Wurzel: \(describe(currentList))")
                for index in netRadioFavoritesPath {
                    let previousTexts = Set(currentList.listInfo.compactMap { $0.text })
                    netRadioLog("Wähle Index \(index) an")
                    currentList = try await selectAndAwaitContent(index, previousTexts: previousTexts)
                    netRadioLog("Nach Auswahl: \(describe(currentList))")
                }
                netRadioLog("Spiele finalen Sender-Index \(item.index) ab")
                let code = try await client.playListItem(item.index)
                netRadioLog("  response_code=\(code)")
                // Mehrfach über einige Sekunden nachschauen statt nur einmal direkt danach – das
                // Verbinden zu einem Stream braucht spürbar Zeit, ein einzelner sofortiger Check
                // sagt nichts darüber aus, ob der Wechsel am Ende wirklich ankommt.
                for i in 0..<6 {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    let p = try? await client.getPlayInfo()
                    netRadioLog("  +\(Double(i + 1) * 0.7)s: artist=\(p?.artist ?? "nil") track=\(p?.track ?? "nil") albumart=\(p?.albumArtUrl ?? "nil") playback=\(p?.playback ?? "nil")")
                }
                await pollOnce()
                netRadioLog("--- Sender abspielen beendet ---")
            } catch {
                netRadioLog("FEHLER: \(error)")
                reportError(error)
            }
        }
    }

    /// Wählt einen Menüeintrag an und wartet ggf. kurz, bis der AVR den Inhalt der neuen
    /// Menü-Ebene tatsächlich liefert. Verifiziert an einem echten Gerät: Bei Unterordnern, deren
    /// Inhalt erst über einen externen Dienst nachgeladen wird (z. B. "Favoriten"), meldet der AVR
    /// bereits eine neue Ebene, bevor der Inhalt wirklich da ist – eine feste, kurze Pause reicht
    /// dafür nicht zuverlässig aus. Bricht spätestens nach ~2,8 s ab und gibt den letzten Stand
    /// zurück, auch wenn der Inhalt sich bis dahin nicht geändert hat.
    private func selectAndAwaitContent(_ index: Int, previousTexts: Set<String>) async throws -> AVRListInfo {
        let code = try await client.selectListItem(index)
        netRadioLog("  response_code=\(code)")
        var info = try await client.getListInfo(input: "net_radio")
        var attempts = 0
        // Sowohl eine (noch) unveränderte Liste als auch eine leere Antwort (der AVR liefert bei
        // einer momentanen Fehlerantwort während des Nachladens gar keine Einträge) gelten als
        // "noch nicht bereit" und werden erneut abgefragt.
        while attempts < 8, info.listInfo.isEmpty || Set(info.listInfo.compactMap { $0.text }) == previousTexts {
            netRadioLog("  Inhalt noch unverändert (Versuch \(attempts + 1)/8), warte...")
            try? await Task.sleep(nanoseconds: 350_000_000)
            info = try await client.getListInfo(input: "net_radio")
            attempts += 1
        }
        return info
    }

    /// Kehrt zuverlässig zur echten Wurzelebene des Net-Radio-Menüs zurück, bevor eine Navigation
    /// beginnt. Der Menüzustand ist geräteseitig sitzungsübergreifend gespeichert – stand er noch
    /// (z. B. durch eine unterbrochene vorherige Navigation, manuelle Bedienung am Gerät selbst
    /// oder einen App-Neustart mitten in einer Aktion) irgendwo in einem Unterordner, würde die
    /// Ordnersuche sonst von der falschen Stelle aus starten und einen falschen Navigationspfad
    /// aufzeichnen bzw. abspielen (an einem echten Gerät genau so beobachtet).
    private func returnToNetRadioRoot() async throws -> AVRListInfo {
        // Bewusst eine feste Anzahl "return"-Aufrufe statt einer Prüfung "sind wir schon auf der
        // Wurzelebene?": Eine transiente Fehlerantwort von getListInfo (keine menu_layer-Angabe,
        // an einem echten Gerät beobachtet) ließe sich sonst fälschlich als "ja, schon dort"
        // auslegen und den Rest der Navigation von der falschen Stelle aus starten lassen.
        // "return" über die Wurzel hinaus ist harmlos (liefert lediglich eine Fehlerantwort).
        for _ in 0..<4 {
            _ = try? await client.returnList()
        }
        return try await client.getListInfo(input: "net_radio")
    }

    private func describe(_ list: AVRListInfo) -> String {
        "layer=\(list.menuLayer.map(String.init) ?? "?") name=\(list.menuName ?? "?") items=\(list.listInfo.map { $0.text ?? "?" })"
    }

    private func netRadioLog(_ message: String) {
        FileHandle.standardError.write(Data("YamahaAVRControl [NetRadio]: \(message)\n".utf8))
    }

    private func reportError(_ error: Error) {
        lastErrorMessage = error.localizedDescription
    }
}
