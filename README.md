# dispad

<p align="center">
  <!-- Record a 10-second GIF showing the iPad mirroring the Mac, drop it into docs/assets/demo.gif, and uncomment:
  <img src="docs/assets/demo.gif" alt="Demo of dispad mirroring a Mac to an iPad over USB-C" width="600">
  -->
  <em>Demo GIF pending — contributions welcome.</em>
</p>

Use an iPad as the primary display for a headless Mac mini, over a USB-C cable.

## Why

Apple Sidecar cannot start before you log in, and a headless Mac mini will not render to its GPU without a monitor. Commercial products like Luna Display solve this with a proprietary USB dongle. `dispad` solves it with software only, open source and free.

## How it works

```
Mac mini ──(USB-C, usbmuxd tunnel)──► iPad

DispadHost.app on the Mac:
  ScreenCaptureKit → VideoToolbox HEVC encoder → usbmuxd server

DispadClient.app on the iPad:
  usbmuxd client → VideoToolbox decoder → AVSampleBufferDisplayLayer
```

## Requirements

- macOS 13 or newer (Apple Silicon recommended)
- iPadOS 16 or newer, any iPad with A12 Bionic or newer (HEVC hardware decode)
- A USB-C cable that supports data (most do)
- Bluetooth keyboard and mouse paired to the Mac mini (the iPad is display-only for now)

## Installation

### Mac side (DispadHost)

1. Download the latest `DispadHost.dmg` from [Releases](../../releases).
2. Drag `DispadHost.app` to `/Applications`.
3. Launch DispadHost. On first launch a welcome sheet appears — click **Install auto-launch** to register a LaunchAgent so the app starts at every login. Click Skip if you don't want auto-launch.
4. Grant Screen Recording permission in System Settings → Privacy & Security.

   On ad-hoc-signed builds macOS sometimes silently denies the permission instead of showing a prompt. If DispadHost doesn't appear in the Screen Recording list, click the `+` button there and add `/Applications/DispadHost.app` manually, then enable the toggle and relaunch the app.

The build is unsigned. If macOS refuses to open it, run:

```bash
xattr -d com.apple.quarantine /Applications/DispadHost.app
```

### iPad side (DispadClient)

iOS doesn't allow distributing apps outside the App Store without a paid developer account, so you build from source:

1. Clone this repo on a Mac with Xcode installed.
2. Run `./scripts/bootstrap.sh` — this installs XcodeGen (via Homebrew) and generates the two `.xcodeproj` files from their `project.yml` specs.
3. Open `DispadClient/DispadClient.xcodeproj` in Xcode.
4. Select the `DispadClient` scheme and your iPad as the run destination.
5. Under Signing & Capabilities, pick your personal Apple ID as the team.
6. Hit Run. The app is built and installed on your iPad.
7. Trust your developer certificate on the iPad: Settings → General → VPN & Device Management.

Free Apple IDs require re-signing the app every 7 days. A paid developer account lasts a year.

See [`docs/installation.md`](docs/installation.md) for troubleshooting.

## Usage

1. Boot the Mac mini (no monitor needed; log in blindly). If you installed auto-launch during setup, DispadHost starts automatically on login.
2. Launch `DispadClient` on your iPad.
3. Connect the iPad to the Mac with a USB-C cable.
4. The connection establishes automatically. The iPad shows the Mac's screen.

## Project layout

```
dispad/
├── DispadHost/          # macOS app (Xcode project)
├── DispadClient/        # iPadOS app (Xcode project)
├── DispadProtocol/      # Shared Swift package (wire format)
├── ThirdParty/Peertalk/ # Vendored usbmuxd bindings
├── docs/                # Architecture and installation docs
└── .github/workflows/   # CI
```

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). This is an MIT-licensed hobby project; issues and PRs are welcome.

## License

MIT. See [`LICENSE`](LICENSE).

Peertalk is vendored under `ThirdParty/Peertalk/` with its original MIT license.
