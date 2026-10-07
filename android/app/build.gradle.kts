import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("../signing/key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.pocket_bot"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.pocket_bot"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // versionCode is derived from the semver name. Do not use the `+`
        // build number from pubspec.yaml; that counter resets across releases.
        versionCode = androidVersionCode(flutter.versionName)
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storePassword = keystoreProperties.getProperty("storePassword")
                storeFile = rootProject.file("../signing/pocketbot-release.jks")
            }
        }
    }

    buildTypes {
        release {
            // Release APKs must share this certificate. Android rejects an update
            // when the installed app was signed by a different key.
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

// Keep this in sync with lib/utils/android_version_code.dart.
fun androidVersionCode(versionName: String): Int {
    val withoutBuild = versionName.substringBefore('+').trim().removePrefix("v")
    val match = Regex("""^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.]+))?$""").find(withoutBuild)
        ?: return 1
    val major = match.groupValues[1].toInt()
    val minor = match.groupValues[2].toInt()
    val patch = match.groupValues[3].toInt()
    return major * 10_000_000 + minor * 100_000 + patch * 1_000 +
        androidPreReleaseCode(match.groupValues[4])
}

fun androidPreReleaseCode(pre: String): Int {
    if (pre.isEmpty()) return 900
    val beta = Regex("""^beta\.(\d+)$""").find(pre)
    if (beta != null) return beta.groupValues[1].toInt().coerceIn(1, 499)
    val rc = Regex("""^rc\.(\d+)$""").find(pre)
    if (rc != null) return 500 + rc.groupValues[1].toInt().coerceIn(1, 399)
    return 1
}
