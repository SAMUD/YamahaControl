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

/// Antwort von "netusb/getListInfo": ein Ausschnitt des aktuell angezeigten Navigationsmenüs
/// (z. B. Net-Radio-Ordnerstruktur "Radio ▸ Favoriten ▸ <Sender>"). Anders als die klassischen,
/// nummerierten Presets (AVRPresetEntry/AVRPresetInfo) bildet das die im vTuner-Menü angelegten
/// Senderfavoriten ab.
struct AVRListInfo: Decodable {
    var menuLayer: Int?
    var menuName: String?
    var listInfo: [AVRListItem]

    enum CodingKeys: String, CodingKey {
        case menuLayer = "menu_layer"
        case menuName = "menu_name"
        case listInfo = "list_info"
    }

    /// Eigene Decodierung, weil der AVR bei einer momentanen Fehlerantwort (z. B. während der
    /// Inhalt eines Ordners wie "Favoriten" noch über einen externen Dienst nachgeladen wird, mit
    /// `response_code` ungleich 0) das Feld "list_info" komplett weglässt – verifiziert an einem
    /// echten Gerät. Ohne diesen Fallback bricht das Decodieren dann ab, statt es einfach als
    /// "noch keine Daten" zu werten und erneut abzufragen.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        menuLayer = try container.decodeIfPresent(Int.self, forKey: .menuLayer)
        menuName = try container.decodeIfPresent(String.self, forKey: .menuName)
        listInfo = try container.decodeIfPresent([AVRListItem].self, forKey: .listInfo) ?? []
    }
}

struct AVRListItem: Codable, Identifiable {
    var text: String?
    /// Position innerhalb der aktuellen Liste – wird nach dem Decodieren aus der Array-Position
    /// gesetzt, da die API selbst keinen Index pro Eintrag mitliefert. Bewusst nicht in
    /// CodingKeys, sonst versucht der Decoder ein nicht existierendes "index"-Feld aus der
    /// JSON-Antwort zu lesen und bricht für jeden Listeneintrag ab.
    var index: Int = 0

    enum CodingKeys: String, CodingKey {
        case text
    }

    var id: Int { index }
}

/// Szene, wie sie in der App angezeigt wird. Die YXC-API liefert (jedenfalls auf am RX-A2070
/// verifizierten Firmwareständen) keine benannten Szenen über getFeatures, nur die Anzahl
/// (`scene_num`) – die Buttons werden daher clientseitig als "Szene 1".."Szene N" erzeugt und per
/// Nummer über `recallScene?num=N` aufgerufen (verifiziert an einem echten Gerät).
struct AVRScene: Identifiable, Hashable {
    var num: Int
    var text: String

    var id: Int { num }
}

struct VolumeRange: Codable {
    var id: String?
    // Als Double, weil der AVR im "range_step"-Array auch Nicht-Lautstärke-Einträge liefert
    // (z. B. "actual_volume_db" mit min -80.5/max 16.5/step 0.5) – mit Int schlug das komplette
    // Decodieren von getFeatures bisher fehl, wodurch Eingänge/Szenen nie geladen wurden.
    var min: Double?
    var max: Double?
    var step: Double?
}

struct AVRFeatureZone: Codable {
    var id: String?
    var inputList: [String]?
    var rangeSteps: [VolumeRange]?
    /// Anzahl fest programmierter Szenen am Gerät (die YXC-API liefert dazu keine Namen).
    var sceneNum: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case inputList = "input_list"
        case rangeSteps = "range_step"
        case sceneNum = "scene_num"
    }
}

struct AVRFeatures: Codable {
    var zone: [AVRFeatureZone]?

    var mainZone: AVRFeatureZone? { zone?.first(where: { $0.id == "main" }) }
    var mainVolumeRange: VolumeRange? { mainZone?.rangeSteps?.first(where: { $0.id == "volume" }) }
}
