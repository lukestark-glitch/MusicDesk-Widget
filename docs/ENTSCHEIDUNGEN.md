# Entscheidungen

Dieses Dokument hält fest, **was** bei MusicDesk wie gelöst wurde und **warum**. Neue Entscheidungen bitte unten anfügen.

---

## 1. NSAppleScript statt ScriptingBridge

**Entscheidung:** Die Kommunikation mit Apple Music läuft über `NSAppleScript`, nicht über ScriptingBridge (`SBApplication`).

**Warum:**
- ScriptingBridge braucht für Swift entweder generierte Header (`sdef | sdp`) oder unsauberes dynamisches Aufrufen per `value(forKey:)`/`perform` – beides fehleranfällig und schwer ohne Xcode zu pflegen.
- `SBApplication` startet die Ziel-App unter Umständen schon beim Zugriff auf Eigenschaften – genau das wollen wir nicht (siehe 2).
- Mit AppleScript bekommen wir **alle Werte in einem einzigen Aufruf** (Status, Titel, Künstler, Position, Dauer) statt fünf einzelner AppleEvents.

**Wie:**
- `NSAppleScript` ist nicht thread-sicher. Alle Skripte werden deshalb auf **einer eigenen seriellen Hintergrund-`DispatchQueue`** einmal kompiliert und dort wiederverwendet. Ergebnisse gehen zurück an den Main Actor. Die Oberfläche blockiert nie, auch wenn Music hängt.
- Das Abfrage-Skript gibt eine **AppleScript-Liste** `{state, name, artist, position, duration}` zurück. Diese wird als `NSAppleEventDescriptor`-Liste ausgelesen (`atIndex(1)` …, `doubleValue` für Zahlen). So umgehen wir Probleme mit Zahl→Text-Umwandlung (Dezimalkomma bei deutscher Systemsprache) und mit Trennzeichen im Songtitel.
- Der Status wird im Skript per Vergleich (`if ps is playing …`) zu `"playing"`/`"paused"`/`"stopped"` umgesetzt (unabhängig von der Systemsprache); der Zugriff auf `current track` ist in `try` gekapselt, weil es im Zustand „gestoppt“ keinen aktuellen Titel gibt.
- Fehlt die Erlaubnis (Fehler −1743), zeigt das Widget den Leerlauf-Zustand, meldet den Fehler nicht wiederholt und versucht es bei der nächsten Abfrage erneut.

## 2. Apple Music wird nie gestartet

**Entscheidung:** MusicDesk sendet nur dann AppleEvents an Music, wenn `NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music")` nicht leer ist.

**Warum:** Ein AppleEvent an eine nicht laufende App startet diese. Ein Desktop-Widget, das beim Anmelden oder jede Sekunde ungefragt Music öffnet, wäre extrem lästig. Läuft Music nicht, zeigt das Widget „Nichts läuft“; auch die Knöpfe starten Music bewusst nicht.

## 3. Benachrichtigung + 1-s-Abfrage + lokale Interpolation

**Entscheidung:** Drei Mechanismen kombiniert:
1. **`DistributedNotificationCenter`** mit `com.apple.Music.playerInfo` – Music meldet Titelwechsel, Play/Pause sofort. Die Daten aus `userInfo` (Name, Artist, Player State, Total Time) werden direkt übernommen, danach folgt eine vollständige Abfrage.
2. **Timer, 1 Sekunde** – fängt alles ab, was die Benachrichtigung nicht meldet (Spulen in Music selbst, verpasste Ereignisse) und gleicht die Position ab.
3. **Lokale Interpolation** – zwischen den Abfragen wird die Position aus `position + (jetzt − updatedAt)` hochgerechnet und ca. 30-mal pro Sekunde gezeichnet. Die Leiste läuft flüssig, ohne Music 30-mal pro Sekunde zu fragen.

Zusätzlich beobachtet `NSWorkspace` Start und Beenden von Music, damit das Widget sofort reagiert.

**Spulen:** Nach einem Sprung wird der Zustand sofort lokal („optimistisch“) gesetzt. Abfrage-Ergebnisse, die kurz danach (ca. 1 s Schonfrist) mit einer veralteten Position eintreffen, werden ignoriert – sonst springt der Regler kurz zurück.

## 4. Fenster: nicht aktivierendes NSPanel auf Schreibtisch-Symbol-Ebene + 1

