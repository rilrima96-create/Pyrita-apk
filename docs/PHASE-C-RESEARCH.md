# Phase C research — VPN-engine integration на Flutter Android

**Цель**: реальный VPN-tunnel на Connect-кнопке (сейчас mockup в `home_screen.dart`).

---

## КРИТИЧЕСКОЕ ОТКРЫТИЕ 2026-05-13 — license audit

**sing-box (Go core от SagerNet) — GPL-3.0.**

Любой Flutter-пакет который статически линкует sing-box, заставляет наш app
тоже стать GPL-3.0 (copyleft propagation). Это противоречит ограничению в
плане a-b2-nifty-haven: «Не fork Hiddify-Next — пишем поверх MIT/Apache
библиотек».

### Аудит pub.dev пакетов (2026-05-13)

| Пакет | Wrapper license | Engine license | Combined verdict |
|---|---|---|---|
| `flutter_sing_box` v1.0.12 | GPL-3.0 (явно) | GPL-3.0 (sing-box) | ❌ GPL |
| `singbox_mm` v0.1.9 | MIT | GPL-3.0 (sing-box) | ❌ GPL (combined) |
| `sing_box` v0.0.1 | Unknown | GPL-3.0 (libbox) | ❌ Не использовать |
| `VPNclient-engine-flutter` | GPL-3.0 | GPL-3.0 (Xray+WG) | ❌ GPL |
| **`flutter_v2ray_client` v3.2.0** | **MIT** ✓ | **Xray MPL-2.0** ✓ | **✓ ИСПОЛЬЗУЕМ** |
| `v2ray_box` (latest) | MIT | Xray MPL-2.0 / sing-box GPL (dual, opt-in) | ✓ Backup (Xray-only mode) |

### MPL-2.0 vs GPL — почему это OK

**MPL-2.0** (Mozilla Public License) — file-level copyleft. Модификации
самого Xray-core должны быть MPL-2.0, но наш application code, который
использует Xray через MethodChannel/JNI binding, остаётся under нашей
лицензией (MIT / proprietary — на выбор).

**GPL-3.0** — work-level copyleft. Любая программа линкующая GPL-код
становится GPL-3.0 целиком, включая весь наш Dart-код.

Для friends-only distribution это всё равно нерелевантно (никто не
требует source), но для будущей commercialization (Stage 6 плана
`steady-churning-cray`) GPL заблокирует продажу.

### Commercial precedent

Browsec (Premium commercial VPN, distributed on Google Play, paid
subscription model) **открыто использует Xray в UI** — engine toggle с
подписью «XRay» в главном экране. Screenshot из 2026-05-13.

Доказывает что:
1. Юридически Xray-путь работает для коммерции — Browsec прошёл Play
   Store review, продаёт подписки без license-conflict
2. MPL-2.0 совместима с пейволлами — paid features за подпиской не
   нарушают лицензию (юзер не может потребовать «выдайте мне premium
   бесплатно потому что GPL»)
3. Xray стандарт для commercial VPN — мы не пионеры

Если когда-то будут юристы или инвесторы — Browsec / NordVPN / ProtonVPN
все embed-ят VPN-движки в коммерческие подписочные приложения.
MPL-2.0 на Xray = стандартная практика, не serious legal risk.

---

## Выбор движка: Xray-core (MPL-2.0)

### Pros
- License-clean: app остаётся под нашим выбором лицензии
- Поддерживает VLESS, VLESS+Reality, VLESS+XHTTP **нативно** (Xray —
  upstream Reality, изобретение проекта)
- В новых версиях Xray (26.x) также есть Hysteria 2, UDPhop, обфускация
  (per release notes `flutter_v2ray_client` v3.2.0 / Xray v26.4.17)
- 4 ABI: arm64-v8a, armeabi-v7a, x86, x86_64 (Pyrita прицеливается на
  arm64-v8a + armeabi-v7a; x86 для эмулятора)

### Cons
- TUIC v5: НЕ в vanilla Xray (нативное решение sing-box). Если нужен в
  Pyrita-app — отдельный embed `tuic-client` (MIT), либо отказ от TUIC
  в Phase C, оставляем только в subscription URL для Hiddify-юзеров.
- Shadowsocks 2022: native Xray поддерживает SS, но AEAD-2022 vairantы
  под вопросом. Проверить в момент integration.

### Pyrita protocol matrix после Phase C

| Протокол | Pyrita-app native | Subscription URL (Hiddify et al) |
|---|---|---|
| VLESS Reality | ✅ Xray | ✅ |
| VLESS XHTTP | ✅ Xray | ✅ |
| Hysteria 2 | ✅ Xray v26+ | ✅ |
| TUIC v5 | ❌ Phase D | ✅ |
| SS-2022 | ⚠️ TBD на audit'е | ✅ |

