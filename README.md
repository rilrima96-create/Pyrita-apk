# Pyrita App

Нативный Android-клиент Pyrita VPN-сервиса. Flutter + sing-box-core (когда дойдём до Phase C).

Лицензия: **MIT** (см. [LICENSE](LICENSE)). Не fork-Hiddify — пишем с нуля поверх MIT/Apache библиотек, чтобы код оставался проприетарным.

## Status

| Phase | Что | Status |
|---|---|---|
| **A** | UI scaffold: theme, splash, login, home mockup, settings | 🚧 в работе |
| **B** | Auth + API integration (login → fetch /api/me → display) | ⏳ next |
| **C** | VPN core: sing-box-core integration + VpnService | ⏳ позже |
| **D** | Polish: stats, auto-reconnect, in-app billing | ⏳ позже |
| **E** | Distribution: RuStore submission + signed APK | ⏳ позже |

## Dev setup

Нужен Flutter SDK 3.22+ и Android Studio (для эмулятора).

```bash
# 1. Install Flutter (Windows)
#    https://docs.flutter.dev/get-started/install/windows
#    Скачать ZIP, распаковать в C:\flutter, добавить C:\flutter\bin в PATH

# 2. Verify
flutter --version
flutter doctor

# 3. Install Android Studio + Android SDK + Emulator
#    https://developer.android.com/studio
#    В Android Studio: Tools → Device Manager → Create Virtual Device

# 4. В этом проекте
cd "E:\2. Всякое ИИшное\pyrita-app"
flutter pub get
flutter run                  # запустит на запущенном эмуляторе или подключенном устройстве
```

Если flutter create не запускали раньше — нужно один раз:

```bash
flutter create . --org com.pyrita --project-name pyrita_app \
  --platforms android --no-pub
flutter pub get
```

(`--platforms android` потому что iOS пока не делаем — нужен Mac + foreign card $99/y.)

## Project structure

```
lib/
├── main.dart                          # entry point
├── app.dart                           # MaterialApp + go_router
├── core/
│   ├── theme.dart                     # Pyrita design tokens
│   ├── api_client.dart                # Dio configured for api.pyrita.com
│   └── auth_storage.dart              # flutter_secure_storage wrapper
├── features/
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── login_controller.dart      # Riverpod
│   ├── home/
│   │   ├── home_screen.dart           # Connect/Disconnect toggle (mockup)
│   │   └── home_controller.dart
│   └── settings/
│       └── settings_screen.dart
└── shared/
    └── widgets/                       # переиспользуемые UI компоненты

assets/
├── images/                            # SVG logos
└── fonts/                             # (опционально, fonts через Google Fonts CDN)

android/
└── app/src/main/
    ├── AndroidManifest.xml            # permissions: INTERNET + future VpnService
    └── kotlin/com/pyrita/app/
        └── MainActivity.kt
```

## API contract

Приложение разговаривает с `https://api.pyrita.com`:

| Method | Path | Описание |
|---|---|---|
| `POST` | `/api/login` | `{email, password}` → session-cookie + 200 |
| `POST` | `/api/register` | `{email, password, accept}` → session-cookie + 200 |
| `GET` | `/api/me` | Текущий юзер + subscription_url + subscription_status |
| `POST` | `/api/logout` | Завершить сессию |
| `POST` | `/api/auth/request-password-reset` | `{email}` → 200 (privacy: всегда) |

Sub URL juzер получает в `/api/me.subscription_url`, его передаём sing-box-core (когда дойдём до Phase C).

## Лицензии деpsов

* Flutter SDK — BSD-3-Clause
* flutter_riverpod — MIT
* go_router — BSD-3-Clause
* dio — MIT
* flutter_secure_storage — BSD-3-Clause
* shared_preferences — BSD-3-Clause
* flutter_svg — MIT
* google_fonts — Apache-2.0
* (Phase C) sing-box-core — MIT

Все permissive licenses — наш код может оставаться проприетарным.

## Брендинг

Дизайн-токены, цвета, логотипы — copy-paste из `pyrita-web/src/styles/colors_and_type.css`. Поддерживаем визуальную консистентность с лендингом.
