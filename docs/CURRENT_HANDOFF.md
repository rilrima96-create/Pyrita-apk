# Current Handoff

Last updated: 2026-07-07 local time.

## Android release candidate `0.1.32+2042`

- Source version is bumped to `0.1.32+2042`.
- In-app updates now check `https://api.pyrita.com/api/release/latest` first.
- The expected direct APK asset is `app-arm64-v8a-release.apk`.
- GitHub Releases API is retained only as a fallback if the Pyrita endpoint is
  unavailable.
- Release workflow can mirror signed direct APKs to the Pyrita web server when
  the `PYRITA_RELEASE_SSH_*` GitHub Actions secrets are configured.
- Local checks passed: `flutter test test/update_service_test.dart` and
  `flutter analyze`.
- Do not install the local debug app over `com.pyrita.pyrita_app`. The user
  needs a signed release APK from CI/tag `v0.1.32` or the same release key.

## Android app state

- Debug builds install side by side as `Pyrita QA` (`com.pyrita.pyrita_app.debug`).
- The normal `Pyrita` package (`com.pyrita.pyrita_app`) is still the older installed app. Android will not allow replacing it from the local debug build because package signatures differ.
- A release update for the normal package requires `android/key.properties` with the signing credentials for `keystore.jks`. Do not commit that file.

## What changed in this session

- Auth cookies are now stored only when the server sends a real session cookie. Deletion or empty cookie headers clear the session instead of saving a broken cookie.
- Account screen uses cached email immediately, limits slow core loading, and treats optional sections as optional so the screen does not stay stuck.
- Server picker now builds a safe server catalog from the subscription and supports a cached server snapshot while VPN is already connected.
- Server snapshot storage intentionally excludes VPN URLs and secrets.
- Android Xray config strips removed `allowInsecure` fields before starting the core. Newer Xray builds reject those fields.
- US server selection now prefers the VLESS profile when the backend exposes it.

## Verified on device

Device: `RF8XB03BBXM`.

- Installed and launched `Pyrita QA`.
- Server picker opens while disconnected and shows:
  - Helsinki / VLESS Reality
  - USA / VLESS
- Selecting Helsinki updates the home card to `Helsinki · FI`.
- Selecting USA updates the home card to `USA · US`.
- USA connects in `Pyrita QA`; Android reports a validated VPN network with session `Pyrita · USA`.
- Server picker also opens while VPN is already connected.
- Switching from connected USA to Helsinki keeps VPN connected and updates the selected server.
- Switching back from Helsinki to USA keeps VPN connected and leaves the phone on USA.
- Account screen no longer forces login and opens using cached identity, but the plan refresh can still show a soft failure if `/api/me` is slow through the active VPN.

## Open follow-ups

- Build and install a properly signed release APK over `com.pyrita.pyrita_app` once signing credentials are available locally or via CI.
- Polish Account plan refresh so a slow `/api/me` does not show alarming copy when cached account data is available.
- Run longer real-use checks on phone apps such as browser, Telegram, and ChatGPT while `Pyrita QA` is connected to USA.