**Entscheidung:** Randloses, transparentes `NSPanel` (`.nonactivatingPanel`), `isOpaque = false`, `backgroundColor = .clear`, kein Schatten, Ebene `CGWindowLevelForKey(.desktopIconWindow) + 1`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]`.

**Warum:**
- Ebene *Schreibtisch-Symbole + 1* liegt genau **über Hintergrundbild und Symbolen**, aber **unter allen normalen Fenstern** – wie ein Teil des Schreibtischs.
- `canJoinAllSpaces` + `stationary`: auf allen Spaces sichtbar, bewegt sich bei Mission Control nicht mit.
- Nicht aktivierend: Ein Klick auf einen Knopf holt MusicDesk nicht nach vorn und nimmt der gerade benutzten App nicht den Fokus.
- `LSUIElement` + `.accessory`: kein Dock-Symbol, nicht im ⌘-Tab-Umschalter.

## 5. Klickflächen mit 0,011 Deckkraft

**Entscheidung:** Knöpfe und Fortschrittsleiste liegen auf einer fast unsichtbaren Fläche (`Color.black.opacity(0.011)`), die Leiste hat eine ca. 30 pt hohe Trefferzone, Knöpfe mindestens 36 × 36 pt.

**Warum:** macOS lässt Mausklicks bei transparenten Fenstern an **vollständig durchsichtigen Pixeln** durch das Fenster hindurch. Ohne Hintergrund müsste man exakt die dünne Linie oder das schmale Symbol treffen. Bei 0,011 Deckkraft ist die Fläche für das Auge unsichtbar, zählt für macOS aber als „getroffen“. Ein kleinerer Wert kann auf manchen Systemen auf 0 gerundet werden. Die übrigen leeren Flächen bleiben voll durchsichtig und damit durchklickbar. `ignoresMouseEvents` wird bewusst nicht gesetzt.

## 6. „First Mouse“

**Entscheidung:** Die Ansicht akzeptiert den ersten Mausklick (`acceptsFirstMouse` → `true`).

**Warum:** Da das Fenster nie aktiv ist, würde der erste Klick sonst nur das Fenster „aufwecken“ und nicht den Knopf auslösen – man müsste jeden Knopf zweimal klicken.

## 7. Autostart mit SMAppService beim ersten Start

**Entscheidung:** Beim allerersten Start (UserDefaults-Merker `didAttemptInitialLoginRegistration`) ruft die App `SMAppService.mainApp.register()` auf. Danach entscheidet nur noch der Nutzer (Menü oder Systemeinstellungen).

**Warum:**
- `SMAppService` (ab macOS 13) ist die aktuelle, von Apple vorgesehene API; keine Hilfs-App und keine veralteten `LSSharedFileList`-Aufrufe nötig. Der Eintrag erscheint sauber unter *Anmeldeobjekte*.
- Ein Desktop-Widget soll einfach immer da sein – daher standardmäßig an.
- Der Merker sorgt dafür, dass ein vom Nutzer abgeschalteter Autostart nicht bei jedem Start wieder eingeschaltet wird.
- Fehler werden mit `os.Logger` protokolliert, die App stürzt nie deswegen ab.

## 8. Ad-hoc-Signatur

**Entscheidung:** Die App wird mit `codesign --force --deep -s -` ad-hoc signiert; keine Beglaubigung (Notarisierung), kein Hardened Runtime, keine Sandbox.

**Warum:**
- Kein kostenpflichtiges Apple-Developer-Konto nötig.
- Apple-Silicon-Macs führen unsignierten Code gar nicht aus – eine Ad-hoc-Signatur reicht dafür aus.
- Die Sandbox würde AppleEvents an Music nur mit zusätzlichen Entitlements erlauben; ohne Sandbox genügt `NSAppleEventsUsageDescription`.
- **Nachteil:** Heruntergeladene Builds lösen einmalig die Gatekeeper-Warnung aus (siehe README). Außerdem ändert sich die Signatur bei jedem Build, daher fragt macOS nach einem Neubau ggf. erneut nach der Music-Erlaubnis.

## 9. Universal Binary über SPM mit Rückfallebene

**Entscheidung:** `swift build -c release --arch arm64 --arch x86_64`. Schlägt das fehl (manche Toolchain-Versionen), baut `build.sh` beide Architekturen einzeln (`--triple arm64-apple-macosx13.0` / `x86_64-apple-macosx13.0`) und fügt sie mit `lipo -create` zusammen. Am Ende prüft das Skript per `lipo -archs`, dass beide Architekturen enthalten sind.

**Warum:** Kein Xcode-Projekt nötig (reines Swift Package, baut auch nur mit den Command Line Tools), und eine einzige Datei läuft nativ auf Intel und Apple Silicon. Das App-Bundle (`Info.plist`, Icon) setzt `build.sh` selbst zusammen.

## 10. Programmatisch erzeugtes Icon

**Entscheidung:** `scripts/make_icon.py` zeichnet das App-Icon mit Pillow (weiße Note aus Grundformen auf rot-pinkem Verlauf, abgerundetes Quadrat) und schreibt `Resources/AppIcon.icns` und `AppIcon.png`.

**Warum:** Keine Fremd-Grafiken mit unklarer Lizenz, keine Abhängigkeit von Schriftarten, reproduzierbar und ohne Grafikprogramm änderbar. Bewusst „Apple-Music-ähnlich“, aber eigenständig.

## 11. Standardfarbe Schwarz

**Entscheidung:** Standard ist **Schwarz**; wählbar sind Schwarz, Weiß und Automatisch (folgt dem Erscheinungsbild von macOS).

**Warum:** Klare, vorhersagbare Darstellung ab dem ersten Start. „Automatisch“ richtet sich nach Hell/Dunkel-Modus, nicht nach dem Hintergrundbild – das wäre für helle Bilder im Dunkelmodus falsch. Wer ein dunkles Hintergrundbild hat, stellt auf Weiß um.

## 12. Eigenes Repository + Build über GitHub Actions

**Entscheidung:** Das Projekt liegt im eigenen Repository `lukestark-glitch/musicdesk-widget` (Projektdateien im Wurzelverzeichnis). Der verbindliche Build läuft auf einem **macOS-Runner von GitHub Actions** (`.github/workflows/build.yml`); ein Tag `v*` erzeugt automatisch ein GitHub-Release mit der ZIP.

**Warum:** Die Entwicklungsumgebung war ein Linux-Container ohne Swift/Xcode – ein lokaler macOS-Build war dort unmöglich. Der CI-Build prüft auf echter macOS-Hardware, dass die App kompiliert, das Bundle korrekt ist und `lipo -archs` beide Architekturen (arm64 + x86_64) enthält. Lokal auf dem Mac funktioniert `./scripts/build.sh` identisch.

---

# Version 1.1

## 13. Quellen-Abstraktion: `MediaSource` + `MediaManager`

**Entscheidung:** Jede Quelle (Apple Music, Spotify, System) implementiert das Protokoll `MediaSource` und liefert einen gemeinsamen Zustand `NowPlaying`. Nur der `MediaManager` kennt die Quellen; die Oberfläche bekommt ausschließlich `NowPlaying` und vier Aktionen (`WidgetActions`).

**Warum:** Die Oberfläche bleibt unabhängig davon, woher die Daten kommen. Neue Quellen brauchen keine UI-Änderung, und das Einstellungsfenster kann dieselbe `WidgetView` mit Beispieldaten (`NowPlaying.sample`) und `WidgetActions.noop` als Live-Vorschau zeigen. Es laufen nur die Quellen, die gerade gebraucht werden – die System-Quelle wird gestoppt, wenn sie nicht aktiv ist; die App-Quellen fragen nur ab, solange ihre App läuft.

## 14. Systemweite Wiedergabe über den upstream-mediaremote-adapter

**Entscheidung:** Für „Alles auf dem Mac“ wird [ungive/mediaremote-adapter](https://github.com/ungive/mediaremote-adapter) unverändert unter `ThirdParty/mediaremote-adapter/` eingebunden (fester Commit, siehe `VENDORED.md`) und als Kindprozess `/usr/bin/perl mediaremote-adapter.pl <Framework> <Test-Client> stream …` gestartet.

**Warum:**
- Seit macOS 15.4 dürfen normale Apps das private Framework *MediaRemote* nicht mehr direkt abfragen. Das System-Programm `/usr/bin/perl` darf es weiterhin; der Adapter nutzt genau das.
- Upstream statt des Forks von ejbills: Upstream hat die dokumentierte Kommandozeile (`stream`, `send`, `seek`, `test`) inklusive Test-Client. Der Fork ändert die Kommandozeile (`loop`/`get`) und sucht seine Dateien über `Bundle.module`/`Bundle(for:)` – das funktioniert in einem von Hand zusammengesetzten SPM-App-Bundle nicht.
- Ein lang laufender `stream`-Prozess mit zeilenweisem JSON ist sparsamer und schneller als wiederholtes Abfragen. Er wird bei Absturz mit Wartezeit neu gestartet und beim Beenden von MusicDesk sicher beendet.
- Der Adapter steht unter BSD-3; der Lizenztext liegt in `LICENSE-THIRD-PARTY.md`.

## 15. Adapter-Test beim Start + automatischer Rückfall

**Entscheidung:** Beim Start läuft einmal `… test` (Zeitlimit 5 s). Nur wenn der Test klappt, gilt die System-Quelle als verfügbar. Sonst – oder wenn Dateien im Bundle fehlen – verhält sich MusicDesk wie „Automatisch“ zwischen Apple Music und Spotify. Der Status steht im Einstellungsfenster.

**Warum:** Die Schnittstelle ist inoffiziell; Apple kann sie mit jedem Update schließen. Das Widget soll dann nicht kaputt wirken („Nichts läuft“ trotz Musik), sondern still auf die offiziell steuerbaren Apps zurückfallen. Der Build führt den Test nur informativ aus und scheitert nie daran, weil CI-Runner keine Wiedergabe haben.

## 16. Reihenfolge bei „Automatisch“

**Entscheidung:** System-Quelle, wenn verfügbar → Apple Music, falls spielend → Spotify, falls spielend → Apple Music, falls geöffnet → Spotify, falls geöffnet → nichts.

**Warum:** Die System-Quelle deckt alle Apps ab (auch Apple Music und Spotify) und braucht keine Erlaubnis. Ohne sie gewinnt, was gerade **spielt**, damit z. B. ein pausiertes Apple Music im Hintergrund nicht ein spielendes Spotify verdeckt. Bei Gleichstand hat Apple Music Vorrang, weil es in macOS enthalten ist.

## 17. Spotify per AppleScript, nie ungefragt gestartet

**Entscheidung:** Spotify wird wie Apple Music per `NSAppleScript` gesteuert (Bundle-ID `com.spotify.client`) und zusätzlich über `com.spotify.client.PlaybackStateChanged` beobachtet. Spotify liefert die Dauer in Millisekunden, die Position in Sekunden – das wird beim Einlesen vereinheitlicht. Wie bei Music (Entscheidung 2) gehen AppleEvents nur an eine laufende App.

**Warum:** Spotify hat keine andere lokale Schnittstelle ohne Anmeldung/Web-API. Die Erlaubnis wird – wie bei Music – einmal pro App abgefragt; der Berechtigungstext nennt beide Apps.

## 18. Einstellungen über `@AppStorage`, Schlüssel zentral in `SettingsKeys.swift`

**Entscheidung:** Alle Darstellungs-Einstellungen liegen in `UserDefaults` unter festen Schlüsseln (`SettingsKey`) mit Standardwerten (`SettingsDefault`). SwiftUI-Ansichten lesen sie direkt per `@AppStorage`, AppKit-Code über `UserDefaults.standard`. Die 1.0-Schlüssel (`colorMode`, `positionLocked` …) behalten ihren Namen.

**Warum:** Widget, Vorschau und Einstellungsfenster bleiben ohne eigenes Benachrichtigungssystem live synchron. Updates von 1.0 übernehmen die bisherigen Einstellungen. Die Standardwerte entsprechen dem 1.0-Aussehen – wer nichts ändert, sieht keinen Unterschied. „Auf Standard zurücksetzen“ löscht nur die Darstellungs-/Quellen-Schlüssel, nicht Position und Autostart.

## 19. Eigenes Einstellungsfenster statt Untermenüs

**Entscheidung:** Die Farbwahl wandert aus dem Rechtsklick-Menü in ein normales Fenster („MusicDesk – Einstellungen“, `Form` mit `.grouped`-Stil) mit Live-Vorschau; ⌘, öffnet es. Das Menü bleibt kurz: Position sperren, Beim Login starten, Einstellungen …, Über, Beenden.

**Warum:** Mit 1.1 gibt es über ein Dutzend Optionen – in Untermenüs wäre das unübersichtlich und ohne Vorschau. Das gruppierte Formular entspricht dem Aufbau der macOS-Systemeinstellungen. Da das Widget-Fenster die App nie aktiviert, aktiviert das Öffnen der Einstellungen die App bewusst, damit das Fenster nach vorn kommt und ⌘, / ⌘Q funktionieren.

## 20. Glas-Effekt mit Verfügbarkeitsprüfung und Ersatz

**Entscheidung:** Der Glas-Effekt der Leiste nutzt `glassEffect()` (Liquid Glass) nur ab macOS 26 – im Code doppelt abgesichert mit `if #available(macOS 26.0, *)` und `#if compiler(>=6.2)`. Auf älteren Systemen (und mit älteren SDKs gebaut) wird `.ultraThinMaterial` mit der Vordergrundfarbe gemischt verwendet.

