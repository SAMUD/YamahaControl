# YamahaControl

Menüleisten-App für macOS, um einen Yamaha AV-Receiver der RX-A-Serie
(getestet mit einem RX-A2070) im Heimnetz zu steuern – ganz ohne Cloud,
Yamaha-Account oder Internetverbindung. Die App spricht direkt die lokale
HTTP/JSON-API des Receivers an ("Yamaha Extended Control", YXC/MusicCast).

## Features

- **Ein/Aus, Lautstärke, Stumm** – Lautstärkeregler auch per Mausrad/Trackpad
  bedienbar, mit einstellbarer Sicherheits-Obergrenze
- **Globale Tastenkombination für Lautstärke** – frei aufnehmbare Shortcuts
  (Lauter/Leiser mit konfigurierbarer dB-Schrittweite, unabhängig von den
  normalen Mac-Lautstärketasten)
- **Bis zu vier Lieblings-Eingangsquellen** als Schnellzugriff, automatisch
  vom Receiver geladen
- **Bis zu vier Szenen-Tasten**
- **Netzwerk-Radio**: Titel/Sender, Play/Pause/Weiter/Zurück, gespeicherte
  Sender direkt anwählbar (klassische Presets und im Receiver-Menü angelegte
  Favoriten)
- **„Jetzt läuft“ im Control Center** + Steuerung über die Medientasten der
  Tastatur (F7–F9)
- **Automatisches Ein-/Ausschalten**: der AVR schaltet sich ein und wechselt
  auf den passenden Eingang, sobald auf dem gewählten Audiogerät tatsächlich ein
  hörbares Audiosignal läuft (und der Mac wach/entsperrt ist), und wieder aus,
  wenn der Mac in den Ruhezustand geht
- **Demo-Modus**: simuliert einen verbundenen AVR mit Beispieldaten zum Testen
  der Oberfläche ohne Gerät im Netzwerk
- Läuft unauffällig im Hintergrund, kein Dock-Icon, kein Programmwechsler-Eintrag

## Voraussetzungen

