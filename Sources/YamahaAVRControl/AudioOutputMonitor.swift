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

    /// Wird aufgerufen, wenn sich das Standard-Ausgabegerät ändert oder wenn auf dem *aktuellen*
    /// Standard-Ausgabegerät tatsächlich Ton zu laufen beginnt/aufhört. `isRunning` unterscheidet
    /// "ist gerade als Standardausgabe ausgewählt" (passiert z. B. schon beim bloßen Einstecken
    /// einer Dockingstation, ganz ohne dass etwas abgespielt wird) von "es läuft gerade wirklich
    /// Audio darüber" (kAudioDevicePropertyDeviceIsRunningSomewhere).
    var onOutputActivityChanged: ((AudioDevice?, Bool) -> Void)?

    private let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
    private var defaultDeviceListenerBlock: AudioObjectPropertyListenerBlock?
    private var runningListenerBlock: AudioObjectPropertyListenerBlock?
    private var observedDeviceID: AudioDeviceID?

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

    /// Läuft gerade wirklich Ton auf dem aktuellen Standard-Ausgabegerät (nicht nur: ist es
    /// ausgewählt)?
    func currentDefaultOutputIsRunning() -> Bool {
        guard let deviceID = defaultOutputDeviceID() else { return false }
        return isRunning(deviceID)
    }

    // MARK: Listener

    private func startListening() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.observeCurrentDefaultDevice()
            }
        }
        defaultDeviceListenerBlock = block
        AudioObjectAddPropertyListenerBlock(systemObjectID, &address, DispatchQueue.main, block)
        observeCurrentDefaultDevice()
    }

    private func stopListening() {
        if let block = defaultDeviceListenerBlock {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(systemObjectID, &address, DispatchQueue.main, block)
            defaultDeviceListenerBlock = nil
        }
        removeRunningListener()
    }

    /// Hängt den "läuft gerade Ton"-Beobachter auf das aktuelle Standard-Ausgabegerät um (der
    /// vorherige wird abgemeldet) und meldet den kombinierten Zustand einmal sofort.
    private func observeCurrentDefaultDevice() {
        removeRunningListener()
        guard let deviceID = defaultOutputDeviceID() else {
            onOutputActivityChanged?(nil, false)
            return
        }
        observedDeviceID = deviceID

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.observedDeviceID == deviceID else { return }
            DispatchQueue.main.async {
                self.onOutputActivityChanged?(self.currentDefaultOutputDevice(), self.isRunning(deviceID))
            }
        }
        runningListenerBlock = block
        AudioObjectAddPropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)

        onOutputActivityChanged?(currentDefaultOutputDevice(), isRunning(deviceID))
    }

    private func removeRunningListener() {
        guard let block = runningListenerBlock, let deviceID = observedDeviceID else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectRemovePropertyListenerBlock(deviceID, &address, DispatchQueue.main, block)
        runningListenerBlock = nil
        observedDeviceID = nil
    }

    private func isRunning(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running)
        return status == noErr && running != 0
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