**Warum:** Die App soll weiterhin ab macOS 13 laufen und auch mit älteren Xcode-Versionen kompilieren (CI baut deshalb auf macOS 14, 15 und 26). `#available` allein reicht nicht, weil ältere SDKs das Symbol gar nicht kennen.

## 21. Knöpfe nach den Apple Human Interface Guidelines

**Entscheidung:**
- SF Symbols (`backward.fill`, `play.fill`/`pause.fill`, `forward.fill`) wie in 1.0; der Wechsel Wiedergabe ↔ Pause nutzt ab macOS 14 den nativen Symbol-Übergang `.contentTransition(.symbolEffect(.replace))`, auf macOS 13 wechselt das Symbol sofort.
- **Überfahren:** Symbol wächst dezent um ca. 6 % (Feder-Animation, Antwortzeit 0,3 s). Eine Hover-Fläche wie bei Symbolleisten-Knöpfen ist bei einem hintergrundlosen Widget nicht möglich; eine Abdunklung würde wie „gedrückt“ aussehen.
- **Gedrückt:** 50 % Deckkraft (wie 1.0) und leichtes Verkleinern auf 92 %, schnelle Feder (0,2 s).
- Der rechte Knopf skaliert um seine **rechte Kante**, damit das Symbol bündig mit dem Ende der Fortschrittsleiste bleibt (Figma-Layout).
- Mit *Bewegung reduzieren* entfällt jede Skalierung und der Symbol-Übergang; nur die Deckkraft ändert sich.
- Deutsche VoiceOver-Beschriftungen („Vorheriger Titel“, „Wiedergabe“/„Pause“, „Nächster Titel“) und Tooltips (`.help`) beschreiben die Aktion („Abspielen“/„Pausieren“).
- Die Knöpfe bleiben auch bei „Nichts läuft“ voll sichtbar und bedienbar (wie 1.0) – sie werden einfach an die aktive Quelle weitergereicht und starten keine App.
- Trefferflächen weiterhin mindestens 36 × 36 pt mit 0,011-Hintergrund (Entscheidung 5); das Layout (560 × 114, Ränder 32 pt, Zeilenmitten 43/71 pt) bleibt unverändert.

