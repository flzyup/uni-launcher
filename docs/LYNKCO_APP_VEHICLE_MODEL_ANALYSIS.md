# 领克 App 首页车模分析

分析对象：用户提供的手机安装包 `com.lynkco.customer`，版本 4.2.8、versionCode 402081770，APK SHA-256 `a5f7b4dfa56fd69d626791df34889b059ec07b5e1a37531f3456497b137d67a9`。APK 与截图仅保存在本机临时目录，不纳入项目。本报告基于静态资源和已观察的首页，不含登录信息、车辆标识或接口凭据。

## 可以确认的内容

1. 手机首页呈现一辆斜前方视角的立体领克 05 车型。静态截图只能证明画面外观，不能单独证明它实时渲染，也不能确认被遮挡一侧车门的展示方式。
2. APK 含 `lib/arm64-v8a/libunity.so`、`libil2cpp.so`、`assets/bin/Data/data.unity3d`、IL2CPP metadata 和 Unity SurfaceView 相关资源。它具备 Unity/IL2CPP 能力，但 APK 中有该引擎不等于首页必定采用它。
3. Unity metadata 与脚本表包含 `CarController`、`CarAssetLoad`、`InitDoorController`、`DoorInfo`、`AnimationParentPath` 等名称，以及四门、四窗、尾门相关 `CarAbnormal...` 和 `...OnValueChanged` 名称。它们说明程序包含与车身局部、状态和动画相关的结构；仅凭名称不能推断取值、消息协议或与首页的调用关系。
4. 另有 `AssetBundleManager`、`DoRequestAssetBundleUrl`、`VehicleAssetReferenceData`、`getCarModelMaterial` 和 `CarModelDownloadEvent` 等模型加载、下载相关名称。它们说明存在动态素材加载的可能，但不证明手机当前显示的 05 模型来自何处。
5. 同时可以找到 `UspCarModelView`、`ControlCarUtilsUsp getCurrentStatusBitmap` 和 `getCurrentCarWindow` 等名称，暗示可能存在按状态组合位图的路径。无法据此认定当前首页采用位图合成或断定其调用链。
6. 对 APK 内唯一 `assets/bin/Data/data.unity3d`（SHA-256 `8981730dbd6f5658410f8091aea6bb078e280b3710cf8ef770edecfc35ddefd4`）用 UnityPy 枚举得到 2282 个对象：其中 Mesh、AnimationClip 和 AnimatorController 均为 0，含 824 个 MonoScript、423 个 MonoBehaviour 和 51 个 Texture2D。**这一结论仅针对该文件**，不能排除其他格式、运行时下载或缓存中的车型素材。
7. `classes.dex` 的可正常解析部分仅包含 3 个 stub 类，文件后部仍可看到许多字符串；常规 DEX 静态反汇编无法还原所需的完整 Java 调用链。本报告没有绕过保护或尝试访问账号私有数据。

## 对 UNI 的建议

优先采用「低成本立体感 + 独立状态层」：

- 底层是一张可确认来源的 05 三维渲染图，优先俯视或高角度，四轮和各门位置可辨认；四个胎压值仍放在对应轮位附近，避免遮挡车身。
- 车门、尾门和车窗使用独立标记或局部透明层；已确认开启时突出显示，关闭、未知、过期分别处理，未知不得画成关闭。状态变化时仅更新对应组件，不做持续动画。
- 如果未来获得可使用的分件模型，可离线渲染基础图和少量局部状态图；先验证开门时的遮挡、不同门同时开启及视角关系，再选择分层还是预渲染组合。不能假设单张侧视图能表达被遮挡一侧车门。
- 保留当前用户提供的顶视线稿作为默认和性能回退；先测量实际资源大小、解码内存、绘制耗时与翻屏帧率，再决定是否开放立体风格。无需为了单个卡片引入完整 Unity 运行时。
- 模型与数据分离：本地 PA 车门字段仍需逐门开关实测，确认有效位、枚举和驾驶位后才能驱动状态层；手机 App 的字段名称不证明车机 PA 的编码。

## 尚需确认

- 当前 05 的具体模型文件是否保存在手机 App 的缓存或从服务端动态下载；本次未读取账号私有缓存、未抓包，也未下载服务端素材。
- 首页实际使用 Unity 实时渲染、预渲染位图还是两者结合；需要用户提供可观察的门窗状态变化或在授权范围内检查对应运行时视图。
- 模型素材可否用于项目分发，以及在 820A 设备上的实际性能。当前没有将手机 APK 的任何模型或素材加入 UNI。
