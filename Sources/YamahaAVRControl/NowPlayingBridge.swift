import Foundation
import MediaPlayer

/// Spiegelt den Wiedergabestatus des AVR (Netzwerk-Radio/USB/Bluetooth) in das systemeigene
/// "Jetzt läuft"-Widget der macOS Control Center und an die Medientasten der Tastatur (F7–F9).
/// Hinweis: Das steuert NICHT die System-Lautstärke des Mac – die Ausgabelautstärke wird
/// weiterhin ausschließlich über das App-Flyout geregelt, da der AVR kein Audioausgabegerät
/// des Mac ist.
@MainActor
final class NowPlayingBridge {
    private let controller: AVRController

    init(controller: AVRController) {
        self.controller = controller
        setupRemoteCommands()
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.controller.playbackAction("play")
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.controller.playbackAction("pause")
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            let isPlaying = self?.controller.playInfo?.playback == "play"
            self?.controller.playbackAction(isPlaying ? "pause" : "play")
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.controller.playbackAction("next")
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.controller.playbackAction("previous")
            return .success
        }
    }

    func update(with playInfo: AVRPlayInfo?) {
        guard let playInfo, let title = playInfo.displayTitle else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [MPMediaItemPropertyTitle: title]
        if let subtitle = playInfo.displaySubtitle {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = playInfo.playback == "play" ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
