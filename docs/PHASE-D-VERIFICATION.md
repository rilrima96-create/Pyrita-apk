# Phase D — Verification checklist

После установки APK с коммитом `17d9a70` (или новее) — пройди этот
checklist на телефоне. Galaxy A16 (Android 16) или любой Android 13+.

## ✅ 5.1 — Navigation (sub-screen back button)

- [ ] **Licenses screen back** — Account → «Открытые лицензии» → tap
      «←» → возвращается на Account (не выходит из app). Также back
      gesture (свайп от левого края) работает.
- [ ] **Checkout from PlanCard** — Account → «Продлить» → открывается
      Checkout → tap «←» в top-bar → возвращается на Account.
- [ ] **Checkout from PlanCard «Сменить»** — то же, кнопка «Сменить».
- [ ] **Checkout from ExpiringBanner** — Home → если subscription
      истекает скоро → tap на жёлтый банер → open Checkout → back
      возвращается на Home.

## ✅ 5.2 — Brand assets (после AI-gen иконок)

Текущие иконки ещё placeholder'ы из `logo-mark.svg`. После генерации
финальных через `docs/ICON-GENERATION-PROMPT.md` проверить:

- [ ] **Launcher** на home screen Android — узнаваемая Pyrita-форма
      внутри square/circle/squircle маски без обрезки центральных
      элементов.
- [ ] **Notification** в шторке при connect VPN — белый силуэт,
      читается даже при ярком фоне, не «белый квадрат».

## ✅ 5.5 — POST_NOTIFICATIONS permission

**Pre-condition**: на Android 13+ permission ещё НЕ выдан (можно
forcr'ить через Settings → Apps → Pyrita → Permissions → Notifications
→ Don't allow → или после fresh install).

- [ ] При первом tap «Подключить» открывается VpnPermissionIntroScreen
      с тремя пунктами в «Что увидите дальше», первый — про
      уведомления.
- [ ] После tap «Понятно, продолжить» появляется system-prompt
      Android: «Allow Pyrita to send you notifications?».
- [ ] Если accept → VPN connects → notification видна в шторке.
- [ ] Если deny → VPN всё равно connects (но без видимой
      notification — это OK, по дизайну).

## ✅ 5.4 — RU bypass routing

**Pre-condition**: VPN connected. Включена mobile data (T-Bank
DPI блокирует pyrita.com на T-Mobile, тестируем что внутри VPN
банки видят real IP).

- [ ] **Yandex** — open `https://yandex.ru` в Chrome → загружается
      без captcha (если был through VPN — был бы FI captcha).
- [ ] **T-Bank** — open T-Bank app → login → balance видно (если
      бы через VPN — был бы 403).
- [ ] **Sberbank** — Sber Online → login → счета загружаются.
- [ ] **Госуслуги** — `https://gosuslugi.ru` → ESIA login → личный
      кабинет загружается.
- [ ] **Wildberries** — open WB app → no «prokey/proxy detected»
      warning.
- [ ] **Pyrita-собственный** — open `https://pyrita.com` в Chrome
      внутри VPN — должен загружаться (Pyrita-домены в bypass
      списке, иначе self-traffic зацикливается).

**Long-tail verify** (что **VPN работает** для не-RU доменов):

- [ ] **OpenAI** — `chatgpt.com` загружается (DPI-блок RU
      обходится).
- [ ] **YouTube** — youtube.com видео play (нет throttling).
- [ ] **Facebook** — meta-домены доступны.

## ✅ 5.6 — Stability (network changes)

### Auto-reconnect: Wi-Fi → mobile

- [ ] VPN connected via Wi-Fi.
- [ ] Отключаешь Wi-Fi (свайп шторку, tap Wi-Fi).
- [ ] State в app: «connecting…» (~2-3 сек).
- [ ] State: «connected» — туннель сам восстановился через mobile.
- [ ] Проверка: open chatgpt.com — открывается.

### Auto-reconnect: airplane mode

- [ ] VPN connected.
- [ ] Включить airplane mode → wait 5 сек → выключить airplane.
- [ ] State в app: «connecting» → «connected» (10-15 сек total).

### Live ping не stuck

- [ ] VPN connected.
- [ ] В _ServerCard «Pyrita · Хельсинки» — pingMs число должно
      обновляться каждые 5 сек (10-50ms типично для FI).
- [ ] Если `—` остаётся >30 сек — bug, репорт логи.

### Multi-cycle no leak

- [ ] Connect → wait 5 сек → Disconnect → wait 3 сек → Connect → …
      повторить **10 раз**.
- [ ] После 10-го цикла: connect быстрый (<5 сек), state ровный.
- [ ] Нет crash, нет stuck «connecting», `adb logcat` без
      sock_path conflict errors.

## Если что-то сломано

```bash
"E:/platform-tools/adb.exe" -s RF8XB03BBXM logcat -d -t 300 | grep -iE "pyrita|v2ray|xray"
```

→ создать issue в Pyrita-apk repo с logcat output + reproduction steps.
