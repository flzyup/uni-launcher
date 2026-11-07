plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "xyz.i4o.uni.launcher"
    compileSdk = flutter.compileSdkVersion
    buildFeatures { buildConfig = true }

    // Compress native libraries in APKs. Android extracts them at install
    // time; this reduces transfer size at the expense of installed disk usage.
    packaging {
        jniLibs { useLegacyPackaging = true }
    }


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
        // 全项目只有一张证书：AOSP 测试签名（testkey）。
        //
        // 车机只认这张。`android.car.permission.CAR_VENDOR_EXTENSION`、原车媒体中心的
        // 传输回调、车控与氛围灯通道，全是 signature|privileged —— 按证书授予，换一张
        // 证书这些能力立刻消失（原车 SDK 连句柄都拿不到）。所以 debug / profile /
        // release 三个构建类型、以及 tools/sign_car_apk.py 出的实车包，全部签同一张，
        // 不再有「开发证书 + 实车证书」两套。
        //
        // 核对指纹：
        //   SHA-256 C8:A2:E9:BC:CF:59:7C:2F:B6:DC:66:BE:E2:93:FC:13:F2:FC:47:EC:77:BC:6B:2B:0D:52:C1:1F:51:19:2A:B8
        //   SHA-1   27:19:6E:38:6B:87:5E:76:AD:F7:00:E7:EA:84:E4:C6:EE:E3:3D:FA
        //   主题    CN=Android, OU=Android, O=Android, L=Mountain View, ST=California, C=US
        //
        // 私钥不入库（.gitignore 的 `**/*.keystore`）。查找顺序：
        //   1) UNI_SIGNING_STORE 环境变量（换机器/CI 只改这一处）
        //   2) android/signing/uni-debug.keystore（本机默认）
        //   3) /data/tools/linkco-android/uni-debug.keystore（原构建机的绝对路径）
        // 三个都没有就直接构建失败。
        //
        // 曾经这里会悄悄回落到 ~/.android 的证书：同一台机器两天里产出两个签名的包，
        // 设备上覆盖安装被系统拒绝（INSTALL_FAILED_UPDATE_INCOMPATIBLE），而构建日志
        // 一句提示都没有。宁可构建失败，也不再猜。
        create("aospTest") {
            val candidates = listOfNotNull(
                System.getenv("UNI_SIGNING_STORE")?.let { File(it) },
                rootProject.file("signing/uni-debug.keystore"),
                File("/data/tools/linkco-android/uni-debug.keystore"),
            )
            val store = candidates.firstOrNull { it.isFile }
                ?: throw GradleException(
                    "找不到 AOSP 测试签名 keystore。把 uni-debug.keystore 放到 " +
                        "app/android/signing/，或用 UNI_SIGNING_STORE 指定绝对路径。已尝试：\n  " +
                        candidates.joinToString("\n  ") { it.absolutePath }
                )
            storeFile = store
            storePassword = "android"
            keyAlias = "uni-debug"
            keyPassword = "android"
            enableV1Signing = false
            enableV2Signing = true
            // v3 打开：Android 9 起系统认它，装上同样一张证书，但多一层密钥轮换/降级保护。
            // minSdk 24 的机器仍然按 v2 验签，不影响安装。
            enableV3Signing = true
        }
    }
    buildTypes {
        debug { signingConfig = signingConfigs.getByName("aospTest") }
        // Flutter 的 profile 产物同样要能装到车上：只换证书。
        // 不能 initWith(release) —— 那会把 release 的 R8 与 keep 规则拖进 profile，
        // 而 integration_test 插件只在 profile 的 classpath 上，R8 直接报缺类。
        maybeCreate("profile").apply {
            signingConfig = signingConfigs.getByName("aospTest")
        }
        release {
            signingConfig = signingConfigs.getByName("aospTest")
            // R8 runs for release. Two things must survive it: kotlinx-coroutines' service
            // loader entry for the Main dispatcher (otherwise the app dies in
            // View.onAttachedToWindow with "Module with the Main dispatcher is missing") and the
            // Flutter plugin registrant. See proguard-rules.pro for the evidence.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
