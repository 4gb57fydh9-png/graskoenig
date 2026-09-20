# Graskönig – TestFlight-Update vorbereiten

Dieses Paket aktualisiert dein vorhandenes Flutter-Projekt. Es ist keine fertige IPA.
Enthalten: letzter korrigierter Spielcode, neue Karten, Anleitung, neues Graskönig-Motiv,
iPhone-/iPad-Icons und Testhinweise. Deine bestehende App-ID und Signierung bleiben Grundlage.
Das komplette Projekt, die letzte hochgeladene Buildnummer und die Codemagic-Konfiguration
liegen hier nicht vor. Deshalb wurde kein signierter iOS-Build erstellt oder hochgeladen.

## 1. Dateien auf deinem Windows-PC übernehmen

Sichere deinen Projektordner. Beende Flutter mit Strg+C.
Kopiere aus diesem Paket in dein bestehendes Projekt:

- `lib/main.dart` → bisherige Datei ersetzen.
- `assets/cards/` → Inhalte zusammenführen, gleichnamige Dateien ersetzen. Andere Motive und Musik behalten.
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/` → diesen Iconordner durch den mitgelieferten ersetzen.
  Nur AppIcon.appiconset ersetzen, nicht den gesamten ios-Ordner oder Assets.xcassets!
- `release_notes.json` → ins Projekt-Hauptverzeichnis neben pubspec.yaml.

Die Icons sind fertig erzeugt. Es ist kein zusätzliches Icon-Paket nötig.
Falls dein Cloud-Workflow Icons automatisch generiert, muss er das neue Bild
`assets/cards/graskoenig_icon.png` verwenden. Sonst könnte er die mitgelieferten Icons
wieder mit dem alten Kartenmotiv überschreiben.

## 2. pubspec.yaml und Buildnummer

Unter dem vorhandenen flutter-Abschnitt muss `assets/cards/` eingebunden sein.
Behalte deine bestehenden Pakete und Audio-Assets. `shared_preferences` bleibt erforderlich.

Öffne App Store Connect → Graskönig → TestFlight und lies die höchste bisherige Buildnummer ab.
In deiner pubspec.yaml die vorhandene Zeile `version:` bearbeiten:
Die Versionsnummer vor dem Pluszeichen kann für diesen Test gleich bleiben;
die Buildnummer dahinter muss für den neuen Upload eindeutig sein. Verwende die höchste bisherige plus 1.
Beispiel nur zur Erklärung: aus `1.0.0+12` wird `1.0.0+13`, wenn 12 der letzte Build war.
Keine zweite version-Zeile anlegen.

Wenn Codemagic die Buildnummer selbst setzt (etwa mit --build-number), zählt diese Einstellung.
Dann dort die nächste freie Nummer sicherstellen; die Zahl in pubspec.yaml allein reicht nicht.
Die Bezeichnung V0.12 dieses Pakets ist keine automatisch gesetzte Apple-Versionsnummer.

## 3. Lokal prüfen und nach GitHub übertragen

Im Terminal deines bestehenden Projekts:

```bash
flutter pub get
flutter analyze
flutter run -d edge
```

Bei Fehlern erst korrigieren. In Edge kann man den Spielcode testen, nicht das native iOS-App-Icon.
Danach in VS Code unter Quellcodeverwaltung die geänderten Dateien prüfen, committen und pushen:
main.dart, neue Karten/Anleitung/Motiv, alle AppIcon-Dateien samt Contents.json,
pubspec.yaml, gegebenenfalls pubspec.lock und release_notes.json.
Commit-Vorschlag: `Graskoenig: neues App-Icon und aktualisierte Spielversion`

## 4. Deinen vorhandenen Codemagic-Workflow starten

1. Öffne dieselbe App und denselben iOS-Workflow, mit denen dein letzter TestFlight-Build funktioniert hat.
2. Wähle den aktualisierten GitHub-Branch und prüfe den neuesten Commit.
3. Nutze die bestehende Bundle-ID, Apple-Verbindung und App-Store-Signierung.
4. Kontrolliere die effektive Buildnummer und starte den Release-Build für iOS.
5. App Store Connect Publishing wie beim letzten erfolgreichen Build verwenden.
   Das Ziel ist TestFlight. Für dieses Update ist keine öffentliche App-Store-Veröffentlichung vorgesehen.
6. Bei erfolgreichem Upload Apples Verarbeitung abwarten. Fehler im Buildprotokoll beheben,
   bevor du einen weiteren Upload startest.

Hier wurde absichtlich keine neue codemagic.yaml eingesetzt: Die vorhandene funktionierende
Konfiguration enthält projektspezifische Einstellungen, die im Paket fehlen.

## 5. Auf dem iPhone aktualisieren

App Store Connect → Graskönig → TestFlight: neuen Build auswählen und gegebenenfalls
zur bisherigen internen Testergruppe hinzufügen. Eventuelle offene Angaben vervollständigen.
Dann am iPhone TestFlight öffnen → Graskönig → Aktualisieren.
Nicht vorher deinstallieren: Eine Deinstallation kann lokale Münzen und Einstellungen löschen.

Prüfe: neues Icon auf dem Home-Bildschirm, Startmenü, Ton, Querformat, neue Karten,
verdeckte Bot-Hand, automatische Zugwechsel (auch nach Auswahl/Verteidigung), Klopfen,
vier vollständige Runden, Münzabrechnung und Anleitung mit Zoom.
Die Testhinweise stehen zusätzlich in release_notes.json.

## Was bereits geprüft wurde

Die Icongrößen entsprechen den Einträgen im mitgelieferten Contents.json.
Alle Icons sind quadratische RGB-PNGs ohne Alphakanal; das Store-Icon hat 1024 × 1024 Pixel.
Dart-Formatierung und ZIP-Integrität sind geprüft. Der zuvor gemeldete categoryName-Fehler ist behoben.
Ein vollständiger Flutter-/iOS-Build und die Signierung wurden hier nicht geprüft.

## Offizielle Anleitungen

- Flutter: https://docs.flutter.dev/deployment/ios
- Codemagic: https://docs.codemagic.io/flutter-publishing/publishing-to-app-store/

## Bildquelle und Erstellung

Das Graskönig-Motiv wurde mit der integrierten Bildgenerierung aus der Figur rechts oben
in deiner rules.jpg erstellt. Vorgabe: nur gekrönter Charakter, dunkelgrüner Hintergrund,
keine Spielkarte, kein Rahmen, kein Text. Die verschiedenen Icongrößen sind technische
Ableitungen dieses Motivs; sie erfordern keine erneute Bildgenerierung.
