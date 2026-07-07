# Current Handoff

Last updated: 2026-07-07 local time.

## Android debug stability check

- Local debug builds now use the visible app label `Pyrita`, not `Pyrita QA`.
- The debug package id remains `com.pyrita.pyrita_app.debug` so it can be
  installed side by side with the signed production package.
- The normal signed `Pyrita` package is `com.pyrita.pyrita_app`. Android will
  not allow replacing it from the local debug build because package signatures
  differ.
- A release update for the normal package requires `android/key.properties` with
  the signing credentials for `keystore.jks`. Do not commit that file.

## What changed in this session

- Android Xray config stripping for removed `allowInsecure` fields remains in
  place. Newer Xray builds reject those fields.
- Server picker still builds a safe server catalog from the subscription and
  supports cached server snapshots while VPN is already connected.
- Server snapshot storage intentionally excludes VPN URLs and secrets.
- US server selection now has a hard Android safety override: if a US Hysteria2
  profile is present, the picker and the actual Xray config choose it before
  the known-bad US VLESS/WebSocket/XHTTP fallbacks.
- `PyritaVpnStatus.copyWith` can now explicitly clear transient errors and ping
  values, so stale errors are not kept accidentally.
- VPN ping/health timers are no longer restarted on every repeated CONNECTED
  callback. They start on transition into connected state.
- Android/Xray `CONNECTED` is no longer treated as final proof of usable
  internet. After the core reports connected, the app performs tunnel health
  checks and stops the VPN if internet through the tunnel does not answer.
- The app no longer auto-opens the full diagnostics dialog on VPN errors.
  Errors stay in the inline banner; detailed logs remain available from the
  manual logs button.

## Verified locally

- `dart format lib\features\home\home_screen.dart`
- `flutter test` passed (`24/24`).
- `flutter analyze` passed with no issues.
- `flutter build apk --debug` passed.
- `aapt dump badging` confirms all application labels are `Pyrita`.
- 2026-07-07: targeted regression tests passed for US-HY2 preference over both
  generic US VLESS and US VLESS XHTTP.

## Verified on device

Device: `RF8XB03BBXM`.

- Debug APK installed successfully.
- The visible app title is `Pyrita`.
- Baseline phone internet without Pyrita VPN was verified in Chrome before this
  investigation.
- Earlier US and Finland VPN attempts reached Android/Xray connected state, but
  real browser traffic did not complete. Treat Android `VALIDATED` alone as
  insufficient proof.
- 2026-07-07 official `v0.1.33` on the same phone still selected US
  VLESS/WebSocket (`us.pyrita.com:443`) and reproduced the bad route. The local
  `v0.1.34` patch is intended to update the signed package and force US-HY2
  before retesting real browser traffic.
- Final Helsinki check after the health-gate change: the app briefly reaches
  protected state, then the tunnel health check fails, the VPN stops, and the
  UI shows `Ошибка подключения` with the message that internet through the
  tunnel does not answer. No full-screen diagnostics dialog auto-opens.

## Open follow-ups

- 2026-07-07 update: signed release `v0.1.38` / `0.1.38+2048` was installed on
  phone `RF8XB03BBXM` as the normal package `com.pyrita.pyrita_app`. The phone
  has no debug/QA Pyrita package installed.
- Android connectivity reported Pyrita as the VPN owner with `tun0`, full
  `0.0.0.0/0` route, and session `Pyrita · Хельсинки`.
- Real traffic verified under Pyrita `v0.1.38`: Chrome `https://example.com`,
  Chrome `https://m.youtube.com`, and the YouTube Android app watch page all
  loaded.
- The current release uses a short-path HTTP-proxy route: TCP goes through the
  Pyrita proxy edge, UDP goes direct to avoid Android Chromium/Yandex QUIC
  hangs. This is working enough for the phone smoke test, but it is not the
  final mobile VPN architecture.
- Remaining follow-ups: replace this emergency path with a UDP-capable mobile
  transport, fix/soften the app ping healthcheck that logs failures during
  heavy YouTube traffic, and investigate Yandex Browser on Android separately
  because Chrome and the YouTube app work while Yandex showed a blank page.
- Windows Hiddify was intentionally not touched.
