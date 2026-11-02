# Manual update checks

Available in Peekdown v1.1.1 and later.

Choose **Peekdown → Check for Updates…** in the app menu, or use the button in
the app window. The results window shows the installed version and whether a
newer stable release is available. When available, release notes appear as plain
text; **View Release on GitHub…** opens this repository's release page so you can
choose the installer or ZIP. Downloads and installation are manual.

Checks run only when requested. There are no startup checks, scheduled requests,
automatic downloads, or self-installation. Network failures, timeouts, rate limits,
and unexpected responses display an error and allow retry.

The host sends an unauthenticated HTTPS request to the GitHub Releases API for
`h0ck3ystyx/peekdown`. GitHub receives normal connection metadata, including the
client IP address and a generic Peekdown update-check user agent. No document
contents, local file paths, credentials, or preference values are sent. The
request uses an ephemeral session without cookies or a persistent response cache.
Redirects are rejected, response bytes are bounded, and timeouts are explicit.
The host has the outgoing network entitlement; preview and thumbnail extensions
retain their offline entitlements. The website playground runs separately in a
browser.

Versions are compared numerically, so `1.0.10` follows `1.0.9`. Draft and
prerelease responses are rejected. An installed experimental version with a
higher numeric version is never offered a downgrade; a stable release of the
same numeric version supersedes its prerelease. Release links are constructed
from validated version tags under this repository's HTTPS GitHub URL; links
supplied in API response fields or release notes are not opened automatically.

Run `./scripts/test.sh` to exercise numeric versions, stable-release validation,
link construction, HTTP/network failures, response byte limits, and retry using
an isolated URL protocol stub. Signed Finder previews should continue to work
without networking. On a signed development app, test the app-menu and window
buttons, the current-version result, and retry after a connection failure.

Local validation: signed development build 20 was tested on 2026-11-01. Both the
main-window button and application-menu action returned the live GitHub result
“You’re up to date” for v1.1.0. Universal CLI and Xcode Release builds passed;
strict signatures and host-only outgoing network entitlement were verified.
