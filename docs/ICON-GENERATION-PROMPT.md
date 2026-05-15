# Иконки Pyrita — Prompt для генерации

Этот файл — спецификация для генерации launcher и notification иконок
Pyrita Android-app. Отдай его в AI image generator (Sora / Midjourney /
Flux / DALL-E / Imagen) или дизайнеру.

## Контекст бренда

Pyrita — VPN-сервис, бренд = pyrite («fool's gold», золотистый
пиритовый кристалл). Палитра:

- Тёплое золото: `#F5DDA3` highlight, `#C9A875` mid-tone, `#7A5519` shadow
- Янтарные/оранжевые блики: `#E26A5E` accent
- Фон / ink: `#0C0907`

Mood: warm, premium, slightly mystic.

## Задача 1 — Launcher icon (Android adaptive)

**Single hero subject**: Isometric stylized golden pyrite crystal/cube
с внутренним тёплым свечением. Может быть либо одиночный куб (как
faceted mineral specimen) ЛИБО чистый кластер из 2-4 кубиков (НЕ 7+
кубиков — они расплываются). Лучше одна сильная форма.

**Style**: 3D-rendered или flat-illustrated isometric; crisp edges,
soft warm rim light, без harsh photorealism.

**Safe zone (CRITICAL)**: Все важные визуальные элементы — внутри
центральных **70%** холста (716×716 пикселей из 1024×1024). Внешние
15% по краям будут обрезаны Android круглой/squircle/teardrop маской
— туда только декоративный фон или пустота.

**Background**: Прозрачный (foreground PNG). Android применит solid
`#0C0907` сам.

**Output**: 1024×1024 PNG, transparent, RGBA.

**Also output**: 1024×1024 PNG, dark backdrop (`#0C0907` + slight
warm gradient), full-bleed без прозрачности — для legacy launcher
(Android <8).

## Задача 2 — Notification icon (Android status bar)

**Subject**: Та же иконическая форма что в launcher, но РАДИКАЛЬНО
упрощённая до силуэта. Android рендерит ИСКЛЮЧИТЕЛЬНО белым
monochrome — градиенты, оттенки, детали ТЕРЯЮТСЯ.

**Constraint**: 1-3 простых геометрических примитива. Должна
читаться при 16×16 пикселей (status bar height на phone).

**Цвет**: Pure `#FFFFFF` white на полностью прозрачном фоне.
Никаких теней, gradient'ов, обводок.

**Output (предпочтительно)**: SVG single path, `viewBox="0 0 24 24"`,
без strokes, `fill="white"`.

**Output (альтернатива)**: PNG 96×96, transparent, монохромный.

**Тест**: Закрой глаза, открой, посмотри 1 секунду — форма должна
узнаваться как "Pyrita brand mark", а не как абстрактная клякса
или белый квадрат.

## Куда класть файлы

```
pyrita-app/assets/images/
  icon-launcher-foreground.png   (Task 1 transparent)
  icon-launcher-legacy.png       (Task 1 full-bleed dark)

pyrita-app/android/app/src/main/res/drawable/
  ic_notification.xml            (Task 2 SVG → VectorDrawable)
```

## Что делать после получения файлов

1. Положить PNG в `assets/images/`, SVG → конвертировать в Android
   VectorDrawable (`drawable/ic_notification.xml`).

2. Обновить `pubspec.yaml`:
   ```yaml
   flutter_launcher_icons:
     adaptive_icon_foreground: "assets/images/icon-launcher-foreground.png"
     image_path: "assets/images/icon-launcher-legacy.png"
     adaptive_icon_background: "#0C0907"
   ```

3. `flutter pub run flutter_launcher_icons` для регенерации mipmap'ов.

4. Verify через `adb install` на физический Android — особенно
   notification на тёмной шторке Samsung One UI.

## Что НЕ делать

- Не рендерить logo-mark.svg (7-куба cluster) как launcher PNG —
  слишком детализировано, сливается на маленьких размерах.
- Не использовать spark.svg (4-конечная sparkle) — слишком абстрактно,
  не узнаваемо как Pyrita.
- Не использовать photo-realistic 3D рендеры (icon-a/b/c.png) —
  details теряются при downscale.

История попыток до AI-gen: см. commits `cff6ce0` (icon-b-pyrite-tight
foreground + spark notification) и `7a6b5ec` (logo-mark cluster
foreground + 7-hex silhouette) на ветке `feature/phase-c-vpn-integration`.
