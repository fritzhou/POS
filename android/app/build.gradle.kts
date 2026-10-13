import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningProperties = Properties()
val releaseSigningPath = System.getenv("NEXAPOS_ANDROID_SIGNING_PROPERTIES")
val releaseSigningFile = if (releaseSigningPath.isNullOrBlank()) {
    rootProject.file("key.properties")
} else {
    file(releaseSigningPath)
}
if (releaseSigningFile.isFile) {
    releaseSigningFile.inputStream().use { releaseSigningProperties.load(it) }
}
val releaseSigningFields = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseSigning = releaseSigningFields.all {
    !releaseSigningProperties.getProperty(it).isNullOrBlank()
}
val isReleaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
if (isReleaseRequested && !hasReleaseSigning) {
    throw GradleException("Release signing is required. Configure ignored android/key.properties or NEXAPOS_ANDROID_SIGNING_PROPERTIES; see docs/RELEASE.md.")
}
if (hasReleaseSigning && !rootProject.file(releaseSigningProperties.getProperty("storeFile")).isFile) {
    throw GradleException("The configured release keystore is missing. Preserve the original signing key; do not regenerate it to build an update.")
}

android {
    namespace = "com.nexapos.nexapos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nexapos.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = rootProject.file(releaseSigningProperties.getProperty("storeFile"))
                storePassword = releaseSigningProperties.getProperty("storePassword")
                keyAlias = releaseSigningProperties.getProperty("keyAlias")
                keyPassword = releaseSigningProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isDebuggable = false
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
