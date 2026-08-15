import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var controller: AVRController
    @EnvironmentObject var settings: SettingsStore
    @State private var showSettings = false
    @State private var volumeSlider: Double = 0
    @State private var isDraggingVolume = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if settings.demoModeEnabled {
                controlsView
            } else if settings.avrHost.isEmpty {
                emptyHostPrompt
            } else if !controller.isReachable {
                unreachableView
            } else {
                controlsView
            }

            Divider()

            footer

            if showSettings {
                SettingsView()
            }
        }
        .padding(16)
        .frame(width: 300)
        .onAppear {
            volumeSlider = controller.volumePercent
            // Sofort aktualisieren statt auf den nächsten periodischen Poll zu warten – sonst
            // kann das Flyout kurz nach dem Öffnen noch den letzten (u. U. veralteten) Stand
            // zeigen, z. B. wenn der Eingang zwischenzeitlich direkt am Gerät gewechselt wurde.
            Task { await controller.pollOnce() }
        }
        .onChange(of: controller.volumePercent) { newValue in
            if !isDraggingVolume { volumeSlider = newValue }
        }
    }

    // MARK: Header / Footer

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(headerIconColor)
                Image(systemName: "hifispeaker.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(settings.demoModeEnabled ? "Yamaha AVR · Demo" : "Yamaha AVR")
                    .font(.system(size: 13, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var headerIconColor: Color {
        guard controller.isReachable else { return .secondary }
        return controller.status?.power == "on" ? .accentColor : .secondary
    }

    private var statusText: String {
        if settings.demoModeEnabled {
            return controller.status?.power == "on" ? (controller.status?.inputText ?? "Eingeschaltet") : "Standby"
        }
        guard !settings.avrHost.isEmpty else { return "Nicht eingerichtet" }
        guard controller.isReachable else { return "Nicht erreichbar" }
        if controller.status?.power == "on" {
            return controller.status?.inputText ?? "Eingeschaltet"
        }
        return "Standby"
    }

    private var footer: some View {
        HStack {
            Button {
                showSettings.toggle()
            } label: {
                Text(showSettings ? "Fertig" : "Einstellungen")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Beenden")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .font(.system(size: 11))
    }

    // MARK: States

    private var emptyHostPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Noch keine Verbindung eingerichtet", systemImage: "wifi.exclamationmark")
                .font(.system(size: 12, weight: .medium))
            Text("Öffne die Einstellungen und trage die IP-Adresse deines Yamaha AVR ein.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Einstellungen öffnen") { showSettings = true }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var unreachableView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("AVR nicht erreichbar", systemImage: "wifi.slash")
                .font(.system(size: 12, weight: .medium))
            Text(settings.avrHost)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Controls

    private var controlsView: some View {
        VStack(alignment: .leading, spacing: 14) {
            powerRow
            volumeSection

            if !settings.favoriteInputs.isEmpty || !controller.availableInputs.isEmpty {
                inputSection
            }

            if !controller.scenes.isEmpty {
                sceneSection
            }

            if let playInfo = controller.playInfo {
                playbackSection(playInfo)
            }

            if let error = controller.lastErrorMessage {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
        }
    }

    private var powerRow: some View {
        Toggle(isOn: powerBinding) {
            Label("Eingeschaltet", systemImage: "power")
                .font(.system(size: 12, weight: .medium))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var powerBinding: Binding<Bool> {
        Binding(
            get: { controller.status?.power == "on" },
            set: { _ in controller.togglePower() }
        )
    }

    /// Obergrenze für den Schieberegler: mindestens die eingestellte Sicherheits-Obergrenze,
    /// aber nie kleiner als die tatsächlich am AVR eingestellte Lautstärke (falls die z. B. per
    /// Fernbedienung höher gesetzt wurde), damit der Regler den echten Wert nie abschneidet.
    private var sliderUpperBound: Double {
        max(settings.maxVolumeCap, volumeSlider, 0.05)
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Lautstärke")
            HStack(spacing: 10) {
                Button {
                    controller.toggleMute()
                } label: {
                    Image(systemName: controller.status?.mute == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.status?.mute == true ? Color.red : Color.primary)

                VolumeSliderControl(
                    value: $volumeSlider,
                    range: 0...sliderUpperBound,
                    onEditingChanged: { editing in isDraggingVolume = editing },
                    onChange: { newValue in
                        controller.setVolumePercent(newValue)
                    },
                    onCommit: { newValue in
                        controller.setVolumePercent(newValue, immediate: true)
                    }
                )
                .frame(height: 20)

                Text("\(Int(volumeSlider * 100))%")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionHeader("Quelle")
                Spacer()
                if !controller.availableInputs.isEmpty {
                    Menu {
                        ForEach(controller.availableInputs, id: \.self) { input in
                            Button {
                                controller.selectInput(input)
                            } label: {
                                if controller.status?.input == input {
                                    Label(inputLabel(input), systemImage: "checkmark")
                                } else {
                                    Text(inputLabel(input))
                                }
                            }
                        }
                    } label: {
                        Label("Alle", systemImage: "list.bullet")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            if !settings.favoriteInputs.isEmpty {
                HStack(spacing: 6) {
                    ForEach(settings.favoriteInputs, id: \.self) { input in
                        let selected = controller.status?.input == input
                        Button {
                            controller.selectInput(input)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: inputIcon(for: input))
                                    .font(.system(size: 15))
                                Text(inputLabel(input))
                                    .font(.system(size: 9))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selected ? Color.accentColor : Color.primary)
                        .background(
                            selected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                }
            }
        }
    }

    private var sceneSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Szenen")
            HStack(spacing: 6) {
                ForEach(controller.scenes) { scene in
                    Button(scene.text) {
                        controller.recallScene(scene)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func playbackSection(_ playInfo: AVRPlayInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Wiedergabe")

            if playInfo.displayTitle != nil || playInfo.displaySubtitle != nil {
                VStack(alignment: .leading, spacing: 1) {
                    if let title = playInfo.displayTitle {
                        Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    if let subtitle = playInfo.displaySubtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }

            HStack(spacing: 32) {
                Spacer()
                Button { controller.playbackAction("previous") } label: {
                    Image(systemName: "backward.fill")
                }
                Button { controller.playbackAction(playInfo.playback == "play" ? "pause" : "play") } label: {
                    Image(systemName: playInfo.playback == "play" ? "pause.fill" : "play.fill")
                        .font(.system(size: 17))
                }
                Button { controller.playbackAction("next") } label: {
                    Image(systemName: "forward.fill")
                }
                Spacer()
            }
            .buttonStyle(.plain)
            .font(.system(size: 14))

            if playInfo.input == "net_radio" {
                Menu {
                    if !configuredPresets.isEmpty {
                        ForEach(configuredPresets) { preset in
                            Button(preset.text ?? "Preset \(preset.id)") {
                                controller.recallPreset(preset.id)
                            }
                        }
                    } else if !controller.netRadioFavorites.isEmpty {
                        ForEach(controller.netRadioFavorites) { item in
                            Button(item.text ?? "Sender") {
                                controller.playNetRadioFavorite(item)
                            }
                        }
                    } else {
                        Text("Keine gespeicherten Sender").foregroundStyle(.secondary)
                    }
                } label: {
                    Label("Sender wählen", systemImage: "list.bullet")
                        .font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .onAppear {
                    controller.loadPresetsIfNeeded()
                    controller.loadNetRadioFavoritesIfNeeded()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Helpers

    /// Der AVR liefert immer alle (bis zu 40) Preset-Slots, auch unbelegte – die kommen mit
    /// leerem Text ("") statt gar nicht im Array. Unbelegte Slots werden ausgeblendet, statt sie
    /// als leere Menüeinträge anzuzeigen.
    private var configuredPresets: [AVRPresetEntry] {
        controller.presets.filter { !($0.text ?? "").isEmpty }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.3)
    }

    private func inputLabel(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func inputIcon(for raw: String) -> String {
        let value = raw.lowercased()
        if value.contains("net_radio") || value.contains("tuner") {
            return "antenna.radiowaves.left.and.right"
        } else if value.contains("bluetooth") {
            return "dot.radiowaves.left.and.right"
        } else if value.contains("spotify") || value.contains("music") || value.contains("napster") {
            return "music.note"
        } else if value.contains("usb") {
            return "cable.connector"
        } else if value.contains("hdmi") {
            return "cable.connector"
        } else if value.contains("tv") {
            return "tv"
        } else if value.contains("server") || value.contains("nas") {
            return "externaldrive.connected.to.line.below"
        } else if value.contains("airplay") {
            return "airplayaudio"
        }
        return "arrow.right.circle"
    }
}
