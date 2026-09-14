plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

android {
    namespace = "com.areebakhan.transport_app"
    compileSdk = 35
    buildToolsVersion = "35.0.0"

    ndkVersion = "27.0.12077973"

    defaultConfig {
        applicationId = "com.areebakhan.transport_app"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        multiDexEnabled = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.3")

    // Required for flutter_stripe (AppCompat / MaterialComponents themes)
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("com.google.android.material:material:1.12.0")

    // ✅ Firebase BOM (version control here)
    implementation(platform("com.google.firebase:firebase-bom:33.4.0"))

    // ✅ Firebase Analytics
    implementation("com.google.firebase:firebase-analytics-ktx")
}
