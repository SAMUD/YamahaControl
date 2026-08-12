import Foundation
import CoreAudio

/// Beobachtet das aktuelle Standard-Audioausgabegerät von macOS (z. B. wenn der Nutzer im
/// Lautsprecher-Menü ein anderes Ausgabegerät auswählt, etwa den AVR selbst als
/// AirPlay-/USB-/HDMI-Ziel). Wird genutzt, um den AVR automatisch einzuschalten, sobald ein
/// bestimmtes Ausgabegerät aktiv wird.
final class AudioOutputMonitor {
    struct AudioDevice: Identifiable, Hashable {
        /// Persistente Geräte-UID (bleibt über Neustarts/Neuverbindungen stabil, anders als die AudioDeviceID).
        let id: String
        let name: String
    }

    var onDefaultOutputChanged: ((AudioDevice?) -> Void)?

    private let systemObjectID = kAudioObjectSystemObject
    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        startListening()
    }

    deinit {
        stopListening()
    }

    // MARK: Geräteliste

    func refreshDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(systemObjectID, &address, 0, nil, &dataSize)
        guard status == noErr, dataSize > 0 else { return [] }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &dataSize, &deviceIDs)
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID in
            guard isOutputDevice(deviceID), let uid = deviceUID(deviceID) else { return nil }
            return AudioDevice(id: uid, name: deviceName(deviceID) ?? uid)
        }
    }

    func currentDefaultOutputDevice() -> AudioDevice? {
        guard let deviceID = defaultOutputDeviceID(), let uid = deviceUID(deviceID) else { return nil }
        return AudioDevice(id: uid, name: deviceName(deviceID) ?? uid)
    }

    // MARK: Listener

    private func startListening() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            let device = self.currentDefaultOutputDevice()
            DispatchQueue.main.async {
                self.onDefaultOutputChanged?(device)
            }
        }
        listenerBlock = block
        AudioObjectAddPropertyListenerBlock(systemObjectID, &address, DispatchQueue.main, block)
    }

    private func stopListening() {
        guard let block = listenerBlock else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(systemObjectID, &address, DispatchQueue.main, block)
        listenerBlock = nil
    }

    // MARK: Low-Level-Helfer

    private func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(systemObjectID, &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    private func isOutputDevice(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        guard sizeStatus == noErr, dataSize > 0 else { return false }

        let bufferListPointer = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(dataSize))
        defer { bufferListPointer.deallocate() }
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, bufferListPointer)
        guard status == noErr else { return false }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        return bufferList.contains { $0.mNumberChannels > 0 }
    }

    private func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &uid)
        guard status == noErr else { return nil }
        return uid as String?
    }

    private func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &name)
        guard status == noErr else { return nil }
        return name as String?
    }
}
