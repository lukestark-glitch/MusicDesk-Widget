# Changelog

Alle nennenswerten Änderungen an MusicDesk. Format angelehnt an [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), Versionen nach [Semantic Versioning](https://semver.org/lang/de/).

## [1.1.1] – 2026-11-11

### Behoben
- Das Widget war auch auf den Vollbild-Spaces anderer Apps zu sehen (z. B. hinter Videos mit schwarzen Rändern). Es blendet sich jetzt aus, solange auf seinem Bildschirm eine App im Vollbild läuft, und kehrt danach automatisch zurück.
- Ein Klick auf das Widget (z. B. Play/Pause) hat seit 1.1.0 den Tastaturfokus übernommen, sodass Eingaben danach nicht mehr in der vorher benutzten App landeten. Der Fokus bleibt jetzt dort; ⌘, funktioniert dafür nur noch, solange MusicDesk aktiv ist (z. B. bei offenem Einstellungsfenster) – sonst Rechtsklick → „Einstellungen …“.

## [1.1.0] – 2026-11-11

### Neu
- **Mehrere Quellen:** neben Apple Music jetzt auch **Spotify** und **„Alles auf dem Mac“** – systemweite Wiedergabe jeder App, z. B. **YouTube im Browser** (über den mitgelieferten [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)).
- Quelle **„Automatisch“** (Standard): systemweit, wenn verfügbar, sonst die spielende bzw. geöffnete App (Apple Music vor Spotify).
- **Adapter-Test beim Start** mit automatischem Rückfall auf Apple Music/Spotify, falls die inoffizielle Schnittstelle nicht funktioniert.
- **Einstellungsfenster** mit Live-Vorschau (hell/dunkel), erreichbar per Rechtsklick → „Einstellungen …“ oder **⌘,**.
- **Farben:** neun Systemfarben (Graphit, Blau, Lila, Pink, Rot, Orange, Gelb, Grün, Mint) und eine **eigene Farbe** per Farbwähler oder Hex-Code.
- **Lesbarkeits-Schatten** für unruhige Hintergrundbilder.
- **Künstler dezenter** (60 % Deckkraft) – standardmäßig an.
- **Quelle anzeigen:** optionales App-Symbol vor dem Titel.
- **Laufschrift** für lange Titel (wahlweise statt Abkürzen); pausiert bei „Bewegung reduzieren“.
- **Fortschrittsleiste:** Deckkraft (15–100 %), **Glas-Effekt** (Liquid Glass ab macOS 26, sonst Milchglas), Hervorhebung des abgespielten Teils, Regler „Immer / Nur beim Überfahren / Nie“, dickere Leiste beim Überfahren, Zeit- und Restzeitanzeige beim Ziehen, „Live“-Anzeige bei Streams ohne Länge.
- **Knöpfe:** dezente Hover- und Klick-Animation, Tooltips, flüssiger Wiedergabe/Pause-Symbolwechsel ab macOS 14.
- **VoiceOver:** deutsche Beschriftungen; Fortschrittsleiste mit Wert („1:14 von 3:20“) und 10-s-Schritten.
- **Automatische Updates:** Suche beim Start und alle 24 h über GitHub-Releases, dezente Mitteilung, „Update installieren …“ im Rechtsklick-Menü und unter *Einstellungen → Updates* (Version, „Jetzt suchen“, Schalter „Automatisch nach Updates suchen“). Der Installer lädt die ZIP, prüft Bundle-ID, Version und Signatur, entfernt die Quarantäne, ersetzt die App am aktuellen Ort und startet neu; bei Fehlern bleibt die alte Version erhalten. (Von 1.0 auf 1.1 muss noch einmal von Hand aktualisiert werden.)
- **„Auf Standard zurücksetzen“** für alle Darstellungs- und Quellen-Einstellungen.
- `CHANGELOG.md`, `LICENSE-THIRD-PARTY.md`.

### Geändert
- Die Farbauswahl ist aus dem Rechtsklick-Menü ins Einstellungsfenster umgezogen; das Menü enthält jetzt „Einstellungen …“.
- Berechtigungstext erwähnt Apple Music **und** Spotify; die Erlaubnis wird je App einmal abgefragt. Die systemweite Quelle braucht keine Erlaubnis.
- Build: Der Adapter wird mit CMake als Universal-Binary gebaut und ins App-Bundle eingebettet (`Contents/Frameworks`, `Contents/Resources`, `Contents/Helpers`), alles ad-hoc signiert.
- CI baut parallel auf macOS 14, 15 und 26; Releases kommen vom neuesten Runner.
- Download jetzt unter [github.com/lukestark-glitch/MusicDesk-Widget/releases](https://github.com/lukestark-glitch/MusicDesk-Widget/releases) als `MusicDesk-1.1.0.zip`.
- Bestehende Einstellungen aus 1.0 (Farbe, Position, Sperre, Autostart) bleiben erhalten.

## [1.0.0]

### Neu
- Erste Version: transparentes Schreibtisch-Widget (560 × 114 pt) für **Apple Music** mit Titel und Künstler, Knöpfen für Zurück / Wiedergabe-Pause / Weiter und einer Fortschrittsleiste mit Regler (Klicken und Ziehen zum Springen).
- Fensterebene über den Schreibtisch-Symbolen, unter allen Fenstern, auf allen Spaces; kein Dock- oder Menüleisten-Symbol.
- Frei verschiebbar mit gespeicherter Position (mehrere Bildschirme), Position sperrbar.
- Farbe Schwarz, Weiß oder Automatisch (Rechtsklick-Menü).
- Autostart beim Anmelden (SMAppService), beim ersten Start eingeschaltet.
- Startet Apple Music nie selbst.
- Universal Binary (arm64 + x86_64), ad-hoc signiert; Build per Swift Package Manager und GitHub Actions.

[1.1.0]: https://github.com/lukestark-glitch/MusicDesk-Widget/releases/tag/v1.1.0
[1.0.0]: https://github.com/lukestark-glitch/MusicDesk-Widget/releases/tag/v1.0.0
