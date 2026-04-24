# Installation

## Mac (DispadHost)

### Option A — download a release

1. Grab the latest `DispadHost.dmg` from the [Releases page](../../releases).
2. Drag `DispadHost.app` into `/Applications`.
3. Launch it. Because the build is unsigned, macOS will likely refuse. Run:

   ```bash
   xattr -d com.apple.quarantine /Applications/DispadHost.app
   ```

   Then launch it again.
4. Grant Screen Recording permission when prompted: System Settings → Privacy & Security → Screen Recording → enable DispadHost.
5. Relaunch the app. The first-run wizard installs a LaunchAgent so it starts at every login.

### Option B — build from source

```bash
git clone https://github.com/<you>/dispad.git
cd dispad
./scripts/bootstrap.sh          # installs XcodeGen and generates Xcode projects
open DispadHost/DispadHost.xcodeproj
```

In Xcode, select the `DispadHost` scheme and hit Run.

## iPad (DispadClient)

Apple does not let us distribute iOS apps outside the App Store without a paid developer account. You build from source with your own Apple ID.

1. On a Mac with Xcode 15+, clone the repo.
2. Run `./scripts/bootstrap.sh` (installs XcodeGen and generates the Xcode projects from their `project.yml` specs).
3. Open `DispadClient/DispadClient.xcodeproj`.
4. Connect your iPad by USB-C and trust the Mac when prompted on the iPad.
5. Select your iPad as the run destination.
6. In the project settings → Signing & Capabilities:
   - Team: pick your personal Apple ID. Add it via Xcode → Settings → Accounts if it's not there yet.
   - Bundle identifier: change to something unique to you, e.g. `com.yourname.dispad`. Free Apple IDs can't reuse bundle IDs across developers.
7. Hit Run.
8. On the iPad: Settings → General → VPN & Device Management → tap your Apple ID under "Developer App" → Trust.

**Free Apple ID caveat:** the app expires after 7 days. You'll have to rebuild & reinstall each week. A paid developer account ($99/year) extends this to a year.

## Troubleshooting

**"No connection" on the iPad.**
Check that the USB-C cable supports data (some cheap cables are power-only). Try a known-good cable such as the one Apple ships with iPads.

**Black screen on the iPad.**
The host may not have Screen Recording permission yet. Open DispadHost from the menu bar and check its status.

**App crashes at launch on the Mac.**
Check `/tmp/dispad-host.log` for the error.

**LaunchAgent didn't start the app at login.**
Run:

```bash
launchctl list | grep dispad
```

If nothing shows up, rerun the first-launch wizard or manually install:

```bash
cp DispadHost/LaunchAgent/com.dispad.host.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.dispad.host.plist
```
