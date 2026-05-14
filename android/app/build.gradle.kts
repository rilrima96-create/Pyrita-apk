import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Загружаем secrets из android/key.properties. Файл НЕ коммитится в репо
// (см. android/.gitignore). На CI создаётся декодом SIGNING_KEYSTORE_BASE64
// GitHub Secret (см. .github/workflows/build-apk.yml шаг "Decode keystore").
// Локально — генерируется keytool'ом и заполняется вручную.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.pyrita.pyrita_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.pyrita.pyrita_app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Signing configs. На tag-сборках (CI build-release job) использует release
    // keystore, на push-сборках (debug) — стандартный debug keystore Flutter'а.
    // Если key.properties отсутствует (новая dev-машина без секретов) —
    // signingConfigs.release просто не настраивается, и build.release падает
    // с понятной ошибкой. Это лучше чем неявно подписать debug-ключом.
    signingConfigs {
        create("release") {
            val alias = keystoreProperties["keyAlias"] as String?
            val kPass = keystoreProperties["keyPassword"] as String?
            val sFile = keystoreProperties["storeFile"] as String?
            val sPass = keystoreProperties["storePassword"] as String?
            if (alias != null && kPass != null && sFile != null && sPass != null) {
                keyAlias = alias
                keyPassword = kPass
                storeFile = file(sFile)
                storePassword = sPass
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // Минификацию (R8/proguard) пока не включаем — добавим в Phase D
            // (требует proguard-rules.pro и тестирования что Flutter
            // engine'овые классы не вырезаются).
        }
    }

    // Phase C: libtun2socks.so (bundled в jniLibs) запускается plugin'ом через
    // ProcessBuilder — нужен реальный файл на disk в /data/app/<id>/lib/<arch>/.
    // По default AGP 8+ packages .so compressed (extractNativeLibs=false) —
    // .so загружаются в JVM напрямую без extract на disk. useLegacyPackaging=true
    // форсирует extract при install.
    //
    // android:extractNativeLibs="true" в AndroidManifest IGNORED AGP 8+ —
    // только эта gradle настройка работает.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

flutter {
    source = "../.."
}
