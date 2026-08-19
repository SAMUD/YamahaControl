# YXC-API: technische Hinweise

Detailwissen zur Yamaha-Extended-Control-API (YXC / MusicCast,
`http://<AVR-IP>/YamahaExtendedControl/v1/...`), das beim Bau dieser App an
einem echten RX-A2070 herausgefunden wurde. Öffentlich dokumentiert ist davon
wenig bis nichts – gedacht als Referenz, falls hier weiterentwickelt wird oder
etwas an einem anderen Receiver-Modell abweicht.

Alle Endpunkte werden in [`AVRClient.swift`](../Sources/YamahaAVRControl/AVRClient.swift)
angesprochen.

## Szenen

`getFeatures` liefert unter `zone[].scene_num` nur die **Anzahl** programmierter
Szenen, keine Namen. Der Aufruf zum Abrufen einer Szene ist

```
GET /<zone>/recallScene?num=<1-basierte Nummer>
```

(nicht `/setScene?scene_input=...` – das liefert `response_code:3`, ungültige
Anfrage). Da keine Namen verfügbar sind, zeigt die App generisch „Szene 1“ bis
„Szene 4“.

## Netzwerk-Radio-Favoriten vs. klassische Presets

Zwei getrennte Systeme:

- **Presets** (`netusb/getPresetInfo`): feste, nummerierte Speicherplätze
  (i. d. R. 40), oft ungenutzt – leere Slots kommen als `{"input":"unknown","text":""}`
  zurück, nicht einfach fehlend.
- **Favoriten**, angelegt im On-Screen-Menü des Receivers unter „Radio ▸
  Favoriten“: liegen nicht in einer flachen Liste, sondern in der
  Menü-Navigationsstruktur. Zum Auslesen/Bedienen:

  ```
  GET /netusb/getListInfo?list_id=main&input=net_radio&index=0&size=8&lang=de
  GET /netusb/setListControl?list_id=main&type=<select|play|return>&index=<n>&zone=main
  ```

  Die App sucht darin automatisch (sprachunabhängig) nach einem Ordner mit
  „favorit“ im Namen. Bei einer anderen Menüstruktur zeigt derselbe
  `getListInfo`-Aufruf im Browser die tatsächlichen Einträge.

### `setListControl`-Typen

Drei gültige `type`-Werte, leicht zu verwechseln:

- `select` – navigiert in einen Ordner hinein bzw. markiert einen Eintrag.
  Startet **keine** Wiedergabe, auch nicht bei einem Sender/Titel – meldet
  dabei trotzdem `response_code:0` (Erfolg), was leicht als "hat funktioniert"
  fehlinterpretiert wird.
- `play` – startet tatsächlich die Wiedergabe eines Eintrags.
- `return` – eine Menüebene zurück. Über die Wurzel hinaus harmlos (liefert
  nur eine Fehlerantwort, kein Absturz).

**Timing:** Der AVR verarbeitet `setListControl`-Aufrufe nicht wirklich
parallel/beliebig schnell hintereinander:

- Zu kurz aufeinanderfolgende Aufrufe liefern `response_code:4`.
- Bei Ordnern, deren Inhalt über einen externen Dienst nachgeladen wird (z. B.
  „Favoriten“), kann `getListInfo` bereits die neue `menu_layer` melden,
  bevor der tatsächliche Inhalt da ist – ein sofortiger Folge-Request sieht
  dann noch die alte Liste. Zuverlässiger: nach jedem Navigationsschritt
  erneut abfragen, bis sich der Inhalt wirklich vom vorherigen unterscheidet
  (Timeout statt fester Wartezeit).
- Der Menü-Navigationszustand ist geräteseitig sitzungsübergreifend
  gespeichert (übersteht App-Neustarts). Vor einer Navigation lohnt es sich,
  mehrfach `return` zu senden, um garantiert auf der echten Wurzelebene zu
  starten.

### Verifikation ist trickreich

Der reguläre Sender, der vorher lief, kann selbst sehr unterschiedliche
Inhalte spielen (Wortbeiträge und Musik im Wechsel) – ein anderer Songtitel
in `getPlayInfo.track` beweist noch **keinen** echten Senderwechsel. Verlässlich
ist ein Vergleich von `getPlayInfo.artist`/`.albumart_url` vor und nach dem
Wechsel.

## `getFeatures`: `range_step` kann Kommazahlen enthalten

Neben Ganzzahl-Einträgen wie `volume` (`min`/`max`/`step` als Int) liefert das
Gerät z. B. `"actual_volume_db": {"min": -80.5, "max": 16.5, "step": 0.5}`.
Ein Codable-Modell mit `Int`-Feldern lässt das **komplette** Decodieren von
`getFeatures` fehlschlagen (nicht nur das einzelne Feld) – entsprechend
müssen `min`/`max`/`step` in `VolumeRange` als `Double` modelliert sein.

## Transiente Fehlerantworten

`getListInfo` kann während eines Ladevorgangs kurzzeitig nur
`{"response_code": <ungleich 0>}` liefern, komplett ohne `list_info`-Feld.
Ein Codable-Modell, das `list_info` als Pflichtfeld erwartet, wirft dabei eine
`DecodingError` (`"The data couldn't be read because it is missing"`) – das
Feld sollte beim Fehlen als leeres Array behandelt werden, nicht als Fehler.

## Status-Änderungen brauchen einen Moment

Nach `setInput`/`setPower` liefert ein sofort folgender `getStatus`-Aufruf
teils noch den alten Wert zurück (Relais-/HDMI-Umschaltung braucht Zeit). Die
App fragt nach solchen Befehlen deshalb kurz wiederholt nach, bis der neue
Wert bestätigt ist, statt sich auf einen einzelnen Poll zu verlassen.