- macOS 13 (Ventura) oder neuer
- [Xcode](https://apps.apple.com/de/app/xcode/id497799835) oder mindestens
  die Xcode Command Line Tools (`xcode-select --install`)
- Der AVR im selben Netzwerk wie der Mac, mit fester bzw. bekannter
  IP-Adresse (Router oder AVR-Menü ▸ Network)

> Reine macOS-App (SwiftUI `MenuBarExtra`, AppKit, CoreAudio, MediaPlayer,
> ScreenCaptureKit) – Bauen und Ausführen geht nur auf einem Mac.

## Installation

```bash
git clone https://github.com/SAMUD/YamahaControl.git
cd YamahaControl
./Scripts/create_dev_cert.sh   # optional, aber empfohlen (behält macOS-Berechtigungen über Rebuilds)
./Scripts/build_app.sh
```

Das erzeugt `YamahaAVRControl.app` im Projektordner.

1. `YamahaAVRControl.app` nach `/Applications` verschieben.
2. Per Doppelklick starten. Falls die App ohne Zertifikat gebaut wurde, ggf.
   per Rechtsklick ▸ „Öffnen“ bestätigen.
3. In der Menüleiste erscheint ein Lautsprecher-Symbol. Anklicken ▸
   „Einstellungen“ ▸ IP-Adresse des AVR eintragen und speichern.
4. Optional für Autostart: **Systemeinstellungen ▸ Allgemein ▸
   Anmeldeobjekte ▸ „+“** ▸ `YamahaAVRControl.app` hinzufügen.

Alternativ zum Testen: `Package.swift` in Xcode öffnen und über
*Product ▸ Run* starten.

## Automatik: AVR an ein Audiogerät koppeln

In den Einstellungen ▸ „Automatisch einschalten“ lässt sich ein
macOS-Audioausgabegerät (z. B. der AVR selbst als AirPlay-/USB-/HDMI-Ziel,
oder eine Dockingstation) sowie ein Ziel-Eingang festlegen.

- **Echte Audiosignal-Erkennung:** Die App prüft über `ScreenCaptureKit`
  (nur Audio) kurz den tatsächlichen Signalpegel, sobald ein Audio-Stream auf
  dem Zielgerät aktiv ist – und erst bei hörbarem Ton (nicht bei digitaler
  Stille von z. B. geöffnetem DaVinci Resolve) wird eingeschaltet. Ist der AVR
  nicht erreichbar oder bereits an, wird der Audiostream nicht abgehört.
  Beim ersten Auslösen fragt macOS einmalig nach der Berechtigung
  *„Bildschirm- & Systemaudioaufnahme“* (Systemeinstellungen ▸ Datenschutz &
  Sicherheit).
- **Präsenz- & Schlaf-Absicherung:** Das automatische Einschalten greift nur,
  wenn der Mac wach, der Bildschirm an und entsperrt ist sowie kürzlich eine
  Nutzereingabe stattfand (verhindert nächtliche Fehltrigger durch Dark-Wakes
  oder Hintergrundprozesse). Geht nur der Monitor aus (z. B. beim Musikhören),
  bleibt der AVR an.
- **Ausschalten bei Mac-Ruhezustand:** Geht der Mac in den Ruhezustand, während
  der AVR auf dem konfigurierten Eingang steht, schaltet die App ihn
  automatisch wieder aus. Läuft am AVR bereits ein anderer Eingang, greift die
  Automatik nicht ein.

## Projektstruktur

```text
Package.swift                     Swift-Package-Definition
Sources/YamahaAVRControl/
  AVRModels.swift                 Codable-Modelle der YXC-API-Antworten
  AVRClient.swift                 HTTP-Client für die AVR-API
  AVRController.swift             Zustand, Polling, Aktionen (ObservableObject)
  SettingsStore.swift             Gespeicherte Einstellungen (UserDefaults)
  NowPlayingBridge.swift          Control-Center „Jetzt läuft“ + Medientasten
  AudioOutputMonitor.swift        CoreAudio: Standardausgabe + Stream-Aktivität
  AudioLevelMonitor.swift         ScreenCaptureKit: Pegelprüfung (Stille vs. Ton)
  AudioTriggerController.swift    AVR an/aus mit Präsenz-, Schlaf- & Pegel-Logik
  VolumeShortcutMonitor.swift     Globaler Tastendruck-Monitor (CGEventTap)
  VolumeShortcutController.swift  Steuerung der Lautstärke über eigene Shortcuts
  VolumeSliderControl.swift       Lautstärkeregler (NSSlider) mit Mausrad-Unterstützung
  MenuBarIconView.swift           Menüleisten-Icon
  MenuBarContentView.swift        Flyout-Inhalt
  SettingsView.swift              Einstellungen im Flyout
  YamahaAVRControlApp.swift       App-Einstiegspunkt (MenuBarExtra)
Scripts/
  build_app.sh                    Baut Release-Binary + packt .app-Bundle
  create_dev_cert.sh              Erstellt lokales Code-Signing-Zertifikat
  generate_icon.swift             Generiert das App-Icon
  Info.plist                      Bundle-Metadaten (u. a. LSUIElement)
docs/
  API_NOTES.md                    Technische Details/Eigenheiten der YXC-API
```

Details zu den verwendeten AVR-API-Endpunkten und ein paar nicht offensichtliche
Eigenheiten davon: [docs/API_NOTES.md](docs/API_NOTES.md).

## Alternative bzw. ergänzende Steuerungsmöglichkeiten

- **Kurzbefehle-App (Shortcuts)**: Mit „Inhalte von URL abrufen“ lassen sich
  dieselben HTTP-Befehle auch als Shortcuts bauen – per Siri, Tastenkombination,
  Stream Deck oder Automatisierung.
- **HomeKit via Homebridge**: z. B. Plugin `homebridge-musiccast` oder
  `homebridge-yamaha-avr` bringt den AVR in die Home-App (Siri,
  Control-Center, Automatisierungen, Apple Watch).
- **Hammerspoon / BetterTouchTool**: für eigene Tastenkombinationen/Gesten,
  die direkt HTTP-Aufrufe an den AVR schicken.
- Echte Lautstärke-Integration ins System-Lautstärkemenü ist technisch nicht
  möglich, solange der AVR nicht selbst das Audioausgabegerät des Mac ist.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
