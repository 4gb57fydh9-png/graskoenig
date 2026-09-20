# Graskönig V0.12 – Update für dein bestehendes Flutter-Projekt

## Installation auf Windows

1. Sichere zuerst deinen bisherigen Projektordner.
2. Entpacke diese ZIP-Datei.
3. Kopiere `lib/main.dart` aus diesem Paket in den `lib`-Ordner deines Projekts und ersetze die bisherige Datei.
4. Kopiere den Inhalt von `assets/cards` in den vorhandenen Ordner `assets/cards`. Ordner zusammenführen, nicht den alten Ordner löschen: weitere Motive und Musik werden weiterhin benötigt.
5. Die neuen Bilder haben Namen mit `_v12.png`. Diese Namen unverändert lassen; der neue Code verwendet sie automatisch.
6. Prüfe in deiner bestehenden `pubspec.yaml`, dass unter dem vorhandenen `flutter:`-Abschnitt der gesamte Kartenordner eingebunden ist:

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/cards/
```

Bestehende andere Einstellungen behalten. Keinen zweiten `flutter:`-Abschnitt anlegen. Falls du einzelne Karten auflistest, kannst du diese Liste durch den Verzeichniseintrag ergänzen bzw. ersetzen.

7. In VS Code im Projektordner das Terminal öffnen:

```bash
flutter pub get
flutter run -d edge
```

`shared_preferences` hast du bereits installiert. Weitere neue Pakete werden für dieses Update nicht benötigt. Nach Änderungen an Bildern die laufende App vollständig beenden und neu starten; Hot Reload allein genügt nicht immer.

## Auf dem iPhone in Safari testen

Beende den PC-Test mit Strg+C und starte:

```bash
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8081
```

Lies in einem zweiten Terminal mit `ipconfig` die IPv4-Adresse deines PCs ab. Öffne auf dem iPhone `http://DEINE-PC-IP:8081`. PC und iPhone müssen im selben Heimnetz sein. Das Server-Terminal bleibt geöffnet. Ein Guthaben in Edge ist getrennt vom Guthaben in Safari gespeichert.

## Was geändert wurde

- Dunkelgrüner Spielhintergrund mit deutlich sichtbaren, gezackten Hanfblättern in Anlehnung an die Kartenrückseite. Das Muster wird direkt in Flutter gezeichnet und passt sich der Bildschirmgröße an.

- Automatischer Spielerwechsel nach dem Ausspielen oder Ablegen, mit kurzer Pause von 0,6 Sekunden. Der Button „Nächster Spieler“ entfällt. Auswahl- und Verteidigungsdialoge sowie das Ablegen überzähliger Handkarten werden zuerst beendet. Auch letzte Züge nach dem Klopfen wechseln automatisch.
- Weibliche Figuren: Energie 100, Energie 50, Glückstreffer, Übertopf und Anwalt (der Kartenname bleibt für die bestehende Spiellogik erhalten).
- Rosa Illustrationen: Beste Freunde, Glückstreffer, Übertopf, Dünger und Ich zieh mir zwei.
- Gartenschere ist ebenfalls rosa; der Code verwendet dafür `schere_v12.png`.
- Alle offenen Karten erhalten im Flutter-Code links unten ein farbiges Typ-Symbol, auch unveränderte und hier nicht mitgelieferte Motive. Das gilt für Hand, Ablage, Plantagen, Übersicht und Vergrößerung. Die Symbole sind eine App-Darstellung, nicht in die gelieferten JPG-/PNG-Dateien eingebrannt. Die Rückseite erhält kein Typ-Symbol.
- Avatar-Auswahl: genau drei männliche und drei weibliche Figuren. Die Auswahl ist rein optisch.
- Startmenü und Graskönig-Avatar: neues großes Charaktermotiv ohne Kartenrahmen oder Kartentext. Native iOS-Icons sind im Ordner `ios/Runner/Assets.xcassets/AppIcon.appiconset` vorbereitet.
- Neue Anleitungsgrafik `rules_v12.png` in der App: antippen und zoomen. Die illustrierten Motive sind Beispiele. Zusätzlich Textregeln: 2–3 Spieler, Kartentypen, Avatare, Münzen und Testshop. Die veraltete `rules.jpg` wird nicht mehr angezeigt.
- Das Münzsystem aus V0.11 bleibt erhalten.

## Figurenverteilung

Unter den hochgeladenen menschlichen Darstellungen gibt es jetzt fünf weibliche und elf männliche Figuren, wenn beide Figuren auf „Beste Freunde“ einzeln gezählt werden: rund 31 % / 69 %. Pflanzen, Hund und Kartenrückseite zählen nicht als menschliche Figuren. Die Verteilung im gesamten Deck kann erst mit den weiteren, nicht hochgeladenen Motiven abschließend geprüft werden. Mehrfach vorhandene Spielkarten ändern diese Motivzählung nicht.

## Kurzer Test nach dem Einbau

1. Menü: Graskönig größer als vorher; Guthaben und Tischauswahl vorhanden.
2. Avatar-Auswahl: Powerfrau, Glücksfee und Anwältin sowie Graskönig, Kumpel und Dealer vorhanden.
3. Kartenübersicht: die sechs rosa Karten und die weiblichen Varianten anzeigen.
4. Bei allen Kartentypen links unten kontrollieren: Gras 🌿, Energie ⚡, Basis 👑, Angriff 💥, Verteidigung 🛡️, Aktion ★.
5. Ein Spiel starten und Symbole auch in Hand, Ablage und Plantage kontrollieren. Bot-Hand bleibt verdeckt. Nach Ausspielen oder Ablegen muss automatisch der nächste Spieler folgen. Auch eine Aktionskarte mit Auswahl und die letzten Züge nach dem Klopfen testen.
6. Regeln öffnen: neue Grafik antippen und zoomen; darunter stehen die aktuellen Textregeln.

## TestFlight

Die vollständigen Schritte für das neue App-Icon und das TestFlight-Update stehen in `TESTFLIGHT.md`.

## Umfang und Prüfung

Dieses Paket ist ein Update, kein eigenständig vollständiges Flutter-Projekt. Plattformordner, Musik und nicht hochgeladene Motive stammen weiterhin aus deinem bestehenden Projekt. Echte Käufe und Online-Spiel sind weiterhin nicht aktiv. Ein vollständiger Flutter-Build und ein visueller iPhone-Test dieses Updates wurden hier nicht durchgeführt.