**Warum:** Die Rückmeldung soll spürbar, aber zurückhaltend sein – das Widget ist Teil des Schreibtischs, kein Bedienfeld. Federn mit hoher Dämpfung wirken nativ und schwingen nicht nach.

## 22. Lesbarkeits-Schatten statt Hintergrund

**Entscheidung:** Optionaler, standardmäßig ausgeschalteter Schein in der Gegenfarbe (bei heller Schrift schwarz, sonst weiß): weicher Schatten (Radius 8 pt, 25 %) plus enge Kontur (Radius 2 pt, 12 %), ohne Versatz. Ist die Option aus, bleiben die Schatten mit 0 % Deckkraft im View-Baum, damit sich beim Umschalten die Struktur nicht ändert (keine zurückgesetzten Hover-/Laufschrift-Zustände).

**Warum:** Ein Kasten würde dem Grundgedanken „nur Inhalt auf dem Hintergrundbild“ widersprechen. Ein zentrierter, weicher Schein hebt Schrift auf unruhigen Bildern ab, ohne wie ein klassischer Schlagschatten zu wirken. Ob die Schrift hell ist, wird aus der Leuchtdichte der gewählten Farbe berechnet (Schwarz/Weiß/Automatisch direkt).

## 23. Laufschrift nur bei Bedarf und mit Rücksicht auf „Bewegung reduzieren“

