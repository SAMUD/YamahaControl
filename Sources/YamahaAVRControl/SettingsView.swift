import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var controller: AVRController
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var audioTrigger: AudioTriggerController
    @State private var hostDraft: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Verbindung")
                HStack(spacing: 6) {
                    TextField("IP-Adresse, z. B. 192.168.1.50", text: $hostDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    Button("Speichern") {
                        controller.updateHost(hostDraft)
                    }
                    .controlSize(.small)
                    .disabled(hostDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Stepper("Prüfintervall: \(Int(settings.pollIntervalSeconds)) s",
                        value: $settings.pollIntervalSeconds, in: 2...60, step: 1)
                    .font(.system(size: 12))
                    .onChange(of: settings.pollIntervalSeconds) { _ in
                        controller.startPolling()
                    }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Favoriten")
                if controller.availableInputs.isEmpty {
                    Text("Verfügbar, sobald der AVR erreichbar ist.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(0..<4, id: \.self) { slot in
                        Picker("Favorit \(slot + 1)", selection: favoriteBinding(slot)) {
                            ForEach(controller.availableInputs, id: \.self) { input in
                                Text(input).tag(input)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.system(size: 12))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Lautstärke-Sicherheit")
                Stepper("Obergrenze im Regler: \(Int(settings.maxVolumeCap * 100))%",
                        value: $settings.maxVolumeCap, in: 0.1...1.0, step: 0.05)
                    .font(.system(size: 12))
                Text("Ein Klick daneben kann die Lautstärke nie über diesen Wert springen lassen.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionHeader("Automatisch einschalten")
                Toggle("Aktiv", isOn: $settings.triggerEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 12))

                Picker("Bei Audiogerät", selection: $settings.triggerDeviceUID) {
                    Text("Keins ausgewählt").tag("")
                    ForEach(audioTrigger.availableAudioDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .pickerStyle(.menu)
                .font(.system(size: 12))

                if !controller.availableInputs.isEmpty {
                    Picker("Eingang wählen", selection: $settings.triggerInput) {
                        Text("—").tag("")
                        ForEach(controller.availableInputs, id: \.self) { input in
                            Text(input).tag(input)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.system(size: 12))
                }

                HStack {
                    Text("Stellst du am Mac dieses Gerät als Audioausgabe ein, schaltet sich der AVR ein und wechselt auf den gewählten Eingang.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Button("Geräteliste aktualisieren") {
                    audioTrigger.refreshDevices()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onAppear { hostDraft = settings.avrHost }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .kerning(0.3)
    }

    private func favoriteBinding(_ slot: Int) -> Binding<String> {
        Binding(
            get: {
                slot < settings.favoriteInputs.count
                    ? settings.favoriteInputs[slot]
                    : (controller.availableInputs.first ?? "")
            },
            set: { newValue in
                var favs = settings.favoriteInputs
                while favs.count <= slot {
                    favs.append(controller.availableInputs.first ?? "")
                }
                favs[slot] = newValue
                settings.favoriteInputs = favs
            }
        )
    }
}
