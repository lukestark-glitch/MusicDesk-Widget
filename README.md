# MusicDesk

**MusicDesk** ist ein kleines Widget für macOS, das anzeigt, was gerade läuft – in **Apple Music**, in **Spotify** oder (neu in 1.1) **in jeder anderen App auf dem Mac**, zum Beispiel **YouTube im Browser** – und mit dem du die Wiedergabe direkt vom Schreibtisch aus steuerst.

Das Widget hat **keinen Hintergrund und keinen Rahmen**: Es besteht nur aus Text, drei Knöpfen und einer Fortschrittsleiste, die direkt auf deinem Schreibtisch-Hintergrundbild „schweben“. Es liegt **über dem Hintergrundbild und den Schreibtisch-Symbolen**, aber **unter allen normalen Fenstern** – es stört also nie beim Arbeiten. Und es ist auf **allen Spaces** (virtuellen Schreibtischen) sichtbar.

> **Screenshot-Platzhalter:** Hier kommt ein Bildschirmfoto des Widgets hin (geplant als `docs/screenshot.png`, noch nicht vorhanden).

Was sich seit 1.0 geändert hat, steht im [CHANGELOG](CHANGELOG.md).

---

## Inhalt

- [Funktionen](#funktionen)
- [Quellen](#quellen)
- [Voraussetzungen](#voraussetzungen)
- [Installation für Endnutzer (fertige App herunterladen)](#installation-für-endnutzer-fertige-app-herunterladen)
- [Installation per Skript (selbst bauen)](#installation-per-skript-selbst-bauen)
- [Bedienung](#bedienung)
- [Einstellungen](#einstellungen)
- [Berechtigungen](#berechtigungen)
- [Updates](#updates)
- [Autostart](#autostart)
- [Deinstallation](#deinstallation)
- [Fehlerbehebung](#fehlerbehebung)
- [Hinweis zu Signatur und Apple-Entwicklerkonto](#hinweis-zu-signatur-und-apple-entwicklerkonto)
- [Für Entwickler](#für-entwickler)
- [Lizenz und Drittanbieter-Komponenten](#lizenz-und-drittanbieter-komponenten)

---

## Funktionen

- Zeigt **Titel und Künstler** des aktuellen Songs („Titel, Künstler“) – bei Videos im Browser Titel und Kanal bzw. Website. Der Künstler wird auf Wunsch etwas dezenter dargestellt.
- **Mehrere Quellen:** Apple Music, Spotify und **„Alles auf dem Mac“** (systemweite Wiedergabe, z. B. YouTube in Safari, Chrome, Firefox oder Arc). Standard ist **Automatisch** – MusicDesk nimmt, was gerade spielt (siehe [Quellen](#quellen)).
- Zeigt **„Nichts läuft“**, wenn nichts abgespielt wird.
- Knöpfe für **Zurück**, **Wiedergabe/Pause** und **Weiter** – mit dezenter Rückmeldung beim Überfahren und Klicken, Tooltips und VoiceOver-Beschriftung. Ab macOS 14 wechselt das Wiedergabe-/Pause-Symbol mit der flüssigen SF-Symbols-Animation.
- **Fortschrittsleiste** mit Regler: Anklicken oder Ziehen springt an eine beliebige Stelle. Die Leiste läuft flüssig mit, wird beim Überfahren etwas dicker und zeigt beim Ziehen die aktuelle und die verbleibende Zeit an. Bei Livestreams ohne bekannte Länge erscheint „Live“.
- **Glas-Effekt** für die Leiste: Liquid Glass ab macOS 26, sonst Milchglas.
- **Lange Titel** werden abgekürzt (…) oder laufen auf Wunsch als **Laufschrift** durch.
- **Farbe** frei wählbar: Schwarz, Weiß, Automatisch (folgt dem hellen/dunklen Erscheinungsbild von macOS), neun Systemfarben oder eine **eigene Farbe** (Farbwähler oder Hex-Code). Optional mit **Lesbarkeits-Schatten** für unruhige Hintergrundbilder.
- Eigenes **Einstellungsfenster** mit **Live-Vorschau** (Rechtsklick → „Einstellungen …“ oder **⌘,**).
- **Komplett transparent** – kein Kasten, kein Rahmen, nur Inhalt auf dem Hintergrundbild.
- Liegt über dem Schreibtisch, aber unter allen Fenstern, auf **allen Spaces**.
- **Frei verschiebbar**; die Position wird gemerkt (auch bei mehreren Bildschirmen). Position lässt sich **sperren**.
- **Startet automatisch beim Anmelden** (abschaltbar).
- **Automatische Updates:** sucht beim Start und alle 24 Stunden nach einer neuen Version und installiert sie auf Wunsch mit einem Klick (siehe [Updates](#updates)).
- Kein Dock-Symbol, kein Menüleisten-Symbol, taucht nicht im App-Umschalter (⌘-Tab) auf.
- Startet Apple Music oder Spotify **niemals von selbst** – das Widget beobachtet nur.
- Läuft nativ auf **Intel- und Apple-Silicon-Macs** (Universal Binary).

---

## Quellen

Unter **Einstellungen → Quelle** wählst du, woher MusicDesk die Wiedergabe liest:

| Quelle | Was wird angezeigt | Technik |
|---|---|---|
| **Automatisch** (Standard) | Was gerade spielt – siehe Reihenfolge unten | – |
| **Apple Music** | Nur die Music-App | AppleScript |
| **Spotify** | Nur die Spotify-App | AppleScript + Spotify-Benachrichtigungen |
| **Alles auf dem Mac** | Jede App, die macOS als „Läuft gerade“ meldet: YouTube und andere Seiten im Browser, Podcasts, VLC, Apple Music, Spotify … | mitgelieferter [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) |

**So entscheidet „Automatisch“:**

1. Ist die Quelle „Alles auf dem Mac“ verfügbar, wird sie verwendet – sie deckt alle Apps ab.
2. Sonst: Apple Music, falls sie gerade **spielt** – sonst Spotify, falls es gerade **spielt**.
3. Sonst: Apple Music, falls sie **geöffnet** ist – sonst Spotify, falls es **geöffnet** ist.
4. Sonst: „Nichts läuft“.

Ist „Alles auf dem Mac“ ausdrücklich gewählt, aber nicht verfügbar, verhält sich MusicDesk wie „Automatisch“ zwischen Apple Music und Spotify. Die Knöpfe und die Fortschrittsleiste steuern immer die gerade aktive Quelle.

> **Wichtig – inoffizielle Schnittstelle:** „Alles auf dem Mac“ nutzt das **private** macOS-Framework *MediaRemote*. Apple hat den direkten Zugriff darauf ab macOS 15.4 eingeschränkt; der mitgelieferte Adapter umgeht das über das System-Programm `/usr/bin/perl`, das weiterhin berechtigt ist. Apple kann das mit jedem macOS-Update ändern. MusicDesk prüft deshalb **beim Start**, ob der Adapter funktioniert („Adapter-Test“). Klappt das nicht, schaltet MusicDesk **automatisch auf Apple Music und Spotify zurück** – das Widget funktioniert also in jedem Fall weiter. Den Status siehst du unter *Einstellungen → Quelle*.

---

## Voraussetzungen

- **macOS 13 Ventura oder neuer** (getestetes Ziel bis einschließlich macOS 27)
- **Intel-Mac oder Apple-Silicon-Mac** (M1, M2, M3, M4 …) – die App ist ein Universal Binary und läuft auf beiden nativ
- Mindestens eine Quelle: die **Apple-Music-App** (in macOS enthalten), **Spotify** oder eine andere App/ein Browser, die Medien abspielt
- Für den **Liquid-Glass-Effekt** der Fortschrittsleiste: macOS 26 (auf älteren Versionen wird Milchglas verwendet)

---

## Installation für Endnutzer (fertige App herunterladen)

### 1. App herunterladen

Repository: [github.com/lukestark-glitch/MusicDesk-Widget](https://github.com/lukestark-glitch/MusicDesk-Widget).

- **Empfohlen – GitHub Releases:** Öffne die Seite
  [Releases](https://github.com/lukestark-glitch/MusicDesk-Widget/releases) und lade bei der neuesten MusicDesk-Version die Datei **`MusicDesk-1.1.0.zip`** herunter.
  (Releases werden automatisch von GitHub Actions erstellt, sobald ein Tag wie `v1.1.0` veröffentlicht wird.)
- **Alternativ – Build-Artefakt:** Im Reiter
  [Actions](https://github.com/lukestark-glitch/MusicDesk-Widget/actions) den neuesten erfolgreichen Lauf des MusicDesk-Workflows öffnen und unten unter **„Artifacts“** die ZIP-Datei herunterladen. (Dafür musst du bei GitHub angemeldet sein. Das Artefakt ist eine ZIP, in der die eigentliche `MusicDesk-1.1.0.zip` steckt – ggf. zweimal entpacken.)

**Update von 1.0:** MusicDesk 1.0 über **Rechtsklick → „MusicDesk beenden“** schließen, die neue `MusicDesk.app` in den Ordner **Programme** ziehen und „Ersetzen“ wählen. Deine Einstellungen (Farbe, Position, Sperre, Autostart) bleiben erhalten. Weil die neue Version eine neue Signatur hat, fragt macOS ggf. erneut nach der Music-Erlaubnis und zeigt einmal die Gatekeeper-Warnung (Schritt 3).

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

### 4. Zugriff auf Apple Music / Spotify erlauben

Sobald MusicDesk zum ersten Mal mit Apple Music bzw. Spotify spricht, fragt macOS **einmal pro App**:
**„MusicDesk möchte auf Music zugreifen“** bzw. **„… auf Spotify zugreifen“** → **„OK“** klicken.

Ohne diese Erlaubnis kann das Widget für die jeweilige App weder den Song anzeigen noch die Wiedergabe steuern. Mehr dazu unter [Berechtigungen](#berechtigungen).

> Die Abfrage erscheint erst, wenn die jeweilige App läuft – das Widget startet Music oder Spotify nicht selbst.

Fertig! Das Widget erscheint unten mittig auf deinem Bildschirm.

---

## Installation per Skript (selbst bauen)

Wer die App lieber selbst aus dem Quellcode baut, braucht **Xcode** oder die **Command Line Tools**. Letztere installierst du im Terminal mit:

```bash
xcode-select --install
```

Für den mitgelieferten Adapter (Quelle „Alles auf dem Mac“) wird außerdem **CMake** benötigt. Ist [Homebrew](https://brew.sh) installiert, holt `build.sh` CMake bei Bedarf automatisch (`brew install cmake`); sonst bricht das Skript mit einem Hinweis ab.

Dann:

```bash
git clone https://github.com/lukestark-glitch/MusicDesk-Widget.git
cd MusicDesk-Widget
./scripts/install.sh
```

Das Skript baut die App, beendet eine evtl. laufende alte Version, kopiert `MusicDesk.app` nach `/Applications` und startet sie.
**Es erscheint keine Gatekeeper-Warnung**, weil selbst gebaute Apps kein Quarantäne-Merkmal (wie heruntergeladene Dateien) tragen.

Nur bauen, ohne zu installieren:

```bash
./scripts/build.sh
```

Das Ergebnis liegt dann in `dist/MusicDesk.app` und als ZIP in `dist/MusicDesk-1.1.0.zip`. Am Ende führt das Skript zur Information den Adapter-Test aus (ein Fehlschlag bricht den Build nicht ab).

---

## Bedienung

| Aktion | So geht's |
|---|---|
| **Widget verschieben** | Auf den **Songtitel** klicken und ziehen. Die Position wird gespeichert. |
| **Wiedergabe / Pause** | Mittlerer Knopf (▶ / ❚❚) |
| **Vorheriger / nächster Song** | Linker bzw. rechter Knopf (◀◀ / ▶▶) |
| **Im Song springen** | Auf die Fortschrittsleiste klicken oder den Regler ziehen (beim Ziehen werden Zeit und Restzeit angezeigt) |
| **Einstellungen** | **Rechtsklick** (oder Ctrl-Klick) auf Titel, Knöpfe oder Leiste → **„Einstellungen …“**, oder **⌘,** |

**Das Rechtsklick-Menü:**

- **Position sperren** – verhindert versehentliches Verschieben.
- **Beim Login starten** – Autostart ein/aus.
- **Update installieren … (1.x.y)** – erscheint ganz oben nur, wenn eine neue Version verfügbar ist.
- **Einstellungen …** (⌘,) – öffnet das Einstellungsfenster.
- **Über MusicDesk** – Versionsinfo.
- **MusicDesk beenden**

Die Farbauswahl ist aus dem Menü in das Einstellungsfenster umgezogen.

Wenn nichts abgespielt wird, zeigt das Widget **„Nichts läuft“**.

> **Wichtig:** MusicDesk hat **kein Dock-Symbol und kein Menüleisten-Symbol**. Beenden kannst du die App daher nur über **Rechtsklick → „MusicDesk beenden“** (oder über die Aktivitätsanzeige).

Klicks auf die leeren, durchsichtigen Stellen zwischen Text und Knöpfen gehen durch das Widget hindurch auf den Schreibtisch.

**Bedienungshilfen:** Alle Knöpfe und die Fortschrittsleiste sind für VoiceOver beschriftet („Vorheriger Titel“, „Wiedergabe“/„Pause“, „Nächster Titel“, „Wiedergabeposition“). Die Leiste lässt sich mit VoiceOver in 10-Sekunden-Schritten verstellen. Ist *Bewegung reduzieren* aktiv (Systemeinstellungen → Bedienungshilfen → Anzeige), entfallen Skalier-Animationen und die Laufschrift.

---

## Einstellungen

Das Einstellungsfenster öffnest du per **Rechtsklick → „Einstellungen …“** oder **⌘,**. Ganz oben zeigt eine **Live-Vorschau** das Widget mit einem Beispiel-Song – umschaltbar auf hellen oder dunklen Hintergrund. Alle Änderungen wirken **sofort**, auch auf das Widget auf dem Schreibtisch.

### Quelle

| Option | Werte | Standard |
|---|---|---|
| **Quelle** | Automatisch, Apple Music, Spotify, Alles auf dem Mac | Automatisch |
| Status | zeigt, ob „Alles auf dem Mac“ verfügbar ist (bzw. warum nicht) | – |
| **Quelle anzeigen** | kleines App-Symbol (z. B. Safari, Spotify) vor dem Titel | aus |

### Darstellung

| Option | Werte | Standard |
|---|---|---|
| **Farbe** | Schwarz, Weiß, Automatisch, Graphit, Blau, Lila, Pink, Rot, Orange, Gelb, Grün, Mint | Schwarz |
| **Eigene Farbe** | Farbwähler oder Hex-Code `#RRGGBB` (wählt automatisch „Eigene“) | `#000000` |
| **Lesbarkeits-Schatten** | dezenter Schein in der Gegenfarbe hinter Schrift, Knöpfen und Leiste | aus |
| **Künstler dezenter** | Künstler/Kanal mit 60 % Deckkraft | an |

„Automatisch“ richtet sich nach dem hellen/dunklen Erscheinungsbild von macOS, nicht nach dem Hintergrundbild.

### Fortschrittsleiste

| Option | Werte | Standard |
|---|---|---|
| **Deckkraft** | 15–100 % | 100 % |
| **Glas-Effekt** | Liquid Glass ab macOS 26, sonst Milchglas | aus |
| **Abgespielten Teil hervorheben** | abgespielter Teil in voller Farbe, Rest blasser | an |
| **Regler anzeigen** | Immer, Nur beim Überfahren, Nie | Immer |

### Titel

| Option | Werte | Standard |
|---|---|---|
| **Langer Titel** | Abkürzen (…), Laufschrift | Abkürzen (…) |

Die Laufschrift läuft nur, wenn der Text nicht ganz hineinpasst, und pausiert bei aktivem *Bewegung reduzieren*.

### Updates

| Option | Standard |
|---|---|
| Anzeige der installierten **Version** und des Such-Status | – |
| **Jetzt suchen** – sofort nach einer neuen Version suchen | – |
| **Automatisch nach Updates suchen** | an |
| **Update installieren …** – erscheint, wenn eine neue Version verfügbar ist | – |

### Allgemein

| Option | Standard |
|---|---|
| **Position sperren** | aus |
| **Beim Login starten** | an (beim ersten Start eingeschaltet) |
| **Auf Standard zurücksetzen** | setzt alle Darstellungs- und Quellen-Einstellungen zurück (nach Rückfrage). Position, Sperre und Autostart bleiben unverändert. |

---

## Berechtigungen

| Quelle | Erlaubnis | Wo änderbar |
|---|---|---|
| **Apple Music** | „MusicDesk möchte auf Music zugreifen“ – einmalig | Systemeinstellungen → Datenschutz & Sicherheit → **Automation** → MusicDesk → Music |
| **Spotify** | „MusicDesk möchte auf Spotify zugreifen“ – einmalig | Systemeinstellungen → Datenschutz & Sicherheit → **Automation** → MusicDesk → Spotify |
| **Alles auf dem Mac** | **keine** Erlaubnis nötig | – |

Jede Abfrage erscheint nur einmal und erst dann, wenn die jeweilige App läuft. Lehnst du eine ab, funktionieren die anderen Quellen trotzdem.

---

## Updates

MusicDesk hält sich ab Version 1.1 selbst aktuell (von 1.0 auf 1.1 bitte einmal von Hand aktualisieren, siehe [Installation](#installation-für-endnutzer-fertige-app-herunterladen)):

- **Suche:** Beim Start und danach **alle 24 Stunden** fragt MusicDesk bei den [GitHub-Releases](https://github.com/lukestark-glitch/MusicDesk-Widget/releases) von `lukestark-glitch/MusicDesk-Widget` nach, ob es eine neuere Version gibt. Es werden dabei keine persönlichen Daten übertragen – nur die öffentliche Release-Liste abgerufen.
- **Hinweis:** Gibt es ein Update, erscheint eine **dezente Mitteilung**. Bei der allerersten Mitteilung fragt macOS einmal, ob MusicDesk **Mitteilungen** senden darf (änderbar unter *Systemeinstellungen → Mitteilungen → MusicDesk*). Ohne diese Erlaubnis siehst du das Update trotzdem im Rechtsklick-Menü und in den Einstellungen.
- **Installieren:** **Rechtsklick → „Update installieren …“** oder *Einstellungen → Updates → „Update installieren …“*.
- **Einstellungen → Updates:** zeigt die installierte Version, **„Jetzt suchen“** und den Schalter **„Automatisch nach Updates suchen“** (Standard: an). Ist er aus, sucht MusicDesk nur noch, wenn du „Jetzt suchen“ klickst.

**Was beim Installieren passiert:**

1. Die neue `MusicDesk-<Version>.zip` wird aus dem GitHub-Release **heruntergeladen** und entpackt.
2. Die neue App wird **geprüft**: richtige Bundle-ID (`com.musicdesk.widget`), wirklich neuere Version, gültige Signatur.
3. Das **Quarantäne-Merkmal wird entfernt** – es erscheint also keine Gatekeeper-Warnung wie beim ersten Download.
4. Die App **ersetzt die bisherige an ihrem aktuellen Ort** (meist `/Applications`) und **startet neu**.

Geht dabei etwas schief, **bleibt die alte Version unverändert erhalten** und MusicDesk zeigt eine Fehlermeldung. Du kannst das Update dann jederzeit manuell von der Release-Seite installieren.

> **Hinweise:**
> - Nach einem Update fragt macOS unter Umständen **noch einmal nach der Apple-Music- bzw. Spotify-Erlaubnis**. Das liegt an der Ad-hoc-Signatur, die sich mit jeder Version ändert – einfach wieder „OK“ klicken.
> - Der Ordner, in dem `MusicDesk.app` liegt, muss für deinen Benutzer **beschreibbar** sein (bei `/Applications` als Administrator normalerweise der Fall). Sonst schlägt die Installation fehl und die alte Version bleibt bestehen.

---

## Autostart

Beim **ersten Start** trägt sich MusicDesk automatisch als Anmeldeobjekt ein, startet also künftig bei jeder Anmeldung mit.

Abschalten bzw. wieder einschalten:

- **Rechtsklick → „Beim Login starten“**, oder
- **Einstellungen → Allgemein → „Beim Login starten“**, oder
- **Systemeinstellungen → Allgemein → Anmeldeobjekte** (MusicDesk unter „Beim Anmelden öffnen“ bzw. „Im Hintergrund erlauben“).

---

## Deinstallation

**Per Skript** (aus dem Ordner `MusicDesk-Widget`):

```bash
./scripts/uninstall.sh
```

**Von Hand:**

1. MusicDesk beenden: **Rechtsklick → „MusicDesk beenden“**.
2. `MusicDesk.app` aus dem Ordner **Programme** in den Papierkorb ziehen (der Adapter steckt in der App und wird mit entfernt).
3. Einstellungen löschen (Terminal):
   ```bash
   defaults delete com.musicdesk.widget
   ```
4. Anmeldeobjekt entfernen: **Systemeinstellungen → Allgemein → Anmeldeobjekte** – falls MusicDesk dort noch steht, entfernen (verschwindet normalerweise mit dem Löschen der App).
5. Optional die Music-/Spotify-Erlaubnis zurücksetzen:
   ```bash
   tccutil reset AppleEvents com.musicdesk.widget
   ```

---

## Fehlerbehebung

**Das Widget zeigt „Nichts läuft“, obwohl Musik spielt / es wurde nie nach der Erlaubnis gefragt**
Wahrscheinlich fehlt die Erlaubnis für Apple Music bzw. Spotify oder wurde abgelehnt. Prüfe *Systemeinstellungen → Datenschutz & Sicherheit → Automation → MusicDesk*. Oder setze die Erlaubnis zurück und starte die App neu – dann wird erneut gefragt:

```bash
tccutil reset AppleEvents com.musicdesk.widget
```

Danach MusicDesk beenden (Rechtsklick → „MusicDesk beenden“) und wieder öffnen. Prüfe außerdem unter *Einstellungen → Quelle*, ob die richtige Quelle gewählt ist.

**YouTube (oder ein anderes Video im Browser) wird nicht angezeigt**
1. Unter *Einstellungen → Quelle* **„Alles auf dem Mac“** oder **„Automatisch“** wählen.
2. Den **Status** darunter prüfen. Steht dort „nicht verfügbar“, hat der Adapter-Test beim Start nicht geklappt (z. B. nach einem macOS-Update, das die inoffizielle Schnittstelle gesperrt hat). MusicDesk nutzt dann automatisch Apple Music und Spotify – Browser-Videos können in diesem Fall nicht angezeigt werden. MusicDesk einmal neu starten testet erneut.
3. Der Browser muss die Wiedergabe an macOS melden (*Media Session*). Test: Erscheint das Video im **Kontrollzentrum** unter „Läuft gerade“? Wenn nicht, kann auch MusicDesk es nicht sehen. Safari und Chrome melden YouTube normalerweise; bei manchen Seiten oder Browser-Einstellungen (z. B. Hardware-Medientasten deaktiviert) fehlt die Meldung.
4. Wer selbst baut, kann den Adapter-Test im Terminal prüfen: `./scripts/build.sh` zeigt das Ergebnis am Ende an.

**Der Glas-Effekt sieht aus wie Milchglas / nicht wie Liquid Glass**
Das ist richtig so: **Liquid Glass gibt es erst ab macOS 26.** Auf älteren Versionen verwendet MusicDesk als Ersatz ein Milchglas-Material.

**Das Widget ist unsichtbar (z. B. schwarze Schrift auf dunklem Hintergrundbild)**
Das Widget ist trotzdem da – man sieht es nur nicht. Ein Rechtsklick wirkt allerdings nur **genau auf Titel, Knöpfen oder Leiste**, nicht auf den leeren Flächen dazwischen. Versuche es unten mittig auf dem Bildschirm (Standardposition) und wähle in den Einstellungen eine andere Farbe oder den Lesbarkeits-Schatten. Alternativ per Terminal umstellen und die App neu starten:

```bash
defaults write com.musicdesk.widget colorMode white
```

(Werte: `black`, `white`, `automatic`, `graphite`, `blue`, `purple`, `pink`, `red`, `orange`, `yellow`, `green`, `mint`, `custom`.) Alle Einstellungen inklusive Position setzt du mit `defaults delete com.musicdesk.widget` zurück.

**Das Widget ist außerhalb des Bildschirms (z. B. nach Abstecken eines Monitors)**
Normalerweise holt MusicDesk sich beim Start selbst zurück auf einen sichtbaren Bildschirm. Falls nicht: App beenden, dann

```bash
defaults delete com.musicdesk.widget
```

und neu starten – das Widget erscheint wieder unten mittig.

**Nach dem erneuten Bauen (oder einem Update) fragt macOS wieder nach der Music-/Spotify-Erlaubnis**
Das ist normal: Jeder neue Build erhält eine neue (Ad-hoc-)Signatur, und macOS behandelt ihn wie eine neue App. Einfach wieder „OK“ klicken. Falls die Abfrage nicht kommt, siehe oben (`tccutil reset …`).

**⌘, öffnet die Einstellungen nicht**
Das Kürzel wirkt, sobald MusicDesk aktiv ist (z. B. nach einem Klick auf das Widget oder wenn das Einstellungsfenster offen ist). Sonst einfach **Rechtsklick → „Einstellungen …“**.

**Das automatische Update schlägt fehl**
Die alte Version bleibt in diesem Fall erhalten. Häufige Ursachen: keine Internetverbindung, oder der Ordner mit `MusicDesk.app` ist nicht beschreibbar (z. B. App liegt auf einem fremden Benutzerkonto oder schreibgeschützten Volume). Lade dann `MusicDesk-<Version>.zip` von der [Release-Seite](https://github.com/lukestark-glitch/MusicDesk-Widget/releases) und installiere sie wie oben beschrieben.

**Der Autostart funktioniert nicht**
Prüfe unter *Systemeinstellungen → Allgemein → Anmeldeobjekte*, ob MusicDesk eingetragen und erlaubt ist, und schalte im Rechtsklick-Menü „Beim Login starten“ aus und wieder ein. Die App sollte in `/Applications` liegen.

**Apple Music oder Spotify startet nicht, wenn ich auf ▶ klicke**
Das ist **Absicht**. MusicDesk öffnet Apple Music und Spotify niemals von selbst – es soll nicht ungefragt Programme starten. Öffne die App einmal selbst, danach funktionieren alle Knöpfe.

---

## Hinweis zu Signatur und Apple-Entwicklerkonto

- Für MusicDesk ist **kein kostenpflichtiges Apple-Developer-Konto** nötig – weder zum Benutzen noch zum Bauen.
- Die App ist **ad-hoc signiert** (lokale Signatur ohne Apple-Zertifikat), einschließlich des mitgelieferten Adapters. Deshalb die einmalige Gatekeeper-Warnung beim heruntergeladenen Build.
- Die App **läuft dauerhaft**. Es gibt **kein Ablaufen nach 7 Tagen** wie bei iOS-Apps mit kostenlosen Provisioning-Profilen – MusicDesk ist eine normale Mac-App, für die diese Einschränkung nicht gilt.

---

## Für Entwickler

### Projektstruktur

```
MusicDesk-Widget/
├── .github/workflows/build.yml    # CI: Build auf macOS 14/15/26, Release bei Tag v*
├── Package.swift                  # Swift Package (swift-tools 5.9, macOS 13+)
├── Sources/MusicDesk/
│   ├── App/                       # main.swift, AppDelegate, Settings(Keys), LoginItem, Kontextmenü, Updater
│   ├── Media/                     # NowPlaying, MediaSource, MediaManager,
│   │                              # Apple-Music-, Spotify- und System-Quelle, AppleScriptRunner
│   └── UI/                        # NSPanel-Fenster, WidgetView, TitleView/Laufschrift,
│                                  # ProgressBar, Einstellungsfenster
├── ThirdParty/
│   └── mediaremote-adapter/       # eingebundener Adapter (BSD-3), siehe VENDORED.md
├── Resources/
│   ├── Info.plist                 # Bundle-ID com.musicdesk.widget, LSUIElement
│   ├── AppIcon.icns               # wird von scripts/make_icon.py erzeugt
│   └── AppIcon.png                # Icon als PNG (1024 px)
├── scripts/
│   ├── build.sh                   # Universal-Build + Adapter (CMake) + App-Bundle + Ad-hoc-Signatur + ZIP
│   ├── install.sh                 # bauen und nach /Applications installieren
│   ├── uninstall.sh               # vollständig entfernen
│   ├── check-bundle.sh            # prüft das fertige App-Bundle (Info.plist, Architekturen, Signatur, Adapter)
│   └── make_icon.py               # App-Icon programmatisch erzeugen (Pillow)
├── docs/
│   └── ENTSCHEIDUNGEN.md          # Design- und Technik-Entscheidungen
├── CHANGELOG.md
├── LICENSE
├── LICENSE-THIRD-PARTY.md         # Lizenz des mediaremote-adapters
└── README.md
```

Der CI-Workflow liegt im Repository-Wurzelverzeichnis: `.github/workflows/build.yml`.

### Technik

- **Swift 5.9**, **SwiftUI** für die Oberfläche, eingebettet per `NSHostingView`; Einstellungen per `@AppStorage` (live zwischen Widget und Einstellungsfenster)
- **AppKit `NSPanel`** (randlos, transparent, nicht aktivierend) auf Fensterebene *Schreibtisch-Symbole + 1*, auf allen Spaces
- **`MediaManager`** wählt die aktive Quelle und reicht deren Zustand an die Oberfläche weiter
- **Apple Music / Spotify:** `NSAppleScript` auf einer eigenen seriellen Hintergrund-Queue; zusätzlich die verteilten Benachrichtigungen `com.apple.Music.playerInfo` bzw. `com.spotify.client.PlaybackStateChanged` und 1-Sekunden-Abfrage (nur solange die App läuft)
- **Alles auf dem Mac:** [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) (Perl-Skript + Framework + Test-Programm im App-Bundle), gestartet als Kindprozess `/usr/bin/perl … stream`; JSON-Zeilen über stdout
- Liquid Glass (`glassEffect`) nur ab macOS 26, Symbol-Übergänge ab macOS 14 – jeweils per Verfügbarkeitsprüfung, ältere Systeme erhalten einen gleichwertigen Ersatz
- **`SMAppService`** (ServiceManagement) für den Autostart
- **Eigener Updater** (`UpdateController`/`UpdateInstaller`): GitHub-Releases-API, Download, Prüfung von Bundle-ID, Version und Signatur, Austausch des Bundles und Neustart
- **Swift Package Manager**, kein Xcode-Projekt nötig; **CMake** für den Adapter
- **Universal Binary** (arm64 + x86_64), ad-hoc signiert

Einstellungen (UserDefaults-Domain `com.musicdesk.widget`):

- aus 1.0: `colorMode`, `positionLocked`, `windowOriginX`, `windowOriginY`, `windowScreenID`, `windowScreenName`, `didAttemptInitialLoginRegistration`
- neu in 1.1: `sourcePreference`, `showSourceIcon`, `customColorHex`, `readabilityShadow`, `barOpacity`, `barGlass`, `highlightPlayed`, `knobVisibility`, `titleOverflow`, `dimArtist`, `autoCheckUpdates`, `lastUpdateCheck`

Hintergründe zu den einzelnen Entscheidungen: [docs/ENTSCHEIDUNGEN.md](docs/ENTSCHEIDUNGEN.md).

### CI

Der Workflow [`.github/workflows/build.yml`](.github/workflows/build.yml) läuft bei jedem Push und Pull-Request, bei Tags `v*` sowie manuell (*workflow_dispatch*) – parallel auf **macOS 14, 15 und 26**, damit der Code sowohl mit älteren SDKs als auch mit dem neuesten Xcode kompiliert. Er baut die App mit `scripts/build.sh`, prüft Architekturen (`lipo`), Signatur (`codesign -v`), `Info.plist` und den eingebetteten Adapter, gibt das Ergebnis des Adapter-Tests aus (ohne den Lauf scheitern zu lassen) und lädt die ZIP als Artefakt hoch. Das Release wird nur vom neuesten Runner (macOS 26) erstellt.

### Release erstellen

```bash
git tag v1.1.0
git push origin v1.1.0
```

Alternativ ohne Tag: Im Reiter *Actions* → Workflow „MusicDesk“ → *Run workflow* mit Häkchen „GitHub-Release … erstellen“ starten. Der Workflow baut dann die App und legt automatisch ein GitHub-Release mit `MusicDesk-1.1.0.zip` an. Für eine neue Version vorher `CFBundleShortVersionString`/`CFBundleVersion` in `Resources/Info.plist` anpassen – `scripts/build.sh` liest die Version von dort und benennt die ZIP entsprechend (`MusicDesk-<Version>.zip`). Änderungen bitte im [CHANGELOG](CHANGELOG.md) eintragen.

---

## Lizenz und Drittanbieter-Komponenten

MusicDesk steht unter der **MIT-Lizenz** – siehe [LICENSE](LICENSE).

MusicDesk enthält den **[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)** von Jonas van den Berg (ungive) unter der **BSD-3-Clause-Lizenz**. Lizenztext und Hinweise: [LICENSE-THIRD-PARTY.md](LICENSE-THIRD-PARTY.md); Herkunft und Version: [ThirdParty/mediaremote-adapter/VENDORED.md](ThirdParty/mediaremote-adapter/VENDORED.md).

MusicDesk ist ein unabhängiges Projekt und steht in keiner Verbindung zu Apple Inc. oder Spotify AB. „Apple Music“ und „macOS“ sind Marken von Apple Inc., „Spotify“ ist eine Marke von Spotify AB. „YouTube“ ist eine Marke von Google LLC.
