import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreAudio
import CoreGraphics

/// Misst über ScreenCaptureKit (nur Audio, kein Video-Output) den tatsächlichen Signalpegel
/// der System-Audioausgabe, um echte Medienwiedergabe von digitaler Stille zu unterscheiden.
/// Pro-Apps wie DaVinci Resolve oder DAWs halten ihren CoreAudio-Stream (`IOProc`) oft dauerhaft
/// offen und senden Nullen – `kAudioDevicePropertyDeviceIsRunningSomewhere` ist dann `true`,
/// obwohl nichts abgespielt wird.
///
/// Wird nur gezielt gestartet, solange alle Trigger-Vorbedingungen erfüllt sind (Mac wach &
/// entsperrt, AVR erreichbar & im Standby, Zielgerät aktiv), und sofort wieder gestoppt, sobald
/// ein Signal erkannt wird oder eine Vorbedingung entfällt.
@MainActor
final class AudioLevelMonitor: NSObject {
    /// Schwellwert für "echtes Audiosignal" (ca. −60 dBFS). Digitale Stille (0.0 bzw. Dither)
    /// liegt deutlich darunter.
    private static let signalThreshold: Float = 0.001

    var onAudioSignalDetected: (() -> Void)?
    var onPermissionDenied: (() -> Void)?

    private(set) var isMonitoring = false
    private(set) var permissionDenied = false

    private var stream: SCStream?
    private var generation: UInt64 = 0
    private let audioQueue = DispatchQueue(label: "local.elektronikbastler.yamahaavrcontrol.audiolevel", qos: .utility)

    func start() {
        guard !isMonitoring, !permissionDenied else { return }
        isMonitoring = true
        generation &+= 1
        let currentGen = generation

        Task { [weak self] in
            guard let self else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard self.isMonitoring, self.generation == currentGen else { return }
                guard let display = content.displays.first else {
                    self.log("Kein Display für SCContentFilter gefunden – stoppe Monitor")
                    self.stop()
                    return
                }

                let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.sampleRate = 48_000
                config.channelCount = 2
                // Minimale Video-Konfiguration (ohne Screen-Output registriert), da SCStream einen
                // gültigen Display-Filter erwartet.
                config.width = 2
                config.height = 2
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                config.showsCursor = false

                let newStream = SCStream(filter: filter, configuration: config, delegate: self)
                try newStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: self.audioQueue)
                try await newStream.startCapture()

                guard self.isMonitoring, self.generation == currentGen else {
                    try? await newStream.stopCapture()
                    return
                }
                self.stream = newStream
                self.log("Audio-Pegel-Überwachung gestartet")
            } catch {
                guard self.isMonitoring, self.generation == currentGen else { return }
                if let scError = error as? SCStreamError, scError.code == .userDeclined {
                    self.permissionDenied = true
                    self.log("Berechtigung für Systemaudioaufnahme nicht erteilt – falle auf Stream-Status zurück")
                    self.stop()
                    self.onPermissionDenied?()
                } else {
                    self.log("Start fehlgeschlagen: \(error.localizedDescription)")
                    self.stop()
                }
            }
        }
    }

    func stop() {
        guard isMonitoring || stream != nil else { return }
        isMonitoring = false
        generation &+= 1
        let activeStream = stream
        stream = nil
        if let activeStream {
            Task {
                try? await activeStream.stopCapture()
            }
            log("Audio-Pegel-Überwachung gestoppt")
        }
    }

    private func handleDetectedSignal() {
        guard isMonitoring else { return }
        stop()
        onAudioSignalDetected?()
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("YamahaAVRControl [AudioLevel]: \(message)\n".utf8))
    }
}

extension AudioLevelMonitor: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.log("Stream unerwartet gestoppt: \(error.localizedDescription)")
            self.isMonitoring = false
            self.stream = nil
        }
    }
}

extension AudioLevelMonitor: SCStreamOutput {
    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        guard let peak = Self.peakAmplitude(from: sampleBuffer), peak > Self.signalThreshold else { return }

        Task { @MainActor [weak self] in
            guard let self, self.stream === stream else { return }
            self.handleDetectedSignal()
        }
    }

    private nonisolated static func peakAmplitude(from sampleBuffer: CMSampleBuffer) -> Float? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else {
            return nil
        }

        var bufferListSizeNeeded = 0
        let sizeStatus = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &bufferListSizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard sizeStatus == noErr, bufferListSizeNeeded > 0 else { return nil }

        let rawMemory = UnsafeMutableRawPointer.allocate(
            byteCount: bufferListSizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawMemory.deallocate() }
        let audioBufferListPtr = rawMemory.bindMemory(to: AudioBufferList.self, capacity: 1)

        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferListPtr,
            bufferListSize: bufferListSizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferListPtr)
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInt = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0
        var maxPeak: Float = 0

        for buffer in buffers {
            guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
            if isFloat && asbd.mBitsPerChannel == 32 {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size
                let samples = data.bindMemory(to: Float.self, capacity: count)
                for i in 0..<count {
                    let v = abs(samples[i])
                    if v > maxPeak { maxPeak = v }
                }
            } else if isSignedInt && asbd.mBitsPerChannel == 16 {
                let count = Int(buffer.mDataByteSize) / MemoryLayout<Int16>.size
                let samples = data.bindMemory(to: Int16.self, capacity: count)
                let scale = 1.0 / Float(Int16.max)
                for i in 0..<count {
                    let v = abs(Float(samples[i])) * scale
                    if v > maxPeak { maxPeak = v }
                }
            }
        }
        return maxPeak
    }
}
