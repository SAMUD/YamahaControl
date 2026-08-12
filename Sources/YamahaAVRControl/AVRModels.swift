import Foundation

struct AVRStatus: Codable {
    var power: String?
    var volume: Int?
    var maxVolume: Int?
    var mute: Bool?
    var input: String?
    var inputText: String?
    var soundProgram: String?

    enum CodingKeys: String, CodingKey {
        case power, volume, mute, input
        case maxVolume = "max_volume"
        case inputText = "input_text"
        case soundProgram = "sound_program"
    }
}

struct AVRPlayInfo: Codable {
    var input: String?
    var playback: String?
    var artist: String?
    var album: String?
    var track: String?
    var station: String?
    var albumArtUrl: String?

    enum CodingKeys: String, CodingKey {
        case input, playback, artist, album, track, station
        case albumArtUrl = "albumart_url"
    }

    /// Netzwerk-Radio liefert den Sendernamen im Feld "station", andere Quellen (USB/Server) im Feld "track".
    var displayTitle: String? {
        if let station, !station.isEmpty { return station }
        if let track, !track.isEmpty { return track }
        return nil
    }

    var displaySubtitle: String? {
        let parts = [artist, album].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " – ")
    }
}

struct AVRPresetEntry: Codable, Identifiable {
    var input: String?
    var text: String?
    // Nicht Teil der API-Antwort: wird nach dem Decodieren aus der Array-Position gesetzt (1-basiert).
    var id: Int = 0

    enum CodingKeys: String, CodingKey {
        case input, text
    }
}

struct AVRPresetInfo: Codable {
    var presetInfo: [AVRPresetEntry]

    enum CodingKeys: String, CodingKey {
        case presetInfo = "preset_info"
    }
}

struct AVRScene: Codable, Identifiable, Hashable {
    /// Wert, der 1:1 als "scene_input"-Parameter an setScene geschickt wird (z.B. "Scene_1").
    var str: String?
    var text: String?

    var id: String { str ?? text ?? UUID().uuidString }
}

struct VolumeRange: Codable {
    var id: String?
    var min: Int?
    var max: Int?
    var step: Int?
}

struct AVRFeatureZone: Codable {
    var id: String?
    var inputList: [String]?
    var rangeSteps: [VolumeRange]?
    var sceneList: [AVRScene]?

    enum CodingKeys: String, CodingKey {
        case id
        case inputList = "input_list"
        case rangeSteps = "range_step"
        case sceneList = "scene_list"
    }
}

struct AVRFeatures: Codable {
    var zone: [AVRFeatureZone]?

    var mainZone: AVRFeatureZone? { zone?.first(where: { $0.id == "main" }) }
    var mainVolumeRange: VolumeRange? { mainZone?.rangeSteps?.first(where: { $0.id == "volume" }) }
}
