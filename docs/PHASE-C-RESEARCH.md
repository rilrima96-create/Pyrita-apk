# Phase C research — sing-box-core integration на Flutter Android

**Цель**: реальный VPN-tunnel на Connect-кнопке (сейчас mockup в `home_screen.dart`).

## Главное открытие 2026-05-12

**Не нужно писать gomobile-bindings с нуля.** Существует ≥3 готовых open-source Flutter-пакетов, обёртывающих sing-box-core через Android VpnService:

| Package | Pros | Cons | Status |
|---|---|---|---|
| **[singbox_mm](https://pub.dev/packages/singbox_mm)** | «Thin VPN shell», routing presets, anti-throttling config builder, notification wiring готов | Молодой (~ один автор), нужен audit | Активный |
| **[flutter_sing_box](https://pub.dev/packages/flutter_sing_box)** | Profile import, Clash API, full VPN service mgmt, Android + iOS | iOS тоже включён (но нам пока не нужен) | Активный |
| **[sing_box](https://pub.dev/packages/sing_box/versions)** | Stats monitoring, bypass rules, DNS config | Меньше docs | Активный |

И ещё есть [VPNclient-engine-flutter](https://github.com/VPNclient/VPNclient-engine-flutter/blob/master/SINGBOX_INTEGRATION.md) — open-source VPN-client от которого можно учиться integration patterns.

## Выбор для Phase C

Сравним вживую при начале работы. Текущий **leaning** — `flutter_sing_box` потому что:
- Поддержка `Clash API` — стандарт для VPN-stats observability
- Android + iOS из коробки (когда iOS добавим)
- Profile import — сразу подходит к нашему flow (юзер не вводит config вручную, мы fetcheм sub URL c api.pyrita.com)

Альтернативно — `singbox_mm` если он более минималистичный и легче integrate'ится.

## Что нужно сделать

1. **Audit пакета** перед production-use:
   - Прочитать source code (Dart + Kotlin/Java)
   - Проверить permissions в их AndroidManifest (не запрашивает ли больше нужного)
   - Проверить licensing — должен быть MIT/Apache/BSD (НЕ GPL — заразит наш код)
   - Проверить размер APK с пакетом

2. **Wire в наш Home screen**:
   ```dart
   final singBox = FlutterSingBox.instance;
   
   Future<void> _connect() async {
     final me = await ApiClient.instance.getMe();
     final subUrl = me["subscription_url"] as String;
     // sing-box fetcheт config напрямую с нашего endpoint'а
     await singBox.importProfileFromUrl(subUrl);
     await singBox.start();
   }
   ```

3. **State management**: подключение/отключение через Riverpod `StreamProvider<VpnState>`, кнопка реагирует на real state.

4. **Background lifecycle**:
   - Android 14+ требует `foregroundServiceType="systemExempted"` для VPN
   - POST_NOTIFICATIONS permission запросить при первом connect'е
   - Persistent notification обязателен (notification.shown:true в VpnService)

5. **DNS / split-tunnel**:
   - sing-box JSON config от api.pyrita.com уже имеет routing rules (geosite-ru bypass)
   - Просто передаём как есть, sing-box применяет

6. **Auto-reconnect** при network change (WiFi ↔ 4G):
   - `connectivity_plus` package на изменение sub'аем
   - Re-start sing-box если соединение ломалось

## Risks / unknowns

1. **Размер APK** с sing-box embedded ~25-40 MB. Это нормально для VPN-app'а, но прирост из текущих ~10 MB.
2. **Compatibility** Android 7+ — sing-box-core supports, должно работать.
3. **Battery drain** в background-mode. sing-box optimized но протоколы вроде Hysteria 2 на UDP poll'ят активнее VLESS-Reality. Если будут жалобы — переключать на VLESS-only.
4. **Multiple VPN apps**: Android разрешает только один active VPN-tunnel. Если у юзера Hiddify тоже подключён — Pyrita попросит permission revoke. UX-screen «отключите другой VPN» нужен.

## Time estimate

С готовым пакетом — Phase C сокращается с моих исходных 4-6 недель до **~1-2 недель**:
- Day 1-3: audit пакета + минимальный integration
- Day 4-7: state-management + UI states (connecting/connected/error)
- Day 8-10: stats display (Mbps вверх/вниз, traffic per protocol)
- Day 11-14: edge cases (multiple-VPN, no-network, battery-optimization conflicts)

## Open questions

1. Какой пакет выбрать (нужен audit и пробный integration)?
2. Нужны ли нам stats UI в Phase C, или это Phase D?
3. Auto-reconnect — Phase C must-have или later?

---

При начале Phase C — пройтись по этим пунктам подробнее, audit нескольких пакетов параллельно, выбрать.