**Entscheidung:** Lange Titel werden standardmäßig wie in 1.0 abgekürzt. Die Laufschrift startet nur, wenn der Text wirklich nicht passt: 2 s Pause, dann 30 pt/s, nahtlose Schleife mit 40 pt Abstand, weiche Ränder. Bei *Bewegung reduzieren* wird abgekürzt. Titel und Künstler sind **ein** zusammengesetzter Text, damit Abkürzen und Laufschrift den ganzen String betreffen.

**Warum:** Dauernde Bewegung am Bildschirmrand lenkt ab; Apple empfiehlt, Animationen bei reduzierter Bewegung zu vermeiden. Die Animation läuft über `TimelineView` statt `repeatForever`, damit sie bei Titelwechseln sauber neu startet.

## 24. Fortschrittsleiste: Hover, Zeitanzeige, Live

**Entscheidung:** Beim Überfahren wird die Leiste 5 → 7 pt dick (Feder). Beim Ziehen erscheinen aktuelle Zeit links und Restzeit („-1:23“) rechts unter der Leiste (11 pt, Ziffern gleicher Breite) und verschwinden kurz nach dem Loslassen. Ohne bekannte Dauer (Livestream) gibt es keinen Regler und kein Springen, stattdessen eine blasse Leiste mit „Live“. Die Leiste wird nur während der Wiedergabe mit bis zu 30 fps neu gezeichnet. In der Vorschau zeigt sie Hover-Effekte, springt aber nicht.

