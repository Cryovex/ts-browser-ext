# Automatic updates for the browser's Tailscale engine

The Tailscale admin console's `ryan-browser-ext` version is the native helper's
embedded `tailscale.com` library. It is independent of the Firefox add-on version.
Updating the system Tailscale app or signing a new XPI does not update this library.

## What this adds

The `Native Tailscale updates` GitHub workflow checks daily for the latest stable
Tailscale release and stable Go toolchain. It rebuilds when either version or the
fork's source changes. It verifies Go module checksums, runs the Go/browser/updater
tests, and exercises the actual Windows native-messaging binary before publishing.
Failed builds never replace the current published release. Each release contains
the binary, update manifest, and resolved `go.mod`/`go.sum`. This is still an
unofficial Cryovex build, not a Tailscale-signed Windows executable.

The Windows updater downloads only this repository's stable native releases,
checks GitHub's SHA-256 asset digests and the release manifest, checks the binary's
embedded dependency/version identity, and rejects older installed releases.
Firefox and the helper must both be closed before replacement. It preserves the
previous executable, and rolls back if the new executable's version check fails.
Authentication state, device identity, extension settings and system VPN settings
are not changed. A real tailnet connection still needs checking after first use;
the version/handshake checks cannot prove every network configuration works.

## Activate once

1. Merge the change to `main` and let the workflow publish its first successful
   native release. Forked repositories may require enabling GitHub Actions first.
2. From this source/package folder, run in PowerShell as your normal Windows user:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AutoUpdates.ps1
   ```

This creates a non-admin scheduled task, **Cryovex Tailnet Browser Engine Update**.
It checks at login, noon, and hourly while you are logged in. It makes no update
request while Firefox or the helper is running; close Firefox to allow the next
check to update. To check immediately after closing Firefox:

```powershell
Start-ScheduledTask -TaskName 'Cryovex Tailnet Browser Engine Update'
```

Status is in `%APPDATA%\ts-browser-ext-cryovex\updater\last-check.txt`.
Updates fail closed on missing assets, network problems or checksum mismatches;
the next scheduled check retries. The updater scripts themselves are installed
locally and are not automatically replaced from the network. Re-run the installer
from a reviewed newer package if updater behavior needs changing.

## Disable or roll back

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-AutoUpdates.ps1 -Remove
```

This removes the task, retaining the installed helper, updater status and login.
For a binary rollback, disable updates and close Firefox first, then restore
`%APPDATA%\ts-browser-ext-cryovex\native-hosts\F\ts-browser-ext-cryovex.exe.previous`
over `ts-browser-ext-cryovex.exe`. Keep updates disabled until the bad release is
replaced, or the updater will attempt to install it again.

GitHub's scheduled workflows can be delayed or disabled after repository inactivity;
check the Actions page if releases stop appearing. The installed task cannot build
a release itself. Keep unrelated Firefox XPI releases marked as not-latest, because
the native updater deliberately accepts only a native release at `releases/latest`.
