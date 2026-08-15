import Foundation

enum AVRError: LocalizedError {
    case invalidURL
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Ungültige AVR-Adresse"
        case .http(let code): return "AVR antwortete mit Status \(code)"
        }
    }
}

/// Dünner Client für die Yamaha MusicCast / "YXC" HTTP-API, wie sie von aktuellen
/// und aelteren Yamaha-AV-Receivern (inkl. RX-A2070) im lokalen Netzwerk angeboten wird.
/// Referenz-Endpunkte lassen sich am Gerät direkt prüfen, z.B.:
///   http://<AVR-IP>/YamahaExtendedControl/v1/system/getFeatures
///   http://<AVR-IP>/YamahaExtendedControl/v1/main/getStatus
final class AVRClient {
    var host: String
    var timeout: TimeInterval = 3

    init(host: String) {
        self.host = host
    }

    private func url(_ path: String, query: [String: String] = [:]) -> URL? {
        var components = URLComponents()
        components.scheme = "http"
        components.host = host
        components.path = "/YamahaExtendedControl/v1" + path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }

    @discardableResult
    private func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
        guard !host.isEmpty, let url = url(path, query: query) else { throw AVRError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AVRError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return data
    }

    private func getJSON<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        let data = try await get(path, query: query)
        return try JSONDecoder().decode(T.self, from: data)
    }

    // MARK: System

    func getDeviceInfo() async throws {
        try await get("/system/getDeviceInfo")
    }

    func getFeatures() async throws -> AVRFeatures {
        try await getJSON("/system/getFeatures", as: AVRFeatures.self)
    }

    // MARK: Zone (main)

    func getStatus(zone: String = "main") async throws -> AVRStatus {
        try await getJSON("/\(zone)/getStatus", as: AVRStatus.self)
    }

    func setPower(_ on: Bool, zone: String = "main") async throws {
        try await get("/\(zone)/setPower", query: ["power": on ? "on" : "standby"])
    }

    func setVolume(_ volume: Int, zone: String = "main") async throws {
        try await get("/\(zone)/setVolume", query: ["volume": String(volume)])
    }

    func setMute(_ mute: Bool, zone: String = "main") async throws {
        try await get("/\(zone)/setMute", query: ["enable": mute ? "true" : "false"])
    }

    func setInput(_ input: String, zone: String = "main") async throws {
        try await get("/\(zone)/setInput", query: ["input": input])
    }

    /// Ruft eine gespeicherte Szene ab (1-basierte Nummer). Verifiziert an einem echten RX-A2070.
    func recallScene(_ num: Int, zone: String = "main") async throws {
        try await get("/\(zone)/recallScene", query: ["num": String(num)])
    }

    // MARK: NetUSB (Netzwerk-Radio, USB, Server, Bluetooth, Streaming-Dienste)

    func getPlayInfo() async throws -> AVRPlayInfo {
        try await getJSON("/netusb/getPlayInfo", as: AVRPlayInfo.self)
    }

    func setPlayback(_ action: String) async throws {
        try await get("/netusb/setPlayback", query: ["playback": action])
    }

    func getPresetInfo() async throws -> AVRPresetInfo {
        try await getJSON("/netusb/getPresetInfo", as: AVRPresetInfo.self)
    }

    func recallPreset(_ num: Int, zone: String = "main") async throws {
        try await get("/netusb/recallPreset", query: ["zone": zone, "num": String(num)])
    }

    /// Liest einen Ausschnitt des aktuell angezeigten Net-USB-Navigationsmenüs (z. B. Net-Radio-
    /// Ordnerstruktur). Verifiziert an einem echten RX-A2070: `list_id=main` ist fest, "index" ist
    /// der erste anzuzeigende Eintrag (0 = von vorn).
    func getListInfo(input: String, index: Int = 0, size: Int = 8, lang: String = "de") async throws -> AVRListInfo {
        var info = try await getJSON(
            "/netusb/getListInfo",
            query: ["list_id": "main", "input": input, "index": String(index), "size": String(size), "lang": lang],
            as: AVRListInfo.self
        )
        info.listInfo = info.listInfo.enumerated().map { offset, item in
            var i = item
            i.index = index + offset
            return i
        }
        return info
    }

    /// Wählt einen Eintrag der zuletzt per `getListInfo` gelesenen Liste an: Ist der Eintrag ein
    /// Ordner, navigiert das Gerät hinein; ist es ein abspielbarer Titel/Sender, wird er direkt
    /// gestartet – das Gerät entscheidet das selbst anhand des Eintrags, verifiziert an einem
    /// echten Gerät.
    func selectListItem(_ index: Int, zone: String = "main") async throws {
        try await get("/netusb/setListControl", query: ["list_id": "main", "type": "select", "index": String(index), "zone": zone])
    }

    /// Verlässt die aktuelle Menüebene wieder eine Ebene nach oben.
    func returnList(zone: String = "main") async throws {
        try await get("/netusb/setListControl", query: ["list_id": "main", "type": "return", "index": "0", "zone": zone])
    }
}
