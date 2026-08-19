# YamahaControl

Kleine macOS-Menüleisten-App, um einen Yamaha AV-Receiver (getestet gedacht für die
RX-A-Serie, z. B. RX-A2070) im Heimnetz zu steuern: Ein-/Ausschalten, Lautstärke,
Stumm, vier Lieblings-Eingangsquellen, Szenen/Presets und Play/Pause/Sender für
Netzwerk-Radio.

Die App läuft dauerhaft im Hintergrund (kein Dock-Icon), prüft periodisch, ob der
AVR im Netzwerk erreichbar ist, und zeigt das passend im Menüleisten-Icon an. Ein
Klick öffnet ein kleines Flyout mit den Bedienelementen.

Technisch spricht die App direkt die HTTP/JSON-API des Receivers an
("Yamaha Extended Control" / MusicCast-API, `http://<AVR-IP>/YamahaExtendedControl/v1/...`).
Es wird keine zusätzliche Cloud, kein Yamaha-Account und keine Internetverbindung
benötigt – alles läuft rein lokal im Heimnetz.

## Voraussetzungen

- Ein Mac mit macOS 13 (Ventura) oder neuer.
- [Xcode](https://apps.apple.com/de/app/xcode/id497799835) aus dem Mac App Store
  (kostenlos) bzw. mindestens die Xcode Command Line Tools (`xcode-select --install`).
- Der AVR muss per LAN/WLAN im selben Netzwerk wie der Mac hängen und eine feste
  bzw. bekannte IP-Adresse haben (im AVR-Menü unter Network zu finden, oder z. B.
  im Router nachschauen). Eine feste IP-Reservierung im Router ist empfehlenswert,
  damit sich die Adresse nicht ändert.

> **Hinweis:** Der Code kann nicht unter Windows/Linux gebaut oder getestet werden –
> die App nutzt macOS-exklusive Frameworks (SwiftUI `MenuBarExtra`, AppKit,
> CoreAudio, MediaPlayer). Bauen und Testen geht nur auf einem Mac.

## Einrichtung

1. Projekt auf den Mac holen (`git clone ...` oder Ordner kopieren).
2. Im Terminal ins Projektverzeichnis wechseln und bauen:

   ```bash
   ./Scripts/build_app.sh
   ```

   Das erzeugt `YamahaAVRControl.app` im Projekt-Root.

   Alternativ: `Package.swift` in Xcode öffnen (Doppelklick) und über
   *Product ▸ Run* direkt starten – praktisch zum Testen, bevor man die App
   fest einrichtet.
3. `YamahaAVRControl.app` in den Ordner „Programme“ (`/Applications`) ziehen.
4. App einmal per Doppelklick starten. Da sie nicht mit einem Apple-Entwicklerkonto
   signiert ist, meldet macOS beim ersten Start ggf. „nicht verifizierter
   Entwickler“ – dann im Finder mit Rechtsklick ▸ „Öffnen“ bestätigen.
5. In der Menüleiste erscheint ein Lautsprecher-Symbol. Anklicken, dann unten auf
   „Einstellungen“ und die IP-Adresse des AVR eintragen und speichern.
6. Damit die App künftig automatisch beim Anmelden startet: **Systemeinstellungen
   ▸ Allgemein ▸ Anmeldeobjekte** öffnen, unter „Öffnen bei der Anmeldung“ auf „+“
   klicken und `YamahaAVRControl.app` hinzufügen.

Danach läuft die App im Hintergrund, prüft regelmäßig (Standard: alle 5 Sekunden,
einstellbar) die Erreichbarkeit des AVR und zeigt Status/Bedienung im Flyout.

## Bedienung im Flyout

- **Ein/Aus**: Schalter oben.
- **Lautstärke**: Schieberegler, Lautsprecher-Symbol daneben schaltet stumm. Lässt
  sich per Ziehen oder per Mausrad/Trackpad-Scroll direkt über dem Regler bedienen.
  Der Regler hat eine einstellbare Sicherheits-Obergrenze (Standard 70 %) – ein
  versehentlicher Klick daneben kann die Lautstärke dadurch nie auf 100 % springen
  lassen. Einstellbar unter „Einstellungen ▸ Lautstärke-Sicherheit“.
- **Quellen**: bis zu vier Favoriten, wählbar in den Einstellungen (Liste wird
  automatisch vom AVR geladen).
- **Szenen**: bis zu vier Szenen-Tasten, sobald der AVR programmierte Szenen
  meldet. Die YXC-API liefert dazu keine Namen, daher erscheinen sie als
  „Szene 1“–„Szene 4“ (entspricht den SCENE-Tasten auf Fernbedienung/Gerät).
- **Wiedergabe**: Bei Netzwerk-Radio/USB/Bluetooth/Streaming werden Titel/Sender
  sowie Zurück/Play-Pause/Weiter angezeigt. Bei Netzwerk-Radio zusätzlich ein Menü
  zum direkten Anwählen gespeicherter Sender – dabei werden sowohl klassische,
  nummerierte Presets als auch im Receiver-Menü unter „Radio ▸ Favoriten“ angelegte
  Senderfavoriten unterstützt (je nachdem, welche davon belegt sind).

## Automatisch einschalten/ausschalten bei Audiogerätewechsel

In den Einstellungen ▸ „Automatisch einschalten“ lässt sich ein macOS-Audioausgabe­gerät
auswählen (z. B. wenn der AVR selbst als AirPlay-2-, USB- oder HDMI-Ziel im
Lautsprecher-Menü von macOS erscheint) sowie ein Ziel-Eingang. Schaltet die App den AVR
automatisch ein und wechselt auf den gewählten Eingang, sobald auf diesem Gerät tatsächlich
Ton **abgespielt** wird – auch wenn das Gerät bereits beim App-Start aktiv ist oder der Mac
gerade erst aus dem Ruhezustand aufwacht. Bewusst nicht schon beim bloßen Auswählen des
Geräts als Standardausgabe: Manche Dockingstations wählen sich beim Einstecken (z. B. nur
zum Laden) automatisch als Standard-Audioausgabe, ganz ohne dass etwas läuft – das soll den
AVR nicht grundlos einschalten. Erkannt wird das über
`kAudioDevicePropertyDeviceIsRunningSomewhere` in CoreAudio
([AudioOutputMonitor.swift](Sources/YamahaAVRControl/AudioOutputMonitor.swift)). Läuft der
AVR bereits, schaltet die Automatik ihn auch nicht auf einen anderen Eingang um – läuft dort
schon etwas anderes, wird das nicht unterbrochen.

Geht der Mac in den Ruhezustand, während der AVR auf genau diesem Eingang steht, schaltet
die App ihn automatisch wieder aus.

Während der Mac schläft (zwischen `willSleep` und einem echten, bildschirm-
sichtbaren Aufwachen) wird jede vom System gemeldete Geräteänderung ignoriert –
CoreAudio meldet gelegentlich unabhängig von jeder Wake-Notification kurzzeitig
wieder das Zielgerät (z. B. wenn eine AirPlay-Route während eines kurzen
„Dark Wake“ neu aufgebaut wird), was den AVR sonst mitten im Schlaf des Mac
wieder eingeschaltet hätte. Sollte der AVR trotzdem noch spontan während des
Schlafs angehen: In **Console.app** nach `YamahaAVRControl` filtern – jede
Schlaf-/Wach-/Geräte-Änderung, die die Automatik sieht, wird dort protokolliert
(`[AudioTrigger]: ...`), das zeigt genau, welches Ereignis den Auslöser gezogen hat.

## Hinweise zur YXC-API

Alle Endpunkte in [AVRClient.swift](Sources/YamahaAVRControl/AVRClient.swift)
sind an einem echten RX-A2070 verifiziert, u. a.:

- **Szenen** werden über `GET /<zone>/recallScene?num=<1-basierte Nummer>`
  aufgerufen. Die YXC-API liefert dazu keine Namen – die Anzahl programmierter
  Szenen (`scene_num` aus `getFeatures`) wird daher clientseitig als „Szene 1“
  bis „Szene 4“ dargestellt.
- **Netzwerk-Radio-Favoriten**: Klassische, nummerierte Presets
  (`netusb/getPresetInfo`) und im Receiver-Menü unter „Radio ▸ Favoriten“
  angelegte Senderfavoriten sind zwei getrennte Systeme. Letztere liegen nicht
  in einer flachen Liste, sondern in der Menü-Navigationsstruktur
  (`netusb/getListInfo` / `netusb/setListControl`) – die App sucht darin
  automatisch (sprachunabhängig) nach einem Ordner mit „favorit“ im Namen.
  Sollte sich die Menüstruktur deines Receivers/Anbieters unterscheiden, im
  Browser `http://<AVR-IP>/YamahaExtendedControl/v1/netusb/getListInfo?list_id=main&input=net_radio&index=0&size=8&lang=de`
  öffnen, um die tatsächliche Struktur zu sehen.
- **`netusb/setListControl`** kennt drei `type`-Werte: `select` (in einen
  Ordner navigieren bzw. einen Eintrag markieren – startet **keine**
  Wiedergabe, auch nicht bei einem Sender/Titel), `play` (Wiedergabe
  tatsächlich starten) und `return` (eine Ebene zurück). Für das Abspielen
  eines Senders wird daher `type=play` gebraucht, nicht `select`.

## Alternative bzw. ergänzende Steuerungsmöglichkeiten unter macOS

Diese App deckt den Hauptwunsch (bequeme Lautstärke-/Ein-Aus-Steuerung per
Menüleiste) ab. Ein paar zusätzliche, macOS-native Wege, die sich lohnen könnten:

- **„Jetzt läuft“-Widget & Medientasten**: Ist bereits eingebaut
  ([NowPlayingBridge.swift](Sources/YamahaAVRControl/NowPlayingBridge.swift)).
  Solange Netzwerk-Radio/USB/Bluetooth läuft, tauchen Titel/Sender im
  Control-Center-Widget „Jetzt läuft“ auf, und die Medientasten der
  Tastatur (F7/F8/F9) steuern Play/Pause/Weiter/Zurück – auch wenn das
  Flyout nicht offen ist.
- **Echte Lautstärke-Integration ins System-Lautstärkemenü ist technisch nicht
  möglich**, solange der AVR nicht das Audioausgabegerät des Mac selbst ist
  (macOS regelt dort nur die Lokal-Lautstärke des Mac, nicht die eines
  separaten Netzwerkgeräts). Wird der AVR stattdessen als AirPlay-Ziel benutzt
  (Ton wird vom Mac per AirPlay an den AVR gestreamt), erscheint er automatisch
  im System-Lautstärkemenü/Control Center – dann regelt macOS aber nur die
  AirPlay-Streamlautstärke, nicht zwingend 1:1 die AVR-eigene Lautstärke. Die
  Auswahl dieses Geräts lässt sich aber als Auslöser nutzen, siehe
  „Automatisch einschalten bei Audiogerätewechsel“ oben.
- **Kurzbefehle-App (Shortcuts)**: Mit der Aktion „Inhalte von URL abrufen“
  lassen sich dieselben HTTP-Befehle, die diese App nutzt, auch als
  Shortcuts bauen – dann per Siri-Sprachbefehl, Tastenkombination, Stream Deck
  oder als Automatisierung („Wenn ich mich am Mac anmelde, AVR einschalten“)
  auslösbar.
- **HomeKit via Homebridge**: Mit einem kleinen Homebridge-Server (z. B. Plugin
  `homebridge-musiccast` oder `homebridge-yamaha-avr`) taucht der AVR als
  Lautsprecher/Schalter in der Home-App auf – inkl. Siri, Control-Center-
  Mediensteuerung, Automatisierungen und Apple-Watch-Bedienung.
- **Hammerspoon / BetterTouchTool**: Für individuelle Tastenkombinationen oder
  Trackpad-Gesten, die direkt HTTP-Aufrufe an den AVR schicken (z. B.
  Lautstärke über die normalen Fn-Lautstärketasten regeln, auch wenn der Mac
  gar nicht der Audioausgang ist).

## Projektstruktur

```text
Package.swift                     Swift-Package-Definition
Sources/YamahaAVRControl/
  AVRModels.swift                 Codable-Modelle der YXC-API-Antworten
  AVRClient.swift                 HTTP-Client für die AVR-API
  AVRController.swift             Zustand, Polling, Aktionen (ObservableObject)
  SettingsStore.swift             Gespeicherte Einstellungen (UserDefaults)
  NowPlayingBridge.swift          Control-Center „Jetzt läuft“ + Medientasten
  AudioOutputMonitor.swift        CoreAudio: aktuelles macOS-Standardausgabegerät
  AudioTriggerController.swift    AVR an/aus bei Audiogerätewechsel bzw. Mac-Schlaf
  VolumeSliderControl.swift       Lautstärkeregler (NSSlider) mit Mausrad-Unterstützung
  MenuBarIconView.swift           Menüleisten-Icon
  MenuBarContentView.swift        Flyout-Inhalt
  SettingsView.swift              Einstellungen im Flyout
  YamahaAVRControlApp.swift       App-Einstiegspunkt (MenuBarExtra)
Scripts/
  build_app.sh                    Baut Release-Binary + packt .app-Bundle
  Info.plist                      Bundle-Metadaten (u. a. LSUIElement)
```

## Lizenz

MIT, siehe [LICENSE](LICENSE).
