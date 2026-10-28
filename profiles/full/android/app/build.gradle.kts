import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPath = System.getenv("ANDROID_KEY_PROPERTIES")
if (!signingPath.isNullOrBlank()) {
    file(signingPath).inputStream().use { signingProperties.load(it) }
    for (key in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        require(!signingProperties.getProperty(key).isNullOrBlank()) {
            "Missing $key in ANDROID_KEY_PROPERTIES"
        }
    }
}
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    require(!signingPath.isNullOrBlank()) {
        "Release builds require ANDROID_KEY_PROPERTIES pointing to an external signing properties file"
    }
}

android {
    namespace = "org.discourse.nativeapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "org.discourse.native"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (!signingPath.isNullOrBlank()) {
            create("upload") {
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("upload")
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
