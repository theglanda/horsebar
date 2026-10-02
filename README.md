# HorseBar 🐴

Slap your MacBook — it makes a sound.

HorseBar lives in the menu bar and listens to the motion sensor built into newer MacBooks.
Give the case a light slap and it plays a sound back.

- **Slap strength**: set how hard a slap needs to be, with a live meter showing your last slap
- **Sound**: random or one specific sound, preview each one with ▶
- **Volume**: optionally louder for harder slaps
- **Cooldown**: so one slap doesn't trigger several sounds
- Add your own sounds: 🐴 → *Sounds Folder* (`.mp3`, `.wav`, `.m4a`, `.aiff`)

## Requirements

- MacBook with **M1 Pro / M1 Max / M2 or newer**. Base M1 and Intel Macs don't expose the motion sensor.
- macOS 14 Sonoma or newer.

## Install

1. Download `HorseBar-x.y.pkg` from [Releases](../../releases).
2. Open it. macOS will say it's from an unidentified developer (the package isn't notarized):
   go to **System Settings → Privacy & Security** and click **Open Anyway**.
3. Click through the installer and enter your password.
4. Look for 🐴 in the menu bar.

The password is needed because the motion sensor can only be read by a small background
service running as root. Everything else runs as your user.

**Uninstall:** 🐴 → ⚙︎ → *Uninstall HorseBar…*

## How it works

Apple Silicon MacBooks (M1 Pro and later) have a Bosch BMI286 IMU behind the Sensor
Processing Unit. There is no public API for it, but it shows up as an `AppleSPUHIDDevice`
(vendor usage page `0xFF00`, usage `3`) and can be read through IOKit HID as root.

```
slapd (root LaunchDaemon)                     HorseBar.app (menu bar, your user)
  IOKit HID → accelerometer @ ~800 Hz
  high-pass filter → peak detection   ──►  /var/run/slapd.sock  ──►  threshold + cooldown
  "impact 0.42"                                                       → AVAudioPlayer
```

- `Sources/SlapCore` — sensor reader and slap detector
- `Sources/slapd` — root daemon, broadcasts `impact <g>` lines over a Unix socket
- `Sources/HorseBar` — SwiftUI menu bar app
- `prototype/slap.py` — quick Python prototype using [macimu](https://github.com/olvvier/apple-silicon-accelerometer)

The interface is undocumented, so a future macOS update could break it.

## Build from source

Requires Xcode Command Line Tools.

```bash
./scripts/install.sh            # build the installer and install it on this Mac
./scripts/build-pkg.sh          # just build dist/HorseBar-<version>.pkg
./scripts/build-pkg.sh --public # same, without sounds-private/
./scripts/uninstall.sh
```

Sounds in `sounds/` are bundled into the app and copied to
`~/Library/Application Support/HorseBar/Sounds` on first launch.

Try the sensor without building anything:

```bash
python3 -m venv .venv && .venv/bin/pip install macimu
sudo .venv/bin/python prototype/slap.py --dry   # print slap strengths only
```

## Credits

- Sensor access based on [olvvier/apple-silicon-accelerometer](https://github.com/olvvier/apple-silicon-accelerometer) (MIT).
- Inspired by [SlapMac](https://slap-mac.com).
- Sound effects were collected from free sound sites (Pixabay, Freesound, and others).
  If you own one of them and want it removed, please open an issue.

## License

MIT — see [LICENSE](LICENSE). The license covers the code, not the bundled sound effects.
