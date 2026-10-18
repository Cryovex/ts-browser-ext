# Windows Firefox build

This is an unofficial personal fork of Tailscale's experimental browser extension.
It is not a Tailscale release. The upstream BSD 3-Clause license and PATENTS file
are preserved. The fork uses a separate extension ID and native-host name.

## Build and test

Use Go 1.26.3 or newer and Node 24:

```powershell
go test ./...
node --test tests/browser.test.cjs
go build -o ts-browser-ext-cryovex.exe .
pwsh -File tests/native-smoke.ps1 -Binary ./ts-browser-ext-cryovex.exe
```

The browser tests mock extension APIs. They check initialization ordering,
disconnect/reconnect, off/on transitions, login links, and Firefox proxy routing.
The smoke test checks the actual Windows executable's framing and clean exit.

## Install for the current Windows user

The Firefox extension requires Firefox 140 or newer for its built-in data
transmission consent prompt. See [privacy and data transmission](firefox/PRIVACY.md).

Back up Firefox after closing it normally. Register the built native host:

```powershell
.\ts-browser-ext-cryovex.exe --install=Fts-browser-ext@cryovex
```

The host is copied to `%APPDATA%\ts-browser-ext-cryovex\native-hosts\F`.
The installer writes a per-user registry entry at
`HKCU\Software\Mozilla\NativeMessagingHosts\io.github.cryovex.ts_browser_ext.firefox`.
No administrator privileges are required.

In Firefox, open `about:debugging#/runtime/this-firefox`, choose **Load Temporary
Add-on**, and select `firefox/manifest.json` or the packaged extension ZIP.
In `about:addons`, grant this extension private-window access if Firefox requires
it for the proxy API. Open its toolbar popup and choose **Log in**.

The unsigned temporary extension is removed when Firefox restarts. Permanent
installation in release Firefox requires Mozilla signing, including for private
self-distribution. Do not disable Firefox's signature checks.

## Package for Mozilla signing

With Python 3 installed, run from the repository directory:

```powershell
py -3 scripts/package-firefox.py
```

Upload `dist/ts-browser-ext-firefox-1.0.2-unsigned.xpi` to Mozilla's developer hub
using **On your own** for unlisted distribution. The archive contains the
readable Firefox files, privacy disclosure, license and patent notice; it does
not include the native executable or your local authentication state. Packaging
does not compile or minify browser code. For the question about source generation
for this browser package, select **No**. In reviewer notes, explain that the
separate native helper's source and build instructions are in this repository.
Select desktop platforms only: the native helper is not supported on Android.
The Android manifest minimum only keeps the data-consent declaration's version
metadata consistent; it does not add Android support.

Download the signed copy from Mozilla and use Firefox's **Install Add-on From
File** action. Keep the existing extension ID so the registered helper continues
to recognize it. Signing the extension does not sign or reinstall the native
helper. Mozilla may request further review or changes; local tests do not
guarantee acceptance.

## Clean exit and rollback

- Switch the extension off to remove its Firefox proxy listener and stop Tailscale.
- If its native process exits, its listener is removed immediately and the
  replacement process must finish initialization before traffic is routed again.
- Closing Firefox closes the native messaging pipe. The native host closes its
  proxy listener and Tailscale server before exiting.
- For immediate rollback, exit Firefox normally and reopen it. The temporary
  add-on and its runtime proxy listener are gone.
- To remove the native registration and installed native binary, close Firefox
  and run the following from the original build/package directory (not from the
  installed native-host directory):

```powershell
.\ts-browser-ext-cryovex.exe --uninstall-browser=F
```

This removes only this fork's Firefox host. It leaves Tailscale authentication
state intact so an uninstall is reversible. A full Firefox-profile restoration
should be used only when necessary, as it returns bookmarks/history/preferences
to the backup time.

## Limits

This remains experimental software. The automated tests do not replace a real
Firefox login and tailnet connectivity test. Disconnect restores ordinary browser
routing; it is not a VPN kill switch.