В UI Account → Protocols бейдж «АКТИВЕН» будет правда работать только
для VLESS Reality + XHTTP в Phase C; остальные останутся «ДОСТУПЕН» для
других клиентов. В Phase D можем расширить.

---

## Выбор Flutter-wrapper'а: `flutter_v2ray_client` (amir-zr)

### Pros

- **License: MIT** (wrapper), Xray binary под MPL-2.0
- **Verified publisher**: `amirzr.dev` (pub.dev verified badge)
- **Активный**: v3.2.0 опубликован 17 дней назад, embeds Xray v26.4.17
- **441 weekly downloads** — есть user base
- **9 likes, 150 pub points** — мало для большого проекта, но нормально
  для нишевого VPN-плагина
- **API focus**: V2Ray Proxy + VPN Mode + live status updates
  (connection state, speeds, traffic, duration), sharing-link parsing
- **35 commits** — small but focused codebase, легче audit'ить

### Cons

- **Один maintainer** — bus factor 1. Mitigation: vendor код на known-good
  версии, fork если abandon
- **iOS использует Xray 25.12.2 + HevSocks5Tunnel 5.14.1** — старее
  Android'ной версии (нам пока не нужен iOS, but worth noting)
- **Windows/Linux/macOS использует Sing Box 1.12.10** — GPL! Но для
  Pyrita-app мы Android-only в Phase C → этот binary не bundled, safe.
- **APK size impact** не задокументирован — ожидаем +20-30 МБ к текущим
  53 МБ (= ~75 МБ release APK). Mitigation: ABI splits в build-apk.yml,
  отдельные APK для arm64-v8a / armeabi-v7a (на ~50% меньше каждый).

### Backup: `v2ray_box`

Если flutter_v2ray_client отвалится по какой-то причине (баг, заброс),
переключаемся на `v2ray_box` в Xray-only mode (документация явно
описывает: keep `libxray.aar`, remove `libsingbox.so`).

---

## Что делаем в Phase C (Etap 4)

См. `~/.claude/plans/c-phase-vpn-integration.md` — детальный план для
следующей сессии. Краткий summary этапов:

1. **4.1 (3-4 ч)** — Final audit + pubspec.yaml import + sample-app тест
2. **4.2 (1 день)** — Android scaffolding + MethodChannel boilerplate
3. **4.3 (2-3 дня)** — PyritaVpnService + permission flow + state EventChannel
4. **4.4 (1-2 дня)** — home_screen wiring (sub URL fetch → start tunnel)
5. **4.5 (1-2 дня)** — Real-time state UI (Mbps stats, server card live ping)

Итого ~5-9 рабочих дней, по реалистичному темпу 1-2 недели.

---

## Risks / Open questions

1. **TUIC v5 fate**: Phase C сразу или отложить в Phase D? Для friends — VLESS
   primary, TUIC nice-to-have. Решение: **отложить, оставить «НЕ
   ПОДДЕРЖИВАЕТСЯ ВСТРОЕННЫМ КЛИЕНТОМ» в Account → Protocols**, рендерим
   честно.

2. **SS-2022 AEAD support в Xray**: уточнить в momento integration. Если
   нет — same approach как с TUIC.

3. **APK size budget**: 53 МБ → 75-85 МБ. Ниже Play Store cap (500 МБ
   AAB) но выше friendly download size. Mitigation: ABI splits в CI.

4. **Auto-reconnect** при network change (WiFi ↔ 4G): connectivity_plus
   listener → restart tunnel. **Phase C must-have** (без этого VPN
   ломается на каждом lifecycle).

5. **Multiple VPN apps на устройстве**: если у юзера Hiddify подключён —
   Android запретит Pyrita взять VpnService. UX-экран «Отключите
   Hiddify» нужен в `_PulseTapTarget` press handler'е.

---

## Open decisions для пользователя

Перед стартом Phase C нужны ответы:

1. **TUIC + SS-2022 в Phase C или Phase D?** (рекомендую D)
2. **iOS targeting когда?** (не сейчас — но влияет на выбор wrapper'а
   если когда-то)
3. **ABI splits**: один универсальный APK (~85 МБ) или per-arch (по
   ~45 МБ)? RuStore универсальный не любит, friends-distribution через
   pyrita.com → можем делать оба.
4. **Бюджет на Phase C**: реалистично 1-2 недели sequential work. Делать
   подряд или с гейтом на каждом 4.X для verify?