**Warum:** Zeitangaben stören im Ruhezustand das reduzierte Design, sind beim gezielten Springen aber nötig. Eine Leiste, die bei Streams „läuft“, wäre irreführend.

## 25. CI auf mehreren macOS-Versionen

**Entscheidung:** Der Workflow baut parallel auf macOS 14, 15 und 26 (`fail-fast: false`); das Release und das Artefakt für Nutzer kommen nur vom neuesten Runner.

**Warum:** Entwickelt wurde wieder ohne lokalen Swift-Compiler (Linux-Container). Neue APIs (Symbol-Übergänge ab macOS 14, Liquid Glass ab macOS 26) müssen sowohl mit älteren SDKs (dort fehlen die Symbole) als auch mit dem neuesten Xcode kompilieren. Nur so fallen fehlende Verfügbarkeitsprüfungen sofort auf.

## 26. Eigener Updater statt Sparkle

**Entscheidung:** MusicDesk sucht beim Start und danach alle 24 Stunden (Schalter `autoCheckUpdates`, Standard an; Zeitpunkt in `lastUpdateCheck`) über die öffentliche GitHub-API (`/repos/lukestark-glitch/MusicDesk-Widget/releases/latest`) nach einer neueren Version. Ein Update wird mit einer dezenten Mitteilung, im Rechtsklick-Menü („Update installieren …“) und unter *Einstellungen → Updates* angeboten. Der eigene Installer lädt die Release-ZIP, entpackt sie, prüft Bundle-ID (`com.musicdesk.widget`), höhere Version und gültige Signatur (`codesign --verify`), entfernt das Quarantäne-Merkmal, ersetzt das Bundle am aktuellen Ort und startet die App neu. Schlägt ein Schritt fehl, bleibt die alte App unangetastet und es erscheint eine Fehlermeldung.

**Warum nicht Sparkle:**
- Sparkle erwartet einen eigenen Signaturschlüssel (EdDSA) für jedes Update und einen gepflegten Appcast-Feed. Beides müsste geheim verwaltet bzw. bei jedem Release erzeugt werden – zusätzlicher Aufwand und ein Risiko, wenn der Schlüssel verloren geht.
- Die App ist nur **ad-hoc signiert** (Entscheidung 8); Sparkles Sicherheitsmodell setzt auf eine stabile Signatur bzw. eigene Schlüssel. Ein Appcast wäre bei uns ohnehin nur eine Kopie dessen, was GitHub-Releases schon liefert.
- Sparkle ist ein großes Framework (mit XPC-Diensten), das sich in ein von Hand zusammengesetztes SPM-App-Bundle nur umständlich einbetten lässt.
- Die GitHub-Releases werden von der CI ohnehin erzeugt (Entscheidung 12) und sind damit die eine verlässliche Quelle.

**Nachteile/Hinweise:** Da sich die Ad-hoc-Signatur mit jeder Version ändert, fragt macOS nach einem Update ggf. erneut nach der Apple-Music-/Spotify-Erlaubnis. Der Ordner der App muss beschreibbar sein. Die erste Update-Mitteilung löst die einmalige Mitteilungs-Abfrage von macOS aus. Die Sicherheit beruht auf HTTPS zu GitHub und der Prüfung von Bundle-ID, Version und Signatur – ohne Entwicklerzertifikat ist eine stärkere Herkunftsprüfung nicht möglich.
