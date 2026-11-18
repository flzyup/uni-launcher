# Release 包用 R8 全量混淆（release 构建实测会产出 r8-map-id，说明 minifyEnabled 生效）。
#
# 已知会崩的一条：kotlinx-coroutines-android 靠
# META-INF/services/kotlinx.coroutines.internal.MainDispatcherFactory 这个服务发现文件
# 注册 Android 主线程调度器。R8 全量模式会把这个资源删掉，于是第一次碰 Dispatchers.Main
# 就在类初始化时抛：
#   IllegalStateException: Module with the Main dispatcher is missing
# 表现为进桌面即 "屡次停止运行"（attach 到窗口时触发插件初始化）。
#
# 现场：Android 12 / 1080x1920 设备，versionCode 2062 release 包，堆栈
#   ExceptionInInitializerError at View.onAttachedToWindow
#   Caused by: IllegalStateException: Module with the Main dispatcher is missing

-keep class kotlinx.coroutines.android.AndroidDispatcherFactory { *; }
-keep class kotlinx.coroutines.internal.MainDispatcherFactory { *; }
-keepnames class kotlinx.coroutines.android.** { *; }

# 服务文件的字面量名字不能被改写，否则 keep 规则匹配不到实际写进去的字符串。
-keepclassmembers class kotlinx.coroutines.** {
    volatile <fields>;
}

# 插件注册表反射创建插件实例，混淆后名字对不上。
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
