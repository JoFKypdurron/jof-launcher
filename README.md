# jof-launcher

JoF Launcher is a cross-platform application for managing and launching Jedi Academy with mods.

## Supported Platforms

- Linux
- macOS (experimental)
- Windows 10 and 11 (x64; ARM64 runs it under emulation)

## Downloads

Every tagged release is published to
[GitHub Releases](https://github.com/JoFKypdurron/jof-launcher/releases) and to
`https://cloud.jof.app/launcher/`. These paths are stable and always serve the most recent release:

| Platform | URL |
| --- | --- |
| Linux (.deb) | `https://cloud.jof.app/launcher/jof-launcher_amd64.deb` |
| Linux (tarball) | `https://cloud.jof.app/launcher/jof-launcher-linux.tar.gz` |
| macOS | `https://cloud.jof.app/launcher/jof-launcher-macos.dmg` |
| Windows (installer) | `https://cloud.jof.app/launcher/jof-launcher-windows-setup.exe` |
| Windows (portable zip) | `https://cloud.jof.app/launcher/jof-launcher-windows.zip` |

Install the Debian package with:

```bash
sudo apt install ./jof-launcher_amd64.deb
```

Versioned `.deb` builds are kept alongside them under
`jof-launcher_<version>_<arch>.deb` if you need to pin or roll back to a
specific release.

## Releasing

Releases are automatic: every merge to `main` that touches the app (anything
outside `*.md`, `LICENSE` and `.github/`) bumps `pubspec.yaml`, tags `vX.Y.Z`
and publishes. Don't bump the version by hand. Label the PR to control the bump:

| PR label | Effect |
| --- | --- |
| _(none)_ | patch (`1.1.16` → `1.1.17`) |
| `release:minor` | minor (`1.1.16` → `1.2.0`) |
| `release:major` | major (`1.1.16` → `2.0.0`) |
| `release:skip` | merge without releasing |

To cut a release by hand (for example, after merging a `release:skip` PR), run
the **Auto Release** workflow from the Actions tab and pick the bump.

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
The output will be `jof-launcher-windows-setup.exe` and
`jof-launcher-windows.zip` in the project root. The installer needs
[Inno Setup 6](https://jrsoftware.org/isinfo.php); without it only the zip is
built. The installer script is `windows/installer/jof-launcher.iss`.

#### macOS
```bash
flutter build macos --release
./scripts/package-macos.sh
```
The output will be `jof-launcher-macos.dmg` in the project root.

## Installing on Windows

Run `jof-launcher-windows-setup.exe`. It installs for the current user into
`%LOCALAPPDATA%\Programs\JoF Launcher` without asking for administrator
rights, adds a Start menu entry, and can be removed from **Settings > Apps**.
Running a newer installer upgrades in place. The portable zip runs from
wherever it is extracted, but does not update itself.

The Windows build is **not code-signed**, so Microsoft Defender SmartScreen
warns about it on first run. This is expected. To continue:

1. In the "Windows protected your PC" dialog, click **More info**.
2. Click **Run anyway**.

Some browsers also flag the download as uncommon; choose **Keep** in the
download list. Signing the installer would remove both warnings.

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

On every platform the launcher installs the EternalJK client from **GitHub
releases** on [JediofFreedom/JoF_EJK](https://github.com/JediofFreedom/JoF_EJK),
not from our own S3 bucket or the jofhub `clientgroups` files:

```
https://github.com/JediofFreedom/JoF_EJK/releases/download/<version>/JoF-<platform>-<arch>.tar.gz
https://github.com/JediofFreedom/JoF_EJK/releases/download/<version>/JoF-windows-<arch>.zip
```

On Windows the architecture comes from `PROCESSOR_ARCHITECTURE` (64-bit,
including ARM64 under emulation, unless Windows itself is 32-bit).

### Choosing which version ships

The version is **not** hardcoded in the launcher; GitHub decides at runtime,
so publishing or rolling back a client is a GitHub release edit rather than a
launcher release. The jofhub `clientgroups` are not consulted at all.

The stable channel installs the release GitHub marks as **Latest**
(`GET /repos/JediofFreedom/JoF_EJK/releases/latest`). To roll clients forward
or back, publish a release or move the "Set as the latest release" flag to an
older one. Prereleases and drafts are never picked for stable.

If GitHub cannot be reached or rate-limits the launcher (60 requests/hour
unauthenticated), whatever client is already installed is kept as is. Only an
install with no client at all falls back to
`ClientReleaseService.fallbackVersion` (currently `1.6.1`). Bump that constant
when the floor for fresh installs should move.

Downloads are verified against the sha256 published by the GitHub release API
(`assets[].digest`) before extraction. If the API is unreachable or
rate-limited (60 requests/hour unauthenticated), verification is skipped rather
than blocking the download.

### Skipping an unchanged client

After extracting, the launcher writes `GameData/.jof-client.json` recording the
release version, asset name, sha256 and the files it extracted. A sync
downloads the client only when that marker no longer matches the release it
would install: a new version, a different architecture or channel, a release
re-uploaded under the same tag (different sha256), or an extracted file that
has since gone missing. When the sha256 cannot be looked up, version and asset
name decide. The tag lookup returns the digests too, and a resolved tag is
reused for five minutes, so a sync costs one GitHub API request. A new client release is installed on the next sync even when no
other asset changed.

### Release channels

Settings → Platform has an "EternalJK client version" dropdown with three
options: **Latest stable** (the default), **Beta**, and **Alpha**.

Stable uses the release marked Latest, as above. Alpha and beta instead call
`GET /repos/JediofFreedom/JoF_EJK/releases` and pick the newest tag matching
`X.Y.Z-alpha.N` / `X.Y.Z-beta.N` (`ClientReleaseService.selectLatestTag`),
comparing the base version and build number numerically rather than trusting
the API's ordering. Switching channels changes the release the install marker
is compared against, so it takes effect on the next sync.

A failed or rate-limited lookup on any channel keeps the installed client
rather than failing the sync or swapping an alpha or beta build for stable,
for the same reason sha256 verification degrades gracefully above.

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
