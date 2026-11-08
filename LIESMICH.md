# KytyPS5 Installer & Updater für Batocera (PS5)

*Created by DeLorean23* · [English: README.md](README.md)

Mit diesem Installer richtest du den experimentellen PS5-Emulator KytyPS5 (https://github.com/KytyPS5/KytyPS5) in Batocera als normales System **PlayStation 5** ein. Die Spiele startest du wie bei jedem anderen Emulator aus der Spieleliste, im Vollbild, und die Einstellungen von KytyPS5 erreichst du über den F1-Dateimanager.

## Download

**KytyPS5 Installer & Updater.zip** gibt es unter **[Releases](https://github.com/DeLorean23/KytyPS5-Installer-Updater-Batocera/releases/latest)**.

## Voraussetzungen

- Batocera (x86_64-PC), Start als root (beim Start aus Ports automatisch)
- Internetverbindung (für Download und Updates)
- Deine eigenen PS5-Spiele

## Installation

1. Den Inhalt der ZIP nach `/userdata` entpacken, damit landen der Installer und das Cover in `/userdata/roms/ports/`.
2. In Batocera die Spieleliste aktualisieren und unter **Ports** den Eintrag **KytyPS5 Installer & Updater** starten.
3. Den Warnhinweis lesen und mit **y** bzw. **A** am Controller bestätigen.
4. Der Installer lädt den neuesten Linux-Build von KytyPS5 von GitHub, prüft die SHA-256-Prüfsumme und richtet alles ein.
5. Am Ende fragt er „Reboot now?“. Mit **y / A** startet Batocera neu.

## Was installiert wird

- KytyPS5 in `/userdata/system/add-ons/kytyps5/`
- System **PlayStation 5** (`ps5`) mit dem Emulator `kyty`, Bezels aus, Beenden mit Hotkey + Start
- Spieleordner: `/userdata/roms/ps5/` (Formate `.elf .bin .self .json .ps5` oder ein Spielordner mit `eboot.bin`)
- **F1 → Anwendungen → KytyPS5** öffnet die Einstellungen von KytyPS5 (`kyty_launcher`)
- Bei AMD-Prozessoren wird KytyPS5 mit `--amd-cpu` gestartet

Um den Emulator einzutragen, legt der Installer eine bearbeitbare Kopie von Batoceras Emulator-Starter (configgen) in `/userdata/system/configgen` ab und bindet sie beim Start über das Original (Dienst `ps5_configgen`, dazu eine Ausweichlösung in `custom.sh`). Vorher prüft er, ob dein Batocera das erwartete Format hat, und bricht sonst mit einer Fehlermeldung ab, ohne etwas zu ändern.

## Update

Den Installer einfach erneut unter Ports starten. Gibt es einen neueren Build von KytyPS5, wird er installiert und die vorherige Version in `/userdata/system/add-ons/kytyps5-backup` aufgehoben. Ist nichts Neues da, steht „up to date“. Nach einem Update ist kein Neustart nötig.

## Hinweise

- KytyPS5 ist sehr experimentell. Nicht jedes Spiel läuft.
- Dieses Projekt stellt keine Spiele oder Firmware bereit.
- Weil der Installer Batoceras Emulator-Starter erweitert, kann nach einem Batocera-Update ein erneuter Lauf des Installers nötig sein.
- Log-Dateien bei Problemen: `/userdata/system/logs/kyty-installer.log`, `/userdata/system/logs/kyty.log` und `/userdata/system/logs/kyty-launcher.log`

## Bauen

`./build.sh` erstellt die ZIP in `dist/` aus `src/installer.template.sh` und `assets/cover.jpg`.

## Lizenz

Der Installer steht unter der [MIT-Lizenz](LICENSE). KytyPS5 selbst ist ein eigenes Projekt mit eigener Lizenz; dieser Installer lädt es nur aus den offiziellen Releases herunter.
