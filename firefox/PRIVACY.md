# Tailnet Browser privacy and data transmission

This is an unofficial Cryovex fork. It uses a separately installed native helper
to connect a Firefox profile to Tailscale. The extension author does not operate
a data collection server for this extension.

## Data needed for the connection

- **Browsing activity and website content:** while enabled, Firefox sends
  proxied connections and their destination names to the local helper. The
  helper routes traffic to websites, tailnet peers, or a configured exit node.
  Normal HTTPS encryption remains between Firefox and the destination; the
  helper does not decrypt HTTPS content. Unencrypted HTTP remains unencrypted
  at the application layer.
- **Authentication information:** login links and account/device authorization
  are used to connect to Tailscale. Login occurs on the authentication site;
  the popup does not contain a password form. The helper stores authentication
  state locally so it can reconnect.
- **Personally identifying information:** a persistent random profile identifier
  is sent to the local helper to select the profile's state directory. The
  helper derives its Tailscale hostname from the local operating-system username.
  Tailscale handles the account and device identity needed for the service.

The Firefox manifest declares these categories so Firefox 140 or later can ask
for consent before installing. Decline installation if you do not want this
routing. The popup switch disables proxy routing; removing the extension stops
its browser integration. Native authentication state survives removal and is
managed separately. Turning the extension off is not a network kill switch.

The native helper embeds Tailscale's client. Tailscale's account, connection,
device metadata and diagnostic handling are governed by its service and client
settings; this fork does not promise that the native client transmits no
technical data. See https://tailscale.com/privacy-policy/ for service details.
Websites, identity providers, tailnet administrators and any chosen exit-node
operator have their own data-handling practices. The extension does not inject
page scripts, read the browser history database, or add advertising analytics.
Its popup uses local/system fonts and makes no external font request.

Local developer console logs may contain connection status and login links.
Do not share these logs without reviewing them for sensitive values.
