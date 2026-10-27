plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "xyz.i4o.uni.launcher"
    compileSdk = flutter.compileSdkVersion
    buildFeatures { buildConfig = true }


    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "xyz.i4o.uni.launcher"
        minSdk = 24
        // Dedicated Android 9 head unit, distributed locally rather than through Play.
        targetSdk = 28
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    lint {
        // Keep release lint enabled; the Play target API deadline does not apply here.
        disable += "ExpiredTargetSdkVersion"
    }

    sourceSets.getByName("main") {
        java.srcDirs("src/main/java/xyz/i4o/uni/launcher/integration", "src/main/java/xyz/i4o/uni/launcher/core")
        assets.srcDir(layout.buildDirectory.dir("generated/officialCatalog").get().asFile)
    }
    signingConfigs {
        create("uniLocal") {
            storeFile = file(System.getenv("UNI_SIGNING_STORE") ?: "/data/tools/linkco-android/uni-debug.keystore")
            storePassword = "android"
            keyAlias = "uni-debug"
            keyPassword = "android"
        }
    }
    buildTypes {
        debug { signingConfig = signingConfigs.getByName("uniLocal") }
        release {
            // Local test distribution using the existing baseline development certificate.
            signingConfig = signingConfigs.getByName("uniLocal")
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

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

val syncOfficialCatalog by tasks.registering(Copy::class) {
    from("../../../analysis/official-widgets.json")
    into(layout.buildDirectory.dir("generated/officialCatalog"))
}
tasks.named("preBuild") { dependsOn(syncOfficialCatalog) }
