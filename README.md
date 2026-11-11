# MusicDesk

**MusicDesk** ist ein kleines Widget für macOS, das anzeigt, was gerade in **Apple Music** läuft – und mit dem du die Wiedergabe direkt vom Schreibtisch aus steuerst.

Das Widget hat **keinen Hintergrund und keinen Rahmen**: Es besteht nur aus Text, drei Knöpfen und einer Fortschrittsleiste, die direkt auf deinem Schreibtisch-Hintergrundbild „schweben“. Es liegt **über dem Hintergrundbild und den Schreibtisch-Symbolen**, aber **unter allen normalen Fenstern** – es stört also nie beim Arbeiten. Und es ist auf **allen Spaces** (virtuellen Schreibtischen) sichtbar.

> **Screenshot-Platzhalter:** Hier kommt ein Bildschirmfoto des Widgets hin (geplant als `docs/screenshot.png`, noch nicht vorhanden).

---

## Inhalt

- [Funktionen](#funktionen)
- [Voraussetzungen](#voraussetzungen)
- [Installation für Endnutzer (fertige App herunterladen)](#installation-für-endnutzer-fertige-app-herunterladen)
- [Installation per Skript (selbst bauen)](#installation-per-skript-selbst-bauen)
- [Bedienung](#bedienung)
- [Autostart](#autostart)
- [Deinstallation](#deinstallation)
- [Fehlerbehebung](#fehlerbehebung)
- [Hinweis zu Signatur und Apple-Entwicklerkonto](#hinweis-zu-signatur-und-apple-entwicklerkonto)
- [Für Entwickler](#für-entwickler)
- [Lizenz](#lizenz)

---

## Funktionen

- Zeigt **Titel und Künstler** des aktuellen Songs in Apple Music („Titel, Künstler“).
- Zeigt **„Nichts läuft“**, wenn Apple Music geschlossen ist oder nichts abgespielt wird.
- Knöpfe für **Zurück**, **Wiedergabe/Pause** und **Weiter**.
- **Fortschrittsleiste** mit Regler: Anklicken oder Ziehen springt an eine beliebige Stelle im Song. Die Leiste läuft flüssig mit.
- **Komplett transparent** – kein Kasten, kein Schatten, nur Inhalt auf dem Hintergrundbild.
- Liegt über dem Schreibtisch, aber unter allen Fenstern, auf **allen Spaces**.
- **Frei verschiebbar**; die Position wird gemerkt (auch bei mehreren Bildschirmen). Position lässt sich **sperren**.
- **Farbe** wählbar: Schwarz, Weiß oder Automatisch (folgt dem hellen/dunklen Erscheinungsbild von macOS).
- **Startet automatisch beim Anmelden** (abschaltbar).
- Kein Dock-Symbol, kein Menüleisten-Symbol, taucht nicht im App-Umschalter (⌘-Tab) auf.
- Startet Apple Music **niemals von selbst** – das Widget beobachtet nur.
- Läuft nativ auf **Intel- und Apple-Silicon-Macs** (Universal Binary).

---

## Voraussetzungen

- **macOS 13 Ventura oder neuer** (getestetes Ziel bis einschließlich macOS 27)
- **Intel-Mac oder Apple-Silicon-Mac** (M1, M2, M3, M4 …) – die App ist ein Universal Binary und läuft auf beiden nativ
- Die **Apple-Music-App** (in macOS enthalten)

---

## Installation für Endnutzer (fertige App herunterladen)

### 1. App herunterladen

Repository: [github.com/lukestark-glitch/musicdesk-widget](https://github.com/lukestark-glitch/musicdesk-widget).

- **Empfohlen – GitHub Releases:** Öffne die Seite
  [Releases](https://github.com/lukestark-glitch/musicdesk-widget/releases) und lade bei der neuesten MusicDesk-Version die Datei **`MusicDesk-1.0.0.zip`** herunter.
  (Releases werden automatisch von GitHub Actions erstellt, sobald ein Tag wie `v1.0.0` veröffentlicht wird.)
- **Alternativ – Build-Artefakt:** Im Reiter
  [Actions](https://github.com/lukestark-glitch/musicdesk-widget/actions) den neuesten erfolgreichen Lauf des MusicDesk-Workflows öffnen und unten unter **„Artifacts“** die ZIP-Datei herunterladen. (Dafür musst du bei GitHub angemeldet sein. Das Artefakt ist eine ZIP, in der die eigentliche `MusicDesk-1.0.0.zip` steckt – ggf. zweimal entpacken.)

### 2. Entpacken und in „Programme“ ziehen

1. Doppelklick auf die ZIP-Datei – es erscheint **`MusicDesk.app`**.
2. Ziehe `MusicDesk.app` im Finder in den Ordner **Programme**.

### 3. Erstes Öffnen – Warnung „nicht verifizierter Entwickler“

Weil die App nicht über ein kostenpflichtiges Apple-Entwicklerkonto beglaubigt ist, zeigt macOS beim ersten Öffnen eine Warnung wie *„MusicDesk kann nicht geöffnet werden, da es von einem nicht verifizierten Entwickler stammt“* bzw. *„Apple konnte nicht überprüfen, ob MusicDesk frei von Schadsoftware ist“*. Das ist normal. So öffnest du sie trotzdem:

1. Doppelklick auf `MusicDesk.app` → die Warnung erscheint → **„Fertig“** bzw. **„OK“** klicken (nicht „In den Papierkorb legen“).
2. **Systemeinstellungen** → **Datenschutz & Sicherheit** öffnen.
3. Ganz nach unten zum Abschnitt **Sicherheit** scrollen. Dort steht ein Hinweis zu MusicDesk → **„Trotzdem öffnen“** klicken.
4. Mit Passwort bzw. Touch ID bestätigen und im nächsten Dialog nochmals **„Trotzdem öffnen“** wählen.

> **Hinweis:** Auf älteren macOS-Versionen ging das auch per **Rechtsklick → „Öffnen“**. Ab macOS 15 Sequoia funktioniert diese Abkürzung **nicht mehr** – nimm den Weg über die Systemeinstellungen.

**Alternative über das Terminal:** Öffne die App „Terminal“ und gib ein:

```bash
xattr -dr com.apple.quarantine /Applications/MusicDesk.app
```

Danach lässt sich die App ganz normal per Doppelklick öffnen.

### 4. Zugriff auf Apple Music erlauben

Beim ersten Start fragt macOS:
**„MusicDesk möchte auf Music zugreifen“** → **„OK“** klicken.

Ohne diese Erlaubnis kann das Widget weder den Song anzeigen noch die Wiedergabe steuern. Die Erlaubnis kannst du später jederzeit ändern unter
**Systemeinstellungen → Datenschutz & Sicherheit → Automation** (Eintrag „MusicDesk“ → „Music“).

> Die Abfrage erscheint erst, wenn Apple Music läuft – das Widget startet Music nicht selbst.

Fertig! Das Widget erscheint unten mittig auf deinem Bildschirm.

---

## Installation per Skript (selbst bauen)

Wer die App lieber selbst aus dem Quellcode baut, braucht **Xcode** oder die **Command Line Tools**. Letztere installierst du im Terminal mit:

```bash
xcode-select --install
```

Dann:

```bash
git clone https://github.com/lukestark-glitch/musicdesk-widget.git
cd musicdesk-widget
./scripts/install.sh
```

Das Skript baut die App, beendet eine evtl. laufende alte Version, kopiert `MusicDesk.app` nach `/Applications` und startet sie.
**Es erscheint keine Gatekeeper-Warnung**, weil selbst gebaute Apps kein Quarantäne-Merkmal (wie heruntergeladene Dateien) tragen.

Nur bauen, ohne zu installieren:

```bash
./scripts/build.sh
```

Das Ergebnis liegt dann in `dist/MusicDesk.app` und als ZIP in `dist/MusicDesk-1.0.0.zip`.

---

## Bedienung

| Aktion | So geht's |
|---|---|
| **Widget verschieben** | Auf den **Songtitel** klicken und ziehen. Die Position wird gespeichert. |
| **Wiedergabe / Pause** | Mittlerer Knopf (▶ / ❚❚) |
| **Vorheriger / nächster Song** | Linker bzw. rechter Knopf (◀◀ / ▶▶) |
| **Im Song springen** | Auf die Fortschrittsleiste klicken oder den Regler ziehen |
| **Einstellungen** | **Rechtsklick** (oder Ctrl-Klick) auf Titel, Knöpfe oder Leiste öffnet das Menü |

**Das Rechtsklick-Menü:**

- **Farbe** → *Schwarz*, *Weiß* oder *Automatisch* (passt sich dem hellen/dunklen Modus von macOS an). Standard ist Schwarz.
- **Position sperren** – verhindert versehentliches Verschieben.
- **Beim Login starten** – Autostart ein/aus.
- **Über MusicDesk** – Versionsinfo.
- **MusicDesk beenden**

Wenn Apple Music geschlossen ist oder nichts abspielt, zeigt das Widget **„Nichts läuft“**.

> **Wichtig:** MusicDesk hat **kein Dock-Symbol und kein Menüleisten-Symbol**. Beenden kannst du die App daher nur über **Rechtsklick → „MusicDesk beenden“** (oder über die Aktivitätsanzeige).

Klicks auf die leeren, durchsichtigen Stellen zwischen Text und Knöpfen gehen durch das Widget hindurch auf den Schreibtisch.

---

## Autostart

Beim **ersten Start** trägt sich MusicDesk automatisch als Anmeldeobjekt ein, startet also künftig bei jeder Anmeldung mit.

Abschalten bzw. wieder einschalten:

- **Rechtsklick → „Beim Login starten“**, oder
- **Systemeinstellungen → Allgemein → Anmeldeobjekte** (MusicDesk unter „Beim Anmelden öffnen“ bzw. „Im Hintergrund erlauben“).

---

## Deinstallation

**Per Skript** (aus dem Ordner `MusicDesk-Widget`):

```bash
./scripts/uninstall.sh
```

**Von Hand:**

1. MusicDesk beenden: **Rechtsklick → „MusicDesk beenden“**.
2. `MusicDesk.app` aus dem Ordner **Programme** in den Papierkorb ziehen.
3. Einstellungen löschen (Terminal):
   ```bash
   defaults delete com.musicdesk.widget
   ```
4. Anmeldeobjekt entfernen: **Systemeinstellungen → Allgemein → Anmeldeobjekte** – falls MusicDesk dort noch steht, entfernen (verschwindet normalerweise mit dem Löschen der App).
5. Optional die Music-Erlaubnis zurücksetzen:
   ```bash
   tccutil reset AppleEvents com.musicdesk.widget
   ```

---

## Fehlerbehebung

**Das Widget zeigt „Nichts läuft“, obwohl Musik spielt / es wurde nie nach der Erlaubnis gefragt**
Wahrscheinlich fehlt die Erlaubnis für Apple Music oder wurde abgelehnt. Prüfe *Systemeinstellungen → Datenschutz & Sicherheit → Automation → MusicDesk → Music*. Oder setze die Erlaubnis zurück und starte die App neu – dann wird erneut gefragt:

```bash
tccutil reset AppleEvents com.musicdesk.widget
```

Danach MusicDesk beenden (Rechtsklick → „MusicDesk beenden“) und wieder öffnen.

**Das Widget ist unsichtbar (z. B. schwarze Schrift auf dunklem Hintergrundbild)**
Das Widget ist trotzdem da – man sieht es nur nicht. Ein Rechtsklick wirkt allerdings nur **genau auf Titel, Knöpfen oder Leiste**, nicht auf den leeren Flächen dazwischen. Versuche es unten mittig auf dem Bildschirm (Standardposition), oder stelle die Farbe per Terminal um und starte die App neu:

```bash
defaults write com.musicdesk.widget colorMode white
```

(Werte: `black`, `white`, `automatic`.) Alle Einstellungen inklusive Position setzt du mit `defaults delete com.musicdesk.widget` zurück.

**Das Widget ist außerhalb des Bildschirms (z. B. nach Abstecken eines Monitors)**
Normalerweise holt MusicDesk sich beim Start selbst zurück auf einen sichtbaren Bildschirm. Falls nicht: App beenden, dann

```bash
defaults delete com.musicdesk.widget
```

und neu starten – das Widget erscheint wieder unten mittig.

**Nach dem erneuten Bauen fragt macOS wieder nach der Music-Erlaubnis**
Das ist normal: Jeder neue Build erhält eine neue (Ad-hoc-)Signatur, und macOS behandelt ihn wie eine neue App. Einfach wieder „OK“ klicken. Falls die Abfrage nicht kommt, siehe oben (`tccutil reset …`).

**Der Autostart funktioniert nicht**
Prüfe unter *Systemeinstellungen → Allgemein → Anmeldeobjekte*, ob MusicDesk eingetragen und erlaubt ist, und schalte im Rechtsklick-Menü „Beim Login starten“ aus und wieder ein. Die App sollte in `/Applications` liegen.

**Apple Music startet nicht, wenn ich auf ▶ klicke**
Das ist **Absicht**. MusicDesk öffnet Apple Music niemals von selbst – es soll nicht ungefragt Programme starten. Öffne Music einmal selbst, danach funktionieren alle Knöpfe.

---

## Hinweis zu Signatur und Apple-Entwicklerkonto

- Für MusicDesk ist **kein kostenpflichtiges Apple-Developer-Konto** nötig – weder zum Benutzen noch zum Bauen.
- Die App ist **ad-hoc signiert** (lokale Signatur ohne Apple-Zertifikat). Deshalb die einmalige Gatekeeper-Warnung beim heruntergeladenen Build.
- Die App **läuft dauerhaft**. Es gibt **kein Ablaufen nach 7 Tagen** wie bei iOS-Apps mit kostenlosen Provisioning-Profilen – MusicDesk ist eine normale Mac-App, für die diese Einschränkung nicht gilt.

---

## Für Entwickler

### Projektstruktur

```
musicdesk-widget/
├── .github/workflows/build.yml    # CI: Universal-Build, Release bei Tag v*
├── Package.swift                  # Swift Package (swift-tools 5.9, macOS 13+)
├── Sources/MusicDesk/
│   ├── App/                       # main.swift, AppDelegate, Settings, LoginItem, Kontextmenü
│   ├── Music/                     # PlaybackState, MusicController, AppleScriptRunner
│   └── UI/                        # NSPanel-Fenster + SwiftUI-WidgetView
├── Resources/
│   ├── Info.plist                 # Bundle-ID com.musicdesk.widget, LSUIElement
│   ├── AppIcon.icns               # wird von scripts/make_icon.py erzeugt
│   └── AppIcon.png                # Icon als PNG (1024 px)
├── scripts/
│   ├── build.sh                   # Universal-Build + App-Bundle + Ad-hoc-Signatur + ZIP
│   ├── install.sh                 # bauen und nach /Applications installieren
│   ├── uninstall.sh               # vollständig entfernen
│   ├── check-bundle.sh            # prüft das fertige App-Bundle (Info.plist, Architekturen, Signatur)
│   └── make_icon.py               # App-Icon programmatisch erzeugen (Pillow)
├── docs/
│   └── ENTSCHEIDUNGEN.md          # Design- und Technik-Entscheidungen
├── LICENSE
└── README.md
```

Der CI-Workflow liegt im Repository-Wurzelverzeichnis: `.github/workflows/build.yml`.

### Technik

- **Swift 5.9**, **SwiftUI** für die Oberfläche, eingebettet per `NSHostingView`
- **AppKit `NSPanel`** (randlos, transparent, nicht aktivierend) auf Fensterebene *Schreibtisch-Symbole + 1*, auf allen Spaces
- **`NSAppleScript`** auf einer eigenen seriellen Hintergrund-Queue zur Kommunikation mit Apple Music; zusätzlich die verteilte Benachrichtigung `com.apple.Music.playerInfo` und 1-Sekunden-Abfrage
- **`SMAppService`** (ServiceManagement) für den Autostart
- **Swift Package Manager**, kein Xcode-Projekt nötig
- **Universal Binary** (arm64 + x86_64), ad-hoc signiert

Einstellungen (UserDefaults-Domain `com.musicdesk.widget`): `colorMode`, `positionLocked`, `windowOriginX`, `windowOriginY`, `windowScreenID`, `windowScreenName`, `didAttemptInitialLoginRegistration`.

Hintergründe zu den einzelnen Entscheidungen: [docs/ENTSCHEIDUNGEN.md](docs/ENTSCHEIDUNGEN.md).

### CI

Der Workflow [`.github/workflows/build.yml`](.github/workflows/build.yml) läuft auf einem macOS-Runner bei jedem Push und Pull-Request, bei Tags `v*` sowie manuell (*workflow_dispatch*). Er baut die App mit `scripts/build.sh`, prüft Architekturen (`lipo`), Signatur (`codesign -v`) und `Info.plist` und lädt die ZIP als Artefakt hoch.

### Release erstellen

```bash
git tag v1.0.0
git push origin v1.0.0
```

Der Workflow baut dann die App und legt automatisch ein GitHub-Release mit `MusicDesk-1.0.0.zip` an. Für eine neue Version vorher `CFBundleShortVersionString`/`CFBundleVersion` in `Resources/Info.plist` anpassen – `scripts/build.sh` liest die Version von dort und benennt die ZIP entsprechend (`MusicDesk-<Version>.zip`).

---

## Lizenz

MusicDesk steht unter der **MIT-Lizenz** – siehe [LICENSE](LICENSE).

MusicDesk ist ein unabhängiges Projekt und steht in keiner Verbindung zu Apple Inc. „Apple Music“ und „macOS“ sind Marken von Apple Inc.
