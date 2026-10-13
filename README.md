# jof-launcher

JoF Launcher is a cross-platform application for managing and launching Jedi Academy with mods.

## Supported Platforms

- Linux
- macOS (experimental)
- Windows (builds from source; not currently part of the automated release)

## Downloads

Every tagged release is published to
[GitHub Releases](https://github.com/JoFKypdurron/jof-launcher/releases) and to
`https://cloud.jof.app/launcher/`. These paths are stable and always serve the most recent release:

| Platform | URL |
| --- | --- |
| Linux (.deb) | `https://cloud.jof.app/launcher/jof-launcher_amd64.deb` |
| Linux (tarball) | `https://cloud.jof.app/launcher/jof-launcher-linux.tar.gz` |
| macOS | `https://cloud.jof.app/launcher/jof-launcher-macos.dmg` |

Install the Debian package with:

```bash
sudo apt install ./jof-launcher_amd64.deb
```

Versioned `.deb` builds are kept alongside them under
`jof-launcher_<version>_<arch>.deb` if you need to pin or roll back to a
specific release.

## Building from Source

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install)
- Platform-specific build tools (C++ compiler, CMake, etc.)

### Build Instructions

#### Linux
```bash
flutter build linux --release
./scripts/package-linux.sh
```
The output will be `jof-launcher-linux.tar.gz` in the project root.

#### Windows
```powershell
flutter build windows --release
.\scripts\package-windows.ps1
```
The output will be `jof-launcher-windows.zip` in the project root.

#### macOS
```bash
flutter build macos --release
./scripts/package-macos.sh
```
The output will be `jof-launcher-macos.dmg` in the project root.

## Installing on macOS

Open the `.dmg` and drag **JoF Launcher** onto the Applications folder.

The macOS build is **not signed with an Apple Developer ID**, so Gatekeeper
blocks it on first launch. This is expected. To allow it:

1. Open JoF Launcher from Applications. macOS refuses to open it.
2. Go to **System Settings > Privacy & Security**.
3. Scroll to the Security section and click **Open Anyway** next to the
   message about JoF Launcher.

Equivalent from the Terminal:

```bash
xattr -dr com.apple.quarantine "/Applications/JoF Launcher.app"
```

Note that Control-clicking the app and choosing **Open** no longer bypasses
Gatekeeper for unsigned apps on macOS 15 Sequoia and later — the Privacy &
Security route above is the only one that works.

Because the bundle is only ad-hoc signed, its code signature changes on every
build. macOS ties folder permissions to that signature, so users may be asked
to re-approve access to Documents or Downloads after each update. Signing with
a Developer ID and notarizing would remove both of these annoyances.

## Game client (EternalJK) downloads

On Linux and macOS the launcher installs the EternalJK client from **GitHub
releases** on [JediofFreedom/JoF_EJK](https://github.com/JediofFreedom/JoF_EJK),
not from our own S3 bucket:

```
https://github.com/JediofFreedom/JoF_EJK/releases/download/<version>/JoF-<platform>-<arch>.tar.gz
```

### Choosing which version ships

The version is **not** hardcoded in the launcher — it is read from the jofhub
cloud manifest at runtime, so publishing a new client is a manifest edit rather
than a launcher release.

`ClientReleaseService.parseVersion` looks through `data.clientgroups[].assets[]`
for an asset whose name starts with `jofclient-`, and takes the first dotted
version out of its `description`:

```
"description": "JoF EJK Client 1.6.1 (64 Bit)"   ->   1.6.1
```

To roll clients forward or back, change that description in the cloud file
manager. Note this is a free-text field rather than a dedicated version column,
so keep a version number in it. If it ever stops parsing, the launcher falls
back to `ClientReleaseService.fallbackVersion` (currently `1.6.1`) rather than
failing the sync — bump that constant when the pinned floor should move.

Downloads are verified against the sha256 published by the GitHub release API
(`assets[].digest`) before extraction. If the API is unreachable or
rate-limited (60 requests/hour unauthenticated), verification is skipped rather
than blocking the download.

### Release channels

Settings → Platform has an "EternalJK client version" dropdown with three
options: **Latest stable** (the default), **Beta**, and **Alpha**. It is only
shown on Linux and macOS.

Stable keeps the behaviour above unchanged — the version comes from the
manifest description. Alpha and beta instead call
`GET /repos/JediofFreedom/JoF_EJK/releases` and pick the newest tag matching
`X.Y.Z-alpha.N` / `X.Y.Z-beta.N` (`ClientReleaseService.selectLatestTag`),
comparing the base version and build number numerically rather than trusting
the API's ordering. Since the client tarball is re-downloaded and re-extracted
on every sync, switching channels takes effect on the next sync with no extra
cache-invalidation step.

A failed or rate-limited lookup on a non-stable channel degrades to the
stable resolution (manifest, then `fallbackVersion`) rather than failing the
sync, for the same reason sha256 verification degrades gracefully above.

Windows is unaffected and still installs the client as individual files from
the jofhub repository via `clientgroups`; the channel setting is not shown
there.

## Cloud backup

Cloud backup of `.cfg` files is **currently disabled**. The existing
implementation talks to S3 directly and needs credentials compiled into the
binary, which a public build cannot ship. The code is still in the tree behind
`BackupService.featureEnabled`, the settings section is hidden, and no backup
runs at startup. Saved backup IDs and previously uploaded backups are left
untouched, so they will be usable again once backups are moved behind a
server-side API.

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d linux   # or macos / windows
```

Pull requests run the analyzer and the test suite in CI.

## Releasing

Bump `version` in `pubspec.yaml`, then push a matching tag (`v1.2.3`). The
release workflow refuses to build if the tag and `pubspec.yaml` disagree,
because the in-app updater compares against the version in the bundle.

## Security

Please report security issues privately through
[GitHub security advisories](https://github.com/JoFKypdurron/jof-launcher/security/advisories/new)
rather than opening a public issue.

## License

The source code is released under the [MIT License](LICENSE).

The JoF name and logos under `assets/` and the platform icon sets are not
covered by that license and may not be reused for other projects. The bundled
Rajdhani font is licensed separately under the
[SIL Open Font License 1.1](https://openfontlicense.org).
