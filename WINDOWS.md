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
