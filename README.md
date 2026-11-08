# KytyPS5 Installer & Updater for Batocera (PS5)

*Created by DeLorean23* · [Deutsche Anleitung: LIESMICH.md](LIESMICH.md)

This installer sets up the experimental PS5 emulator KytyPS5 (https://github.com/KytyPS5/KytyPS5) on Batocera as a normal **PlayStation 5** system. Games start in fullscreen from the game list, just like with any other emulator, and the KytyPS5 settings are available in the F1 file manager.

## Download

Get **KytyPS5 Installer & Updater.zip** from the **[Releases](https://github.com/DeLorean23/KytyPS5-Installer-Updater-Batocera/releases/latest)** page.

## Requirements

- Batocera (x86_64 PC), run as root (the default when started from Ports)
- Internet connection (for downloads and updates)
- Your own PS5 games

## Installation

1. Extract the contents of the ZIP archive to `/userdata`. This places the installer and its cover image in `/userdata/roms/ports/`.
2. In Batocera, refresh the game list and launch **KytyPS5 Installer & Updater** from **Ports**.
3. Read the warning and confirm with **y** or **A** on your controller.
4. The installer downloads the newest KytyPS5 Linux build from GitHub, checks its SHA-256 checksum and sets everything up.
5. At the end, it asks "Reboot now?". Press **y / A** to restart Batocera.

## What gets installed

- KytyPS5 in `/userdata/system/add-ons/kytyps5/`
- System **PlayStation 5** (`ps5`) with the emulator `kyty`, bezels off, exit with Hotkey + Start
- Games folder: `/userdata/roms/ps5/` (formats `.elf .bin .self .json .ps5`, or a game folder with `eboot.bin`)
- **F1 → Applications → KytyPS5** opens the KytyPS5 settings (`kyty_launcher`)
- On AMD CPUs, KytyPS5 is started with `--amd-cpu`

To register the emulator, the installer places an editable copy of Batocera's emulator launcher (configgen) in `/userdata/system/configgen` and mounts it over the original at boot (service `ps5_configgen`, plus a fallback in `custom.sh`). Before changing anything it checks that your Batocera uses the expected format and stops with an error otherwise.

## Update

Simply launch the installer again from **Ports**. If a newer KytyPS5 build is available, it will be installed and the previous version kept in `/userdata/system/add-ons/kytyps5-backup`. If no update is available, the installer displays "up to date". No reboot is required after an update.

## Notes

- KytyPS5 is highly experimental. Not every game will run.
- This project does not provide any games or firmware.
- Because the installer extends Batocera's emulator launcher, a future Batocera update may require running the installer again.
- Log files for troubleshooting: `/userdata/system/logs/kyty-installer.log`, `/userdata/system/logs/kyty.log` and `/userdata/system/logs/kyty-launcher.log`

## Building

`./build.sh` creates the ZIP in `dist/` from `src/installer.template.sh` and `assets/cover.jpg`.

## License

The installer is released under the [MIT License](LICENSE). KytyPS5 itself is a separate project with its own license; this installer only downloads it from the official releases.
