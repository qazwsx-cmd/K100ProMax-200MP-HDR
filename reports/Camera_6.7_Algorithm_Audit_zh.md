# 相机 6.7.000280.0 拍照算法与自定义参数逆向报告

分析日期：2026-11-09（北京时间）；同日补充用户提供的 32 位、64 位原生库分析。

**当前进展。0.1.2 已验证覆盖安装签名与旧配置读取，真机连接和成片待测，见第 25 节。第 26 节新增锐化专项追踪，已核对拍摄请求的最终标签、厂商纹理的共用标签分支、成片锐化脚本和原厂着色器计算。**

最初一轮完成了静态拆包、11 个 DEX 的类索引与定向指令检索、关键 Java 调用链反编译，以及打包原生库与依赖检查。后续收到用户从 `/system_ext/lib` 提供的两个 32 位库，以及随后补充的两个 64 位库，新增结果见第 10、11 节，以第 11 节的 64 位结果作为后续开发的优先依据。尚未连接手机，没有拍摄 A/B 样张，没有生成或安装所谓“算法增强版”。以下将代码证据、设备依赖和开发建议分别说明。

**最新设备反馈：固定路径下的 ClearShot XML 确认不存在，本轮搜索也未列出 ClearShot 后端文件，列出了 `/odm/lib64/libmialgoengine.so` 与 `/system_ext/lib64/libmicampostproc_client.so`。因此，目前不能把 ClearShot 参数入口当作这台手机已经启用的调参通路，分析重点转向这两份实际找到的后端文件。详情见第 12 节。**

**后端文件现已收到并分析：引擎为 MIA2 管线／插件架构，客户端通过 HIDL 连接厂商后处理服务。已确认客户端会合并 HDR、MFNR、超分辨率等请求标签，但尚未确认当前插件的独立明度／色度降噪强度参数。旧 JNI 的 V10 期待符号与这份新引擎不匹配，应优先核对实际管线 JSON 与插件。详情见第 13 节。**

**最新采集结果：已解析 79 份配置，其中 54 份为管线描述；在 `vendor.qti.camera.provider-service_64` 的加载清单中确认 MIA2、定制库、All-in-One 和两套 MFNR 包装插件。已定位它们的精确文件路径，并读出原厂配置中的部分多帧策略值。APP、Provider、cameraserver 与 cameramind 的采样清单均未列出旧 JNI 或 postproc client。第 15、16 节记录该轮判断；三份插件的后续结果见第 17 节。**

## 1. 分析对象

| 项目 | 核对结果 |
| --- | --- |
| 原文件 | 相机-com.android.camera-6.7.000280.0.apk |
| 包名 | `com.android.camera` |
| versionName | `6.7.000280.0` |
| versionCode | `670002800` |
| 文件大小 | 200,627,029 字节 |
| SHA-256 | `4637b77d5b365260f8089318179206d42d0ba842fb08109f203f1ea9d3908f63` |
| Manifest | minSdk 29，targetSdk 36；这不等同于已验证任意 Android 版本兼容 |
| DEX | 11 个，共索引 35,387 个类定义 |
| 打包的 arm64 原生库 | 49 个 |

混淆后的类名仅适用于这一份 APK。JADX 对部分复杂方法产生了控制流警告，例如 `Camera2Module.updateMfnr()`、`ProModule.updateMfnr()`。本报告未依据这些方法中不可靠的重建分支推导“强制开启必定可用”，而以配置字段、直接写入方法、标签定义及新旧两套请求构造代码相互核对。

## 2. 已确认的控制层

| 层级 | 本 APK 中的证据 | 可做的工作 |
| --- | --- | --- |
| 应用配置与场景策略 | `Camera2Module`、`ProModule`、`n9.d0`、`n9.e0` | 保存用户参数，按模式和镜头选择配置，使用原有拍摄状态机 |
| 拍摄请求 | `n9.k0`、`r9.*`；另一套为 `Mp.*`、`Wp.*`、`pa.b0` | 在设备支持时发送锐化、纹理、HDR、MFNR 等厂商标签 |
| 图像风格渲染 | `EffectController`、`Wu.g`、`MIVIRenderTag` | 预览与成片的风格参数、额外锐化、对比度、色温、颗粒、柔光 |
| 原生拍摄处理入口 | `MiCamAlgoInterfaceJNI`、`MiaNodeJNI` | 看得到会话、帧、元数据和处理入口，算法实现需要额外的原生库 |

Android 的请求接口负责把采集与处理配置交给相机子系统。HAL 提供的抽象控制模型与具体 ISP 实现并不一一对应，因此一个应用层参数不能被直接解释为某一底层算法的全部强度。[官方说明](https://source.android.com/docs/core/camera/camera3_requests_hal)

### 2.1 主拍摄算法的边界

`com.xiaomi.engine.MiCamAlgoInterfaceJNI` 明确执行：

```java
System.loadLibrary("camera_algoup_jni.xiaomi");
```

它声明的原生方法包括 `createSessionWithSurfaces()`、`createSessionByOutputConfigurations()`、`preProcess()`、`processFrame()`、`processFrameWithSync()` 和 `setMiViInfo()`。`FrameData` 还携带请求元数据、结果元数据及图像缓冲区。

`com.xiaomi.engine.MiaNodeJNI` 另行加载 `camera_mianode_jni.xiaomi`，并通过原生 `processRequest()` 处理帧。

在当前 APK 的 ZIP 文件清单中，没有找到对应的 `libcamera_algoup_jni.xiaomi.so` 与 `libcamera_mianode_jni.xiaomi.so`。这说明这些入口对应的实现没有随当前基础包一起提供。其实际位置、是否在目标机使用、依赖链和动态加载路径仍需从目标 ROM 与运行日志确认，不能仅凭类存在认定所有设备都走这条路径。

包内存在 `libMiFilterSDK.so`、`librender_engine.so`、显著性检测、文档处理等库。它们的存在不能证明主拍摄融合算法已完整包含在 APK 中。包内也有 Qigsaw 动态功能配置，后续分析需要考虑功能拆分包。

## 3. 可自定义的参数及真实含义

下表“已确认”表示已经核对到发送代码与类型，不表示目标手机已执行该参数。

| 功能 | 已确认的入口或标签 | 实施判断与限制 |
| --- | --- | --- |
| 拍摄锐化级别 | `n9.d0.W(int)` → `n9.e0.G0` → `n9.k0.M0()` → `r9.*.m0()` | 可做设备范围内的级别选择。不能承诺最低级等于关闭全管线的全部锐化 |
| 厂商纹理 | `n9.d0.z(int)` → `D0`；Qcom 标签 `com.xiaomi.sharpness.strength` | 与上面的标准厂商锐化级别是不同入口，应分别验证，避免两个控件重复堆叠锐化 |
| 对比度／影调 | `n9.d0.v(int)`、`x(int)`；Qcom 路径会写 `org.codeaurora.qcamera3.contrast.level` | 可做影调调节。内部存在 shadow、hue 等不同命名，不能把它宣传为独立的 HDR 暗部恢复强度 |
| 饱和度 | `n9.d0.U(int)` → `F0` → `n9.k0.J0()` | 可调；Qcom 与 MTK 的编码不同，需要通过原适配层转换 |
| 色温、色调 | `n9.d0.y(int)`、`A(int)`，及厂商 customquality 标签 | 有明确的应用层入口；必须检查自定义画质开关和设备支持 |
| HDR | `n9.d0.M(p9.a)`、`n9.k0.j0()` → `xiaomi.hdr.enabled` | 可接入原有 HDR 状态选择与策略。一个布尔标签不足以替代原有 HDR 检测、多帧曝光与会话配置 |
| 多帧降噪 | `n9.d0.P(int, boolean)` → `f1/g1` → `n9.k0.o0()` | 已确认开关与帧数请求。设备是否接受某个帧数、如何采集与融合，需要实测 |
| 软件多帧 | `xiaomi.swmf.enabled` | 有发送入口；硬件 MFNR 与软件 MFNR 的选择有设备与场景约束 |
| 画质优先 | `xiaomi.imageQuality.isHighQualityPreferred`，类型 Byte | 已确认入口；原代码的偏好默认值就是 true，重复强制开启可能没有任何增益 |
| 风格渲染 | `StyleAdjustEffect` 与 `SharpenEffect` | 可提供精细滑杆，属于风格／后处理，不能代替底层采集与降噪算法 |

### 3.1 锐化不是统一的“0—100”

Qcom 的拍摄锐化标签是 `org.codeaurora.qcamera3.sharpness.strength`，MTK 路径是 `com.mediatek.ispfeature.controlEdgeLevel`。这两种映射来自 `la.B0.C1` 的名称供应器 `la.N.get()`。

在 Qcom 适配器 `r9.e.m0()` 与新请求适配器 `Wp.e.F()` 中，大于 6 的数会被改成 0。因此把界面上的 0—100 数值直接写入这个入口，会造成错误映射。

原应用已经读取 `org.codeaurora.qcamera3.sharpness.range` 与默认值。`s2.T0` 会使用设备信息构造专业模式的锐化选项，其原生 UI 还有模式与机型功能开关限制。合适的做法是读取每个镜头的实际范围和默认值，再将控件映射到可用级别。

另外两条锐化入口也应一起检查：

- 厂商纹理参数 `com.xiaomi.sharpness.strength`。
- 渲染脚本中的 `SharpenEffect;SharpenIntensity=...` 与 `StyleAdjustEffect` 的 `SharpenIntensity`。

减少额外加锐，是值得验证的自然细节方案。它能否改善白边、树叶纹理、发丝或石刻质感，要看原图和这些入口在目标机的实际效果，不能通过静态分析提前保证。

### 3.2 多帧降噪能请求帧数，无法任意指定融合实现

下面这条调用链是明确的：

```text
n9.d0.P(frameCount, enabled)
  → n9.e0.g1 / f1
  → n9.k0.o0(applyType, builder, capabilities, configs)
  → xiaomi.mfnr.enabled
  → xiaomi.mfnr.frameNum（开启且帧数大于 0 时）
```

新的请求构造路径 `Mp.b.y()` 与 `Wp.e.v()` 也存在对应处理。旧路径和新路径都对应用阶段做了条件判断，非指定采集阶段会关闭相应请求。这里的 `applyType == 3` 是请求应用阶段，不能当成“专业模式编号”。

这提供了开发 MFNR 策略开关和实验性帧数设置的基础。它没有暴露一个已经确认的、跨机型通用的“降噪强度 0—100”参数，也没有证明任意增加帧数都有效。HDR、运动、RAW、超高像素和重处理流配置都会影响执行路径。

对静物可以试验原厂策略与设备接受的较高帧数；人物或移动物体应保留运动判定。实际拍摄时间、鬼影、涂抹与清晰度必须一起评估。

### 3.3 画质优先很可能已经开启

`Camera2Module.updateHighQualityPreferred()` 经 `n9.i.accept()` 更新配置并调用 `n9.k0.m0()`。后者先通过 `n9.e.X2()` 检查能力，再由 Qcom 适配器发送 Byte 0 或 1。

更关键的是 `com.android.camera.data.data.A.Y()`：设备支持时读取 `pref_camera_high_quality_preferred_key`，默认值为 **true**。因此开发时应先显示当前实际状态，核对请求是否发出，再评估这个开关能否带来变化。单纯写入 true 不应被算作已完成的算法优化。

### 3.4 自定义画质存在两套实现

`Camera2Module.updateStyleTexture()`、`updateStyleTone()`、`updateStyleTune()`、`updateStyleTemperature()` 会根据 `com.android.camera.data.data.I.S0()` 等条件，选择渲染参数或厂商请求参数。

| 参数 | Qcom 的厂商请求标签 | MTK 的厂商请求标签 |
| --- | --- | --- |
| 自定义画质开关 | `com.xiaomi.customquality.enable` | 同一公共标签定义 |
| 纹理 | `com.xiaomi.sharpness.strength` | `com.mediatek.ispfeature.controlTextureLevel` |
| 色调 | `com.xiaomi.customcolortune.customtuneLevel` | `com.mediatek.ispfeature.controlHueLevel` |
| 色温 | `com.xiaomi.customcolortemperature.customtemperatureLevel` | `com.mediatek.ispfeature.controlTemperatureLevel` |
| 内部 shadow／影调路径 | `org.codeaurora.qcamera3.contrast.level` | `com.mediatek.ispfeature.controlShadowLevel` |
| 饱和度 | `org.codeaurora.qcamera3.saturation.use_saturation` | `com.mediatek.ispfeature.controlSaturationLevel` |

Qcom 对比度适配中有 `i + 1` 转换，饱和度还有非线性级别映射；这些转换并非所有 customquality 调用都共享。新增参数必须结合具体调用点测试，不应把同一个数值同步塞到多个标签。

## 4. 风格面板可以做到什么

`com.xiaomi.camera.effect.EffectController.c()` 生成 `Wu.g`，随后 `MIVIRenderTag.TagForCandy.getPictureStyleCandyParams()` 把它变成包含以下参数的脚本：

```text
StyleAdjustEffect
  Algos
  SharpenIntensity
  ContrastIntensity
  SaturationIntensity
  Temperature
  Tint
  Grain
  VignetteIntensity
```

| 界面参数 | 原应用数据范围 | 渲染路径的转换 |
| --- | --- | --- |
| 纹理／风格锐化 | -50 到 50 | `i / 100.0`，即 -0.5 到 0.5 |
| 影调／对比度 | -50 到 50 | `i / 100.0` |
| 鲜艳度 | -50 到 50 | 负值乘 2，正值乘 1.4，最终 -1 到 0.7 |
| 色温 | -50 到 50 | `i * 2 / 100.0` |
| 色调 | -50 到 50 | `i * 2 / 100.0` |
| 颗粒 | 0 到 100 | `i / 100.0` |
| 暗角 | -50 到 50 | `i / 100.0` |

这些是**这一版应用的 UI／渲染转换**，不是所有原生厂商标签的合法取值范围，也不代表渲染库内部算法已完成逆向。

还可调用原有黑柔／白柔效果。`getPictureStyleCandyParams()` 根据柔光档位拼接 `BlackMistEffect` 或 `WhiteMistEffect`。

实施时有三个关键点：

1. 预览使用 `EffectController.g0()` 推送渲染属性，成片使用 `MIVIRenderTag` 生成脚本，两条路径都要验证。
2. `Wu.g.c` 是算法位掩码。锐化为 64，对比度为 8，饱和度为 4，色温为 1，Tint 为 2，颗粒为 16，暗角为 32。只修改浮点值却不更新位掩码，可能没有效果。
3. `EffectController.c()` 在特定模式／功能条件不满足时会把相关数值归零。需要对目标模式单独接入，不能仅增加一个设置页面。

**“NoiseStrength”与“Grain”不能直接称为降噪。** 本次追踪的滤镜路径将它们用于噪声／颗粒风格参数，且 `setPictureTypeNoise()` 对应脚本的 `Grain`。另外，检索到的 `pref_intelligent_noise_reduction_key` 属于录像声音设置，不能用于证明照片有独立降噪滑杆。

## 5. 目前不能承诺的功能

| 目标 | 本次调查结论 |
| --- | --- |
| 明度降噪、色度降噪分别调节 | 旧 ClearShot 有参数结构，但目标设备未证实该通路在用；当前三份活动链插件尚未提供可直接开放的有效强度／范围，见第 17 节 |
| HDR 高光、暗部、局部对比各自独立调节 | 有 HDR 开关、检测元数据和影调入口，缺少其底层融合与局部映射参数的完整证据 |
| 自定义每帧曝光与 HDR 融合权重 | 存在 HDR／夜景多帧处理逻辑；尚未验证可供用户任意设定的可靠接口 |
| 消除锐化白边而完全保留全部细节 | 已有降低加锐的切入点；效果需要样张证明，无法恢复在更早阶段已经损失的细节 |
| 更换 AI 降噪模型、修改去马赛克／重建实现 | 需要目标机原生算法库、依赖、模型或 tuning 以及进一步分析 |
| 超高像素、普通、专业、录像共用一套拍照算法 | 各自的会话、输出与状态约束不同，必须分别适配与验证 |

对 11 个 DEX 的直接字段引用检索，未找到 `CaptureRequest.NOISE_REDUCTION_MODE`、`EDGE_MODE`、`TONEMAP_MODE`、`TONEMAP_CURVE`、`TONEMAP_PRESET_CURVE` 的直接引用。相同检索方法在 `n9.k0` 中成功找到曝光补偿、AE、ISO 等标准字段，作为检索正向校验。这个结果仅说明未发现这些直接 DEX 引用，不排除反射、字符串构造或原生层使用。

Android 标准降噪模式仍可作为设备支持时的实验功能，但应先读取可用模式并验证结果。官方把 HIGH_QUALITY 定义为可能降低帧率的模式，而不是某个可量化的降噪强度。自定义 TONEMAP 曲线还可能关闭该处理阶段的复杂色彩映射，不能直接视作原厂 HDR 的增强开关。[CaptureRequest 文档](https://developer.android.com/reference/android/hardware/camera2/CaptureRequest)

## 6. 推荐的第一版功能

建议先做独立的“拍摄画质设置”面板，并保留一键恢复原厂值。

| 设置项 | 默认行为 | 开发优先级 |
| --- | --- | --- |
| 拍摄锐化级别 | 使用设备默认值；支持后允许下调／上调 | 高 |
| 厂商纹理与额外风格锐化 | 分开显示其真实含义；避免额外锐化重复叠加 | 高 |
| 对比度、饱和度、色温、色调 | 默认沿用原设置；保存每镜头、每模式的覆盖值 | 高 |
| 颗粒、暗角、柔光 | 独立风格设置，明确它们的视觉用途 | 高 |
| 画质优先 | 显示当前值与支持状态，保留原厂默认 | 高 |
| HDR | 接入现有关闭／自动／开启状态与拍摄策略 | 中，需要目标模式验证 |
| MFNR | 保留原厂策略，可选关闭作对照；帧数作为受限实验项 | 中，需要设备验证 |
| 标准 NR／Tonemap 实验 | 仅在报告支持时开放，单独验证 | 低 |

三组配置可以作为测试方向，不应先宣称是提升画质的成品预设：

- **自然细节**：减少额外加锐，轻调纹理，保留 HDR 与运动策略。
- **静物优先**：核对画质优先状态，试验设备接受的 MFNR 帧数，同时评估耗时与纹理保留。
- **运动拍摄**：遵循原厂运动检测与曝光选择，评估残影和成功率。

## 7. 各模式的适配要求

| 模式 | 本次证据与后续工作 |
| --- | --- |
| 普通拍照 | `Camera2Module` 具有完整配置入口，适合作为首个验证路径 |
| 2 亿像素／超高像素 | 代码有 QCFA、RAW、重处理及 SR 的特殊分支；目标传感器的输出分辨率和能力需要真机确认 |
| 专业 JPEG／HEIF | `ProModule` 覆写了锐化、对比度、饱和度和 MFNR 更新逻辑，不能只挂普通模式的方法 |
| RAW | 需要保持 RAW 的用途，区分 RAW 数据和伴随 JPEG 的效果；不能把后期风格是否出现在 RAW 中作为唯一判断 |
| 录像 | 需要独立核对录像请求与编码前渲染路径；本次未完成逐项录像算法审计，不能套用拍照帧数策略 |

还要分别核对新旧两套请求构造通路。只覆盖 `n9.k0` 或只覆盖 `Wp.*`，都可能遗漏目标设备实际使用的路径。

## 8. 判断“优化成功”的依据

每个设置至少分成“应用已配置”“请求已写入”“设备已报告或有成片证据”三个状态。`la.F0` 的部分写入方法会捕获异常或静默处理，不报错并不证明标签有效。即使在请求中读回原值，也不能单独证明 HAL 按预期执行。

建议以相同场景、镜头、构图和曝光做原厂／单变量 A/B，保留原图与元数据。优先检查：

- 树叶、草地、发丝、文字和石刻的真实细节，以及边缘白边。
- 暗部细纹、彩噪、涂抹和颜色偏移。
- 窗口、天空和灯光的高光过渡。
- 人物肤色、移动物体的鬼影和拍摄成功率。
- 从按下快门到最终大图可用的时间、文件分辨率与格式。
- 预览、快速缩略图与相册最终成片之间的差异。

首轮应采用单参数、小范围测试。只有找到有效且有益的设置，再组合成预设。

进一步分析底层算法所需的材料，可以从目标手机实际加载的 `libcamera_algoup_jni.xiaomi.so`、`libcamera_mianode_jni.xiaomi.so` 开始，再沿它们的依赖确定需要哪些库。还需同一 ROM 的相机调参文件、设备能力与拍照日志。当前尚未验证库的实际安装路径，不应假定所有机型都位于同一个目录。

## 9. 关键证据定位

| 编号 | 类与方法 | 说明 |
| --- | --- | --- |
| E1 | `com.xiaomi.engine.MiCamAlgoInterfaceJNI` 静态初始化、原生方法 | 外部算法库、会话与处理入口 |
| E2 | `com.xiaomi.engine.MiaNodeJNI` 构造器、`process()` | 第二个外部原生处理入口 |
| E3 | `n9.d0.W/U/v/P/w/x/y/z/A/M`，`n9.e0` 字段 | 锐化、饱和、对比、MFNR、自定义画质与 HDR 配置 |
| E4 | `n9.k0.M0/J0/J/o0/j0/m0/M/N/O/Q` | 配置到请求的写入与条件 |
| E5 | `la.B0`；`la.N/M/L/J/g/j/v0/x/K`；`H8.d`；`imagecodec.a/b/c` 的供应器 | 标签名称、类型与芯片平台差异 |
| E6 | `r9.e.m0/l0/k/A/P`；`r9.d` 对应方法 | Qcom／MTK 数值映射 |
| E7 | `Mp.b.y`、`Mp.e`、`Mp.d`、`Wp.e.F/E/c/v`、`pa.b0.i` | 新请求构造路径与参数缓存 |
| E8 | `s2.T0`；`la.x0.W1/X1`；`n9.e.o0` | 锐化范围、默认值与专业模式 UI |
| E9 | `Camera2Module.updateHighQualityPreferred`；`n9.i.accept`；`data.data.A.Y`；`n9.e.X2` | 画质优先调用链、能力检查与默认 true |
| E10 | `Camera2Module.updateStyleTexture/Tone/Tune/Temperature/Vibrance` | 渲染路径与厂商标签路径的分流 |
| E11 | `EffectController.c/g0/i/k0/l0/m0/n0/o0/p0/q0`；`Wu.g` | 风格参数、位掩码、预览同步与清零条件 |
| E12 | `MIVIRenderTag.TagForCandy.getPictureStyleCandyParams/getFilterCandyParams`；成片脚本组装 | 成片风格、颗粒、柔光与额外锐化 |
| E13 | `features.mode.pro.photo.ProModule.updateSharpness/updateContrast/updateSaturation/updateMfnr/updateSuperResolution` | 专业模式存在独立处理与特殊限制 |
| E14 | `la.F0`；`n9.d.S0`；`n9.e.X2/V2` | 失败处理、标签存在检查与功能能力判断 |

本报告提供的是开发可行性及可核对的入口清单。可以据此进入参数探测与模块实现阶段；“画质已经提升”仍需通过目标机的最终成片与拍摄稳定性验证。

## 10. 用户提供的原生库补充分析

### 10.1 文件已确认是 32 位

用户报告文件来自 `/system_ext/lib`，同名文件也存在于 `/system_ext/lib64`。本次直接检查上传文件的 ELF 头，结果如下。

| 文件 | 大小 | 架构 | SHA-256 |
| --- | --- | --- | --- |
| `libcamera_algoup_jni.xiaomi.so` | 38,264 字节 | ELF32、ARM、EABI5、小端 | `0690ceee22af0008b9dca05eb9c2dd0d660307de21991484e15f425bd41b9ec5` |
| `libcamera_mianode_jni.xiaomi.so` | 48,584 字节 | ELF32、ARM、EABI5、小端 | `2e0c032ea7420a887ec1652c5791cfa38baee95bb0e98d39463428cc7e811077` |

此前 APK 的 49 个打包原生库全部位于 `lib/arm64-v8a/`。因此这两个 32 位样本可用于追踪设计与依赖，但不能用于给相机 64 位实现直接套用函数地址、结构体偏移或二进制补丁。下一步应核对 `/system_ext/lib64` 下的同名文件，并结合进程加载记录确认实际路径。

还有一个值得关注的细节：32 位 algoup 样本本身包含且引用了 `lib64` 后端路径。这种架构不匹配进一步说明，不能只看文件在 ROM 中存在，就认定这条代码在当前拍摄中有效执行。

### 10.2 已追到动态加载的下一层库

以下结果结合了 ELF 导入／导出符号、ARM Thumb 反汇编、PC 相对字符串地址和调用点，超过了单纯字符串检索的证据强度。

| 上传库／函数 | 代码中的后端路径 | 已确认的加载方式 |
| --- | --- | --- |
| algoup 的 `Jni_Init_V10()` | `/vendor/lib64/libmialgoengine.so` | `android_load_sphal_library()`，随后用 `dlsym()` 解析 `MI_open_lib`、`MIAGetApiVersion` |
| algoup 的 `Jni_Init_V11()` | 先 `/system/lib64/libmicampostproc_client.so`，失败分支再尝试 `/system_ext/lib64/libmicampostproc_client.so` | `dlopen()`，随后解析 `miOpenLib`、`GetExtInterafce`、`GetExtVersion`；`GetExtInterafce` 为样本中的原始拼写 |
| mianode 的 `QVisidonClearshot::ParseAlogLib()` | `/vendor/lib/libVDDualCameraClearShot.so` | `android_load_sphal_library()` 与 `dlsym()` |
| mianode 的 `QVisidonClearshot_S::ParseAlogLib()` | `/vendor/lib/libVDClearShot.so` | `android_load_sphal_library()` 与 `dlsym()` |

这已经把此前两个 JNI 桥接库后面的库名具体定位出来。上述路径表示**上传样本中确实存在的加载分支**，不表示它们全部存在于用户手机、全部加载成功或每次拍照都使用。64 位对应库也可能与这些 32 位样本不同。

两个上传库的 `DT_NEEDED` 分别有 20 项和 16 项，主要是 Binder、相机元数据、图形缓冲区、日志、C/C++ 运行库等系统依赖。mianode 还依赖 `libxml2.so`。核心后端通过运行时加载，因此仅看 `DT_NEEDED` 会遗漏上表中的算法依赖。

### 10.3 找到真实的 ClearShot 调参读取路径

在 `QVisidonClearshot_S::init()` 中，代码将以下路径传给 `parser_parameter()`：

```text
/vendor/etc/camera/visidon_clearshot_params_algoup.xml
```

已在解析函数中确认被比较和读取的字段包括：

| 字段名 | 可合理解释的调参方向 |
| --- | --- |
| `luminance_noise_reduction` | 明度降噪 |
| `chroma_noise_reduction` | 色度降噪 |
| `sharpen` | 锐化 |
| `effectiveFrames` | 有效帧数相关设置 |
| `input_brightness_threshold` | 输入亮度阈值 |
| `input_sharpness_threshold` | 输入清晰度阈值 |
| `noise_reduction_adjustment` | 降噪调整数组 |
| `moving_pixels_rejection_threshold` | 运动像素排除阈值 |
| `moving_object_noise_removal` | 运动对象噪声处理相关设置 |

这组字段属于 ClearShot 参数解析路径，和滤镜的颗粒参数不同。解析代码包含 `atof()`／`atoi()` 转换和参数存储，`set_parameter()` 选择并复制参数，处理函数进一步调用 `VDClearShot_SetNRForBrightness()`、`VDClearShot_Process()`。双摄分支则解析 `VDDualCameraClearShotSetNRForBrightness`、`VDDualCameraClearShotProcess` 等函数指针。

因此，现在已有“原生降噪与锐化可能可调”的更直接证据。仍然缺少以下验证：

- 64 位 mianode 是否保留同样的参数和读取路径。
- 对应 XML 是否存在、内容怎样分设备或分档配置。
- 目标模式是否实际调用这个 ClearShot 分支。
- 参数合法范围、默认值及其对最终成片的影响。

不能据此立即做一个标为“全模式明度／色度降噪”的控件，也不能将尚未知范围的参数直接设成 0—100。

### 10.4 本轮反汇编核对点

下列地址均为**本次上传的 ELF32 样本的虚拟地址**，仅用于复核，不能移用于 64 位文件。

| 文件 | 地址／函数 | 核对内容 |
| --- | --- | --- |
| algoup | `0x65b4`，`Jni_Init_V10` | `0x65ce` 调用厂商库加载接口，参数指向 `libmialgoengine.so` 路径 |
| algoup | `0x682c`，`Jni_Init_V11` | `0x683e` 与 `0x6862` 为两个 postproc client 路径的加载点 |
| mianode | `0x80fc`，双摄 `ParseAlogLib` | `0x811c` 加载 `libVDDualCameraClearShot.so` |
| mianode | `0x8c54`，单摄 `ParseAlogLib` | `0x8c74` 加载 `libVDClearShot.so` |
| mianode | `0x9224`，`QVisidonClearshot_S::init` | `0x928e` 取得 XML 路径，`0x9290` 调用参数解析函数 |
| mianode | `0x8df4`，`parser_parameter` | 解析相关明度、色度、锐化及帧数字段 |
| mianode | `0x91a0`，`set_parameter` | 选择并复制运行参数 |
| mianode | `0x92f4`，`process` | `0x9540` 调用按亮度设置降噪接口，`0x95ba` 调用 ClearShot 处理接口 |

### 10.5 下一步材料的优先顺序

先提供已经找到的 `/system_ext/lib64/libcamera_algoup_jni.xiaomi.so` 与 `/system_ext/lib64/libcamera_mianode_jni.xiaomi.so`。它们能确定与相机架构对应的入口及下一层真实路径。

随后按确认的依赖寻找 `libmialgoengine.so`、`libmicampostproc_client.so`、`libVDClearShot.so`、`libVDDualCameraClearShot.so`，以及上述 ClearShot XML。不存在的文件无需替换成网上其他机型版本。保留相同 ROM 的原始文件，才能继续核对调用关系和参数含义。

## 11. 64 位原生库与 APK 调用链核对

### 11.1 新上传文件确认为 AArch64

用户随后上传的两个带 `(1)` 文件名后缀的附件均为 ELF64、AArch64、小端共享库。`(1)` 是上传文件名的一部分，库自身的 SONAME 仍是原来的库名。

| 上传文件 | 字节数 | SHA-256 |
| --- | --- | --- |
| `libcamera_algoup_jni.xiaomi(1).so` | 85,072 | `f88381ea9b18a6dc2d60dae4a1bea167b97c00877b50c3633dfeb7d202773ec9` |
| `libcamera_mianode_jni.xiaomi(1).so` | 101,040 | `68238fe78862a1fa70f8dd672e3f639d6a018d6ca323c3988ffdc114e4fa5720` |

本轮完成 AArch64 定向反汇编、PLT 与 ELF 重定位关联、字符串地址核对，并补充扫描 11 个 DEX 中对引擎接口的直接调用。以下地址全部属于这两个 64 位样本。

### 11.2 后端选择顺序得到确认

`Java_com_xiaomi_engine_MiCamAlgoInterfaceJNI_init` 位于 `0xa14c`。它先调用 `Jni_Init_V10()`，仅在返回值为 **-1** 时转去 `Jni_Init_V11()`。这并不是在看到当前 Android 版本后就直接选择 V11。

| 分支 | 64 位库中的实际路径与证据 |
| --- | --- |
| V10 | `Jni_Init_V10()` 位于 `0x9b3c`；`0x9b70` 调用 `android_load_sphal_library()` 加载 `/vendor/lib64/libmialgoengine.so`，再解析 `MI_open_lib`、`MIAGetApiVersion` |
| V11 | `Jni_Init_V11()` 位于 `0x9e78`；先在 `0x9e9c` 尝试 `/system/lib64/libmicampostproc_client.so`，失败分支在 `0x9ed8` 尝试 `/system_ext/lib64/libmicampostproc_client.so` |
| V11 接口 | 随后解析 `miOpenLib`、`GetExtInterafce`、`GetExtVersion`，其中 `GetExtInterafce` 的拼写以二进制为准 |

这说明两组后端是有回退关系的候选路径，不能表述成每次拍照都必须同时执行两组引擎。库文件是否存在、初始化是否成功和后续模式是否走该会话仍需真机确认。

64 位 mianode 的两个加载分支也已核实：

- `QVisidonClearshot::ParseAlogLib()`，`0xe1c4` 起，`0xe208` 加载 `/vendor/lib64/libVDDualCameraClearShot.so`。
- `QVisidonClearshot_S::ParseAlogLib()`，`0xef18` 起，`0xef5c` 加载 `/vendor/lib64/libVDClearShot.so`。

### 11.3 参数不只存在于 32 位旧代码

64 位 `QVisidonClearshot_S::init()` 位于 `0xf6d8`。`0xf760` 取得 `/vendor/etc/camera/visidon_clearshot_params_algoup.xml` 的字符串地址，`0xf76c` 调用 `parser_parameter()`，后者位于 `0xf148`。

解析过程明确比较字段名，使用 `atof()` 或 `atoi()` 转换并写入参数记录。已核对如下映射。

| 字段 | 类型 | 单条运行参数内的字节偏移 | 可调方向 |
| --- | --- | --- | --- |
| `luminance_noise_reduction` | float32 | `0x00` | 明度降噪 |
| `chroma_noise_reduction` | float32 | `0x04` | 色度降噪 |
| `sharpen` | float32 | `0x08` | 锐化 |
| `brightening` | int32 | `0x0c` | 亮度增强相关控制 |
| `color_boost` | int32 | `0x10` | 色彩增强相关控制 |
| `moving_object_noise_removal` | int32 | `0x14` | 运动对象噪声处理相关控制 |
| `input_sharpness_threshold` | int32 | `0x18` | 输入清晰度阈值 |
| `allocate` | int32 | `0x1c` | 内部设置，语义尚不充分，不宜直接开放为用户控件 |
| `noise_reduction_adjustment` | 6 个 int32 | `0x20`—`0x34` | 分项降噪调整 |
| `input_brightness_threshold` | float32 | `0x38` | 输入亮度阈值 |
| `baseFrame` | int32 | `0x3c` | 基准帧相关设置 |
| `effectiveFrames` | int32 | `0x40` | 有效处理帧数相关设置 |
| `useTripodMode` | int32 | `0x44` | 三脚架相关设置 |
| `moving_pixels_rejection_threshold` | float32 | `0x48` | 运动像素排除阈值 |
| `deghosting_strength` | int32 | `0x4c` | 去鬼影相关设置 |

这张表描述的是与本次 SHA-256 对应样本的结构布局。字段可调方向主要按名称和调用上下文解释，尚未得到各项合法范围、精确单位、取值效果或跨版本稳定性。不能将此表当成跨机型通用结构体，也不能直接给所有字段填入同一种 0—100 数值。

`set_parameter()` 位于 `0xf604`，按记录阈值选择并复制运行参数。`process()` 位于 `0xf7dc`，其中也直接存在同类选择与加载逻辑，说明只拦截导出的 `set_parameter()` 不足以保证影响这条处理路径。

更靠后的稳定候选核对点是 `VDClearShot_Process`：

- 处理代码在 `0xfabc` 调用 `VDClearShot_SetNRForBrightness()`，在 `0xfb20` 调用 `VDClearShot_Process()`。
- 本库导出的 `VDClearShot_Process()` 包装函数位于 `0x109f8`，会从第三个参数指向的区域复制 **80 字节**，再调用已加载 API 表中的处理函数。
- 80 字节与上表 `0x00` 至 `0x4f` 的运行参数布局吻合，提供了“XML → 运行参数 → 算法调用”的数据通路证据。

`effectiveFrames` 与传感器实际采集张数必须区分。这里还存在输入计数与缓冲区上限约束，改一个处理参数并不会凭空增加已经采集的原始帧。

### 11.4 APK 确实存在直接调用 ClearShot 的分支

新增 DEX 调用扫描在引擎包外找到 18 条对 `MiCameraAlgo`、`TaskSession`、`MiaNodeJNI` 的直接调用记录，来自 10 个类。对于 ClearShot，关键位置为混淆后的 `Xp.h.b(Ch.b, TaskSession)`。

该方法是带有 `MultiFrameProcessor`／`ClearShotProcessor` 日志的多帧处理器。当捕获任务的算法类型 `bVar.a == 2` 时，它构造帧列表和输出图像，并执行：

```java
MiaNodeJNI.getInstance().process(frameList, outputImage, 2, flag);
```

这里第三个参数是原生节点类型。APK 的 `NodeType` 定义 `NDTP_CLEARSHOT_S = 2`；64 位 `MiaNodeFactory::Initialize()`（`0xcb20`）也在类型为 2 的分支构造 `MiaNodeClearShot_S`，对应构造调用点 `0xcb90`。

因此，已把 APK 中存在的多帧分支与 64 位单摄 ClearShot 节点对上。这仍然不是“用户常规模式已经实测调用”的证明。该任务类型由更上层设备与拍摄策略决定，现代 HAL 也可能走其他处理路径。

### 11.5 现在能制定的自定义方案

独立明度降噪、独立色度降噪、锐化和去鬼影等设置，已经具有比最初 APK 调查更具体的原生入口。建议以以下顺序实施：

1. **只读命中检查**：记录目标模式、镜头、处理函数是否被调用，以及原厂参数。仅在进程映射里看到库被加载，还不算处理函数命中。
2. **建立原厂基准**：读取当前 ROM 的 ClearShot XML，核对设备分组、参数档位和默认值。默认设置保持原厂数据。
3. **单变量测试**：针对已确认命中的路径提供参数覆盖，先比较明度降噪、色度降噪、锐化，再评估运动处理参数。
4. **按路径开放设置**：支持的模式和镜头显示真实状态；未命中路径不显示“已经生效”。继续分别验证普通、超高像素、专业与录像。

实现层面可以研究调参文件的可恢复覆盖，或在最终原生处理入口覆盖运行参数。原有 Java 滤镜脚本入口不能直接替代这组原生调参能力。是否需要进一步解析 ClearShot 后端本体，取决于目标是修改已有参数，还是研究／改变其内部算法实现。

当前最有价值的下一份文件是 `/vendor/etc/camera/visidon_clearshot_params_algoup.xml`。后端本体的后续分析优先沿实际使用路径选择 `libVDClearShot.so`、`libmialgoengine.so` 或 `libmicampostproc_client.so`，不必先假定所有候选都正在使用。

## 12. 目标 ROM 的搜索反馈与调查方向调整

用户随后使用 root 执行文件检查，回传结果为：

```text
ls: /vendor/etc/camera/visidon_clearshot_params_algoup.xml: No such file or directory
```

对 `/vendor`、`/odm`、`/system_ext`、`/system`、`/product` 中普通文件的搜索，按用户回传输出仅列出：

```text
/odm/lib64/libmialgoengine.so
/system_ext/lib64/libmicampostproc_client.so
```

### 12.1 这份反馈改变了什么

现在可以确认用户检查的固定 XML 路径不存在；本轮 `find -type f` 搜索未列出名称匹配的 ClearShot 文件。此前的 64 位分析证明了 ClearShot 调参代码与 APK 调用分支的存在，尚未证明当前 ROM 的配套后端与配置齐全，也未证明用户实际拍照会执行该分支。它可能是保留的兼容路径，此判断仍是推断。

`find -type f` 不会列出符号链接本身，且默认不跟随符号链接目录。因此，这份搜索结果不等同于遍历了每个符号链接目标。尤其不能仅凭引擎库显示在 `/odm`，就断言代码中的 `/vendor/lib64/libmialgoengine.so` 路径必然无法访问。需要链接检查或运行时加载结果才能定论。

### 12.2 下一步以实际找到的后端为优先

| 用户找到的文件 | 下一轮分析重点 |
| --- | --- |
| `/odm/lib64/libmialgoengine.so` | 核对 `MI_open_lib`、`MIAGetApiVersion` 等接口、算法节点／插件依赖、配置加载路径和元数据参数 |
| `/system_ext/lib64/libmicampostproc_client.so` | 核对 `miOpenLib`、`GetExtInterafce`、`GetExtVersion` 等接口，以及客户端是否继续委托给其他进程或库 |

这两份文件当前仅由用户的搜索输出定位，尚未收到本体、没有完成内容分析。文件存在也不代表处理函数已经命中。

在已提供的 64 位 JNI 库中，V10 加载失败会返回 -1，JNI 初始化入口仅在这个返回值时进入 V11。V11 再依次尝试 system 与 system_ext 下的 postproc client。这些代码条件支持同时检查两份实际找到的文件，但不能代替对当前进程后端选择的运行时验证。

后续自定义调节应以被确认命中的处理路径为基础。若当前模式走另一套引擎，应追踪它实际接受的参数，而不沿缺少配套文件的 ClearShot 路径直接制作并宣称生效的控件。

## 13. 两份后端本体的分析结果

### 13.1 本次实际收到的文件

| 文件 | 大小 | 架构 | SHA-256 |
| --- | --- | --- | --- |
| `libmialgoengine.so` | 2,088,384 字节 | ELF64、AArch64 | `b13c9ebc974dd27ec79d704e322c3c9bb671f8a6e67b4587d41a6579348dfa3e` |
| `libmicampostproc_client.so` | 151,920 字节 | ELF64、AArch64 | `7c0455b74bed672096b5d53272ade0611a8935cbdf12d4d8d42865f7f4dd315c` |

两者均为去除完整调试符号后的库，但仍保留了足够的动态导出函数。已检查 ELF 依赖、导出接口、关键函数反汇编、插件路径和管线选择逻辑。

### 13.2 旧 JNI 的 V10 接口不能直接套用

对动态符号表的核对结果如下。

| JNI 寻找的符号 | 当前 `libmialgoengine.so` 是否定义导出 | 当前 `libmicampostproc_client.so` 是否定义导出 |
| --- | --- | --- |
| `MI_open_lib` | 否 | 否 |
| `MIAGetApiVersion` | 否 | 否 |
| `miOpenLib` | 否 | 是，`0x10aa4` |
| `GetExtInterafce` | 否 | 是，`0x10ab4` |
| `GetExtVersion` | 否 | 是，`0x10ac4` |

这份 MIA 引擎导出的主要是 `mialgo2::` 这一套 C++ 接口，例如 `MiaOfflineSession::initialize()`、`process()`、`MPluginModule`、`PipelinePruner`，以及 `getMiaOfflineSessionInstance()` 等。它与旧 JNI 的 V10 所期待的两个 C 接口并不相同。

需要准确区分两个结论：

- 当前文件自身没有定义导出上述 V10 符号，因此不能假设旧 JNI 的 V10 分支可以直接调用它。
- 这不等于相机整体无法工作。实际系统可能走 V11 客户端、HAL 或其他会话路径，还必须考虑加载句柄的依赖符号查找与进程实际加载情况。本轮未拿到运行时调用证据，不能据此断言某个分支必然已选中或已经崩溃。

后续实现不应修改路径，把新引擎强塞给旧接口，再将“能够加载文件”当作兼容成功。

### 13.3 客户端确认会连接厂商后处理服务

`libmicampostproc_client.so` 的 `DT_NEEDED` 包含 21 项，其中有：

```text
vendor.xiaomi.hardware.campostproc@1.0.so
libhidlbase.so
libhidltransport.so
```

`mialgo::MiPostProcServiceIntf::init()` 位于 `0x12690`，在 `0x12780` 调用了 `IMiPostProcService::tryGetService()`。库还具有 `MiPostProcSessionIntf::processFrame()`、`preProcessFrame()`、`createSession()`、回调和图像缓冲区封装等代码。

这证明客户端承担服务连接和帧／元数据交接职责。只在这份客户端中搜索降噪数学实现，并不能覆盖服务端实际执行的处理。该服务是否在用户当前拍摄时被使用，仍需要运行时记录。

### 13.4 已在原生客户端核对到请求标签的传递

`MiaFrameWrapper::mergeAppRequestSetting()` 位于 `0x11138`。它会读取应用请求中的厂商标签，然后通过 `setVTagValue()` 或 `updateVTagValue()` 合并到后续元数据中。

| 标签 | 已确认的含义或作用方向 |
| --- | --- |
| `xiaomi.hdr.enabled` | HDR 开关；本函数按布尔值规范化 |
| `xiaomi.hdr.raw.enabled` | RAW HDR 相关开关 |
| `xiaomi.mfnr.enabled` | 多帧降噪开关；本函数按布尔值规范化 |
| `xiaomi.depurple.enabled` | 去紫边相关开关 |
| `xiaomi.superResolution.enabled` | 超分辨率相关开关 |
| `xiaomi.capturefusion.isFusionOn` | 融合处理相关开关 |
| `xiaomi.hdr.sr.enabled` | HDR 与超分组合相关开关 |
| `xiaomi.multiframe.inputNum` | 多帧输入数量相关元数据 |
| `xiaomi.mivi.supernight.mode` | 超级夜景模式相关元数据 |
| `xiaomi.nightmotioncapture.mode` | 夜景运动捕捉相关元数据 |

本函数还处理翻转、人像灯效、连拍提示、图像名称等字段。上述证据进一步支持开发“拍摄策略与功能选择”的自定义入口，但并未暴露一个通用的“降噪强度 0—100”。多帧输入数量必须与实际图像缓冲区和采集策略保持一致，不能只改元数据制造额外输入帧。

实际是否执行 HDR、MFNR 或超分，还受模式、流配置、能力、场景和处理节点选择影响。读取或写回标签成功，仍不是最终算法已执行的充分证据。

### 13.5 MIA2 管线配置根目录已经确认

引擎的 `MiaOfflineSession::selectPipeline()` 位于 `0x1c7b40`。已在反汇编中核对到对不同 JSON 文件名的选择，以及拼接根目录：

```text
/odm/etc/camera/xiaomi/
```

这次不仅在字符串表看到路径，还在管线选择函数末段看到该目录参与路径构造，例如 `0x1ca578`、`0x1ca5ac` 等引用点。随后由 JSON 文件读取和解析代码处理管线描述。

| 在选择逻辑中出现的 JSON | 按名称可判断的用途方向 |
| --- | --- |
| `normalsnapshot.json`、`rearsinglesnapshot.json` | 普通／单摄照片管线 |
| `satsnapshot.json` | SAT 拍照管线 |
| `superhdsnapshot.json` | 超高像素照片管线 |
| `manualsnapshot.json` | 专业照片管线 |
| `manualrawsnapshot.json`、`manualultrarawsnapshot.json` | 专业 RAW 相关管线 |
| `rearsupernightsnapshot.json`、`frontsupernightsnapshot.json` | 前后摄夜景照片管线 |
| `normalvideo.json`、`rearsimplevideo.json` | 录像相关管线 |
| `highresolutionhdr10video.json`、`hdr10video.json` | 高分辨率／HDR10 录像相关管线 |

这些名称和选择分支说明引擎会区分多种处理管线。具体传感器、输出分辨率、相机应用模式编号与 JSON 的映射，仍需要配置内容和运行时信息核对。不能仅凭 `superhdsnapshot.json` 这一名字，保证用户的 2 亿像素模式使用了某个特定 HDR 或降噪节点。

### 13.6 算法插件位于独立目录

在 `MPluginModule` 的加载逻辑中，已核对到以下两个路径：

```text
/odm/lib64/camera/plugins/
/odm/lib64/camera/dynamicplugins/
```

具体证据包括：

- `getPluginWraperByPluginName()`（`0x140290`）在 `0x140744` 使用普通插件目录，在另一分支使用动态插件目录。
- `getPluginProvider()`（`0x142820`）构造插件路径，并在 `0x142930` 调用 `PluginManager::load()`。
- `MPluginModule` 构造过程还调用 `PluginManager::loadFromFolder()`。
- 引擎依赖 `libcom.xiaomi.pluginutils.so`、`libcom.xiaomi.metadatautils.so`、`libmetatagwrapper.so` 等厂商辅助库。

由此可见，当前引擎的会话、管线、节点、插件调度与真正的算法插件应分层分析。下一步先从 JSON 中确认具体插件名，再按目标功能选择需要分析的插件，能够减少收集无关库。

引擎另外包含 `/odm/lib64/libmialgoengine_custom.so` 路径，是可进一步调查的定制化辅助库线索。本轮尚未取得它，也未独立证明该路径在当前设备运行时被加载，因此按候选材料收集。

### 13.7 调试与资源属性不能当作画质强度

引擎中存在大量 `persist.vendor.camera.dsac.*mask`、调度、延迟、内存和调试属性，也引用了 `miaplugintrimconfig.json`、`miviprocesstimethreshold.json`。这些名称和出现位置首先反映任务分类、插件管理或处理时间等控制线索，不能直接解释成 HDR 强度、降噪强度或画质增强等级。

本轮没有执行任何 `setprop`、服务停止、SELinux 修改或相机库替换，也没有把这些属性生成所谓“画质拉满”配置。

### 13.8 当前可行性结论

| 目标 | 当前证据与建议 |
| --- | --- |
| HDR、MFNR、超分等拍摄策略选择 | APK 与客户端中均有入口，适合先做按模式、按镜头验证的参数面板 |
| 饱和度、对比度、色温、纹理与风格 | 仍可沿前文确认的厂商请求或渲染入口实现，需要同步验证成片 |
| 独立明度降噪、色度降噪强度 | ClearShot 兼容代码存在，但目标 ROM 没找到其配套；应从当前管线实际使用的插件重新确认 |
| 改善过度锐化、涂抹、HDR 鬼影 | 是合理优化目标；要先定位负责这些效果的实际插件，再用原图对比证明收益 |
| 重写融合、重建或神经网络算法 | 两份后端仍不足以完成，需具体算法插件／模型与进一步分析 |

## 14. 一次性配置与加载清单采集脚本

新增交付文件为 `Camera67_Collect_ReadOnly.sh`。它只读相机来源文件和进程信息，输出一个新的采集压缩包，不修改相机配置、属性、服务、SELinux 或系统库。

采集内容如下：

- `/odm/etc/camera/xiaomi/` 与对应 vendor 目录中的 JSON／XML 配置，保留原始文件路径。
- 可选的 `libmialgoengine_custom.so`，若存在则复制到采集包。
- 两个插件目录及对应 vendor 目录的文件名、大小和链接信息，暂不批量复制大型算法插件。
- 已提供的关键库在手机上的路径、链接与 SHA-256，避免重复上传相同本体。
- 相机、相机服务和相关后处理进程中 `.so` 的加载路径，采样约 20 秒。
- 设备型号、平台、架构和 SDK 等必要环境信息，以及缺失或读取失败记录。

脚本不读取照片内容。加载清单只能证明库被映射，不能单独证明某个处理函数已执行。

保存脚本到手机下载目录后执行：

```bash
su -c 'sh /sdcard/Download/Camera67_Collect_ReadOnly.sh'
```

出现开始采集提示后，在约 20 秒内切回相机，拍一张普通模式照片。脚本会在下载目录生成带时间与进程号的 `camera67_audit_*.tar.gz`，上传这个压缩包即可供下一轮核对配置与插件。

脚本已通过本地 `sh -n` 和 `bash -n` 语法检查，尚未在用户的 Android 手机上运行验证。若设备限制读取某些进程映射，失败会写入采集日志，其余配置仍可用于分析。

## 15. 设备采集包核对结果

### 15.1 采集内容与环境

本轮读取用户上传的 `camera67_audit_20261109_050644_23722.tar.gz`。压缩包共有 98 个成员，普通文件合计 1,526,813 字节。解包时检查了绝对路径、上级路径跳转和链接类型，未修改原始归档。

其中包含 79 份 JSON／JSONC 配置、479,040 字节的 `libmialgoengine_custom.so`、插件目录清单、关键库路径与哈希，以及相关进程的库加载记录。79 份配置全部完成解析，识别出 54 份管线描述。对带注释、前部旧示例和尾随逗号的文件进行了仅供分析的规范化，原文件保持不变。

设备回传信息为：

| 项目 | 值 |
| --- | --- |
| 设备代号 | `songyuan` |
| 型号字符串 | `M098FE` |
| 平台 | `canoe` |
| 硬件厂商标识 | `qcom` |
| SoC 字符串 | `SM8850` |
| 架构 | `aarch64` |
| SDK | `37` |

后续以这些实测标识适配，不根据相机移植包的名称或配置注释猜测市场型号。`overridesettings.json` 头部的 `device:ishtar` 是注释，不能覆盖实际设备标识；`manualsnapshot.json` 前部还有整段注释掉的旧管线，也未计入有效节点。

### 15.2 实际库加载位置已经缩小到 Provider 侧

| 采样进程 | PID | 与本轮调查有关的观察 |
| --- | --- | --- |
| `com.android.camera` | 1622 | 相机 APP 的加载清单；未列出旧 JNI 与 postproc client |
| `vendor.qti.camera.provider-service_64` | 2415 | 加载 MIA2 引擎、定制库、目标插件与相关算法库 |
| `cameraserver` | 3156 | 本轮未列出上述旧 JNI 与 postproc client |
| `com.xiaomi.cameramind` | 8609 | 本轮未列出上述旧 JNI 与 postproc client |

采集脚本自身的 PID 23722 因命令行含有 camera 名称也被收录，不把它当作相机算法进程。

Provider 的清单明确包含：

```text
/odm/lib64/libmialgoengine.so
/odm/lib64/libmialgoengine_custom.so
/odm/lib64/libmialgo_aisp.so
/odm/lib64/libaispalgoprocessor.so
/odm/lib64/libarc_aisp.so
```

此前用户上传的四份 JNI／引擎／客户端文件，均与手机上对应路径的 SHA-256 一致。`/vendor/lib64/libmialgoengine.so` 在本次 root 检查中明确返回不存在，实际找到并加载的是 ODM 版本。

这个结果比单纯从字符串推测路径更强：当前调参调查的重点应落在 Provider 中的 MIA2 与插件，以及送入该侧的请求元数据。APP 里的 LSPosed Java hook 可以修改它能控制的请求或风格参数，但若要修改另一个进程里的原生算法参数，需要针对那个进程设计对应方案。

仍要保留证据边界：加载记录能证明库进入了该进程，不能证明每次按快门都调用了其中所有算法；未在本轮采样中看到某个库，也不能证明所有模式永远不用它。

### 15.3 关键插件已对应到真实文件路径

| 配置中的插件名 | Provider 加载清单中的路径 | 本轮配置中引用它的管线数 |
| --- | --- | --- |
| `com.xiaomi.plugin.mialgoallinone` | `/odm/lib64/camera/dynamicplugins/com.xiaomi.plugin.mialgoallinone.so` | 11 |
| `com.xiaomi.plugin.offcammfnr` | `/odm/lib64/camera/preloadplugins/com.xiaomi.plugin.offcammfnr.so` | 12 |
| `com.xiaomi.plugin.offlinemfnr` | `/odm/lib64/camera/preloadplugins/com.xiaomi.plugin.offlinemfnr.so` | 9 |
| `com.xiaomi.plugin.quality` | `/odm/lib64/camera/plugins/com.xiaomi.plugin.quality.so` | 6 |
| `com.xiaomi.plugin.misrdehaze` | `/odm/lib64/camera/dynamicplugins/com.xiaomi.plugin.misrdehaze.so` | 1 |
| `com.xiaomi.plugin.sdsr` | `/odm/lib64/camera/dynamicplugins/com.xiaomi.plugin.sdsr.so` | 1 |
| `com.xiaomi.plugin.filter` | `/odm/lib64/camera/plugins/com.xiaomi.plugin.filter.so` | 16 |

管线数仅是本次 54 份描述中的静态引用统计，不是实际命中次数。其中 `preloadplugins` 是本轮加载清单揭示的关键补充目录。早期采集脚本没有单独列出这个目录，但进程清单记录了其完整路径，因此无需再猜测 MFNR 包装插件是否以同名文件存在。

不要仅凭 `quality` 这一名称把它当作锐化或成片增强模块。实际配置把它放在预选帧相关子管线，具体算法含义仍需插件本体证据。

### 15.4 各模式的管线差异

| 配置文件 | 有效节点／连接数 | 与调参相关的已见节点 |
| --- | --- | --- |
| `normalsnapshot.json` | 22／29 | offcam MFNR、Bayer 转 YUV、滤镜、Gainmap 等 |
| `satsnapshot.json` | 54／74 | offline MFNR、All-in-One、融合、SR Dehaze、SDSR、滤镜等候选分支 |
| `superhdsnapshot.json` | 43／59 | offcam MFNR、两个 All-in-One 实例、滤镜等 |
| `manualsnapshot.json` | 19／27 | offline MFNR、Bayer 转 YUV、去紫边、滤镜、Gainmap 与编码 |
| `manualrawsnapshot.json` | 8／11 | RAW 相关处理及伴随成片处理分支 |
| `manualultrarawsnapshot.json` | 17／23 | 专业 UltraRAW 相关分支及伴随成片处理 |
| `rearsimplevideo.json` | 3／3 | memcpy、预览美颜、ASD，未定义照片的 FilterInstance0 |

以上都是可被进一步选择、裁剪和旁路的图描述，不能把图内全部节点解释为同一张照片必定依次执行。

`superhdsnapshot.json` 的 All-in-One 实例还有 `maxProcessTime = 40000` 这一处理时间限制字段。它不是曝光时间，也不能解释为提高画质的强度。`NodeMask` 是节点行为位掩码，`NodeConcurrencyThreadLimit` 是并发相关参数，都不能当成锐化／降噪强度。

普通、SAT、高像素和专业照片配置都具有 `com.xiaomi.plugin.filter` 节点及连接。高像素配置的 FilterInstance0 位于翻转之后、水印之前；专业照片中位于 LDC 之后、水印之前。这能帮助继续排查预览与成片参数同步，但节点存在不等于当前模式已正确接收自定义滤镜脚本。

录像要单独判断：`rearsimplevideo.json` 没有照片滤镜节点，而 `rearmagicwandvideo.json`、`cinelook.json` 出现 `com.xiaomi.plugin.videofilter`。不能用普通照片管线替代录像路径验证。RAW 配置里的成片滤镜分支，也不代表 RAW 像素本体被施加了滤镜。

### 15.5 两亿级模式确有配置项

`aispsensormodesettings.json` 的 PhysicalId 1 包含：

```text
aispSensorMode = 20
imageWidthList 中的对应宽度 = 16320
imageHeightList 中的对应高度 = 12288
```

像素乘积为 200,540,160，属于约 2 亿级的配置尺寸。它为高像素路径调查提供了具体依据，但仍不是运行时输出分辨率、所有镜头支持情况或高像素 HDR／降噪已生效的证明。

### 15.6 配置中可研究的采集策略值

以下数值来自有效配置内容，不是本次照片的实测帧数，也不保证每个模式或镜头都会使用。

| 文件与配置路径 | 当前值 | 可研究方向 |
| --- | --- | --- |
| `overridesettings.json` → `FeatureList.FeatureSR.NumOfSnapshotRequiredBySR` | 8 | SR 多帧采集策略 |
| 同文件 → `FeatureSR.NumOfSnapshotRequiredByRemosaicSR` | 4 | Remosaic SR 策略 |
| 同文件 → `FeatureSR.NumOfSnapshotRequiredByQUADBayerSR` | 6 | Quad Bayer SR 策略 |
| 同文件 → `FeatureSRHDR.NumOfSnapshotRequiredBySRHDR` | 10 | SR 与 HDR 组合策略 |
| 同文件 → `FeatureSRHDR.DefaultExpValuesOfSRHDR` | 八个 0、-6、6 | 多曝光序列候选；其单位需结合消费者确认，不能直接按 EV 解释 |
| 同文件 → `FeatureAINR.NumOfSnapshotRequiredByAINR` | 6 | AINR 采集策略 |
| 同文件 → `FeatureHD.NumOfSnapshotRequiredByRemosaicHD` | 5 | 高像素 Remosaic 策略 |
| 同文件 → `FeatureHD.MfnrMaxExpTime` | 250,000,000 ns | 注释描述为高像素 MFNR 允许的最大曝光时间，约 0.25 秒 |
| 同文件 → `FeatureHDR.MinNumOfSnapshotRequiredByYuvHDR` | 3 | YUV HDR 最低输入要求，不能当成强度 |
| 同文件 → `FeatureHDR.MinNumOfSnapshotRequiredByRawHDR` | 2 | RAW HDR 最低输入要求，不能当成强度 |

这为制作“原厂策略／静物优先／运动优先”等可调策略提供了实际候选配置。修改前还应确认消费者、覆盖顺序、请求与实际缓冲区数量；不能仅把数字统一加大就宣称优化。

`miviphotographerconfig.json` 的 `MaxMFNRCount = [3,3]` 按文件注释是 MFNR 并行任务数，不是单张照片只合成 3 帧。相同文件还包含任务压力下的策略切换及高温处理设置，这些机制不应被混同成图像降噪强度滑杆。

### 15.7 定制库中的动态路由得到进一步核对

本轮取得的 `libmialgoengine_custom.so` 为 AArch64，SHA-256：

```text
dd28377e58d21dc14a46e7c7eebb7c7e4eb7b0308f7e8541c032284ef1519ed7
```

Provider 的加载清单确认该文件已映射。其 `GetInstance()` 位于 `0x69e58`，主要定制类为 `QcomPrunerCustomization`。

`decideFeaturePipeline()` 位于 `0x6786c`，本轮反汇编确认其读取：

- `com.xiaomi.mivi2.preAnchorProc`
- `xiaomi.mfnr.enabled`
- `xiaomi.ai.asd.SmartAE`
- `xiaomi.snapshot.EHDREnable`
- 存储等其他状态。

`lookForDisableNodesForPreAnchorProc()` 位于 `0x2c5fc`，也读取预处理与融合相关状态，决定节点是否启用。可见最终图并非只由 JSON 文件名决定。不能随意伪造 SmartAE 结构或删除图中的“看起来多余”节点。

## 16. 基于当前设备材料的实施判断

### 16.1 可以先开发的功能

**APP／请求层面**可以制作独立参数面板，沿前文已确认的入口覆盖锐化、纹理、色彩与 HDR／MFNR 策略。应按镜头和模式保存设置，以原厂值为默认，并记录设备是否支持、请求是否写入以及是否有真实成片变化。

**系统调参层面**可以研究对已确认读取的配置进行可恢复覆盖，或对 Provider 中真正命中的处理入口调参。它与 APP 内的 Java 渲染 hook 不是同一个作用范围。配置策略调节可能改变拍摄等待、输入帧数和场景选择，需要分别核对普通、高像素、专业与录像。

可以把第一版验证范围收敛为：

| 设置组 | 实施目标 | 当前限制 |
| --- | --- | --- |
| 原厂基准 | 不覆盖原厂值，能够恢复，记录当前链路 | 必须保留真实基准，不能只比较两组都被修改的图 |
| 自然细节 | 减少额外加锐，单独测试厂商锐化和纹理入口 | 已被早期 ISP 处理损失的细节无法靠后期恢复 |
| 静物细节 | 研究持稳场景的多帧／SR／HDR 策略 | 不能只增大输入数量；需核对请求、缓冲区、耗时与鬼影 |
| 运动拍摄 | 保留原厂运动与场景判断，评估成功率 | 不应把静物长流程无差别强制用于人物和运动物体 |

这些是待实现和验证的功能范围，不是已经证明改善画质的预设。当前未安装调参模块，也未对手机配置或库做任何修改。

### 16.2 上一轮定位的三个插件（本轮已取得）

截至该轮，资料没有给出当前活动算法中可直接开放的“明度降噪强度／色度降噪强度／锐化半径”的合法取值范围，因此定位了三个同时满足“实际管线引用”和“Provider 加载记录”的包装插件；本轮已取得并分析，结果见第 17 节：

```text
/odm/lib64/camera/dynamicplugins/com.xiaomi.plugin.mialgoallinone.so
/odm/lib64/camera/preloadplugins/com.xiaomi.plugin.offcammfnr.so
/odm/lib64/camera/preloadplugins/com.xiaomi.plugin.offlinemfnr.so
```

它们可能继续调用独立算法本体。本轮加载清单已经列出 `libmialgo_aisp.so`、`libaispalgoprocessor.so`、`libarc_aisp.so` 等候选，但不能只凭名字判定各自负责的具体数学处理。先读取包装插件的依赖、实际参数结构和配置路径，再决定是否需要其中的算法本体。

这三份文件已由用户通过 `camera67_target_plugins.tar.gz` 提供，不需要重复采集。下一层依赖已依据实际调用收敛，见第 17.8 节。

## 17. 三份目标插件：参数消费者、实际后端与开发边界

本轮材料：`camera67_target_plugins.tar.gz`。已检查归档成员的路径、类型和大小后解包，仅做静态解析，没有执行上传的原生库。三份均为 ELF64 AArch64；解压 `.gnu_debugdata` 补充本地函数名，并结合动态符号、PLT、反汇编和上一轮 Provider 加载记录交叉核对。

### 17.1 文件核对

以下路径均相对于 `/odm/lib64/camera/`。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `dynamicplugins/com.xiaomi.plugin.mialgoallinone.so` | 533,424 | `80ccafb794a334a40fe0b4bec31aebfd7981e9d0af524e2184c1e8016c66e29e` |
| `preloadplugins/com.xiaomi.plugin.offcammfnr.so` | 435,104 | `eb3dac68fed0a319c77483b4d255a5c4b140609643b2a69cf4536f3d90d37ae8` |
| `preloadplugins/com.xiaomi.plugin.offlinemfnr.so` | 435,024 | `dac0df7e27cac62807a7711b9bfa2619badbd2c13a1bff3af057384f9502ab93` |

它们与上一轮加载记录的路径相符。加载记录本身不含这三份文件的来源哈希核对，不能把“同一路径”表述为已经完成逐文件在机一致性验证。

### 17.2 已确认的后端调用

| 插件 | 本轮指令级证据 | 判断 |
| --- | --- | --- |
| All-in-One | `initialize()` 位于 `0x27bc4`；`0x2810c` 调用 `AispAlgoProcessor::aispAlgoCreate()` | 创建 AISP 处理对象 |
| All-in-One | `0x34008` 调用 `aispAlgoInit()`；`0x34f14` 调用 `aispAlgoStart()`；`0x35610` 调用 `aispAlgoAddFrame()`；`0x36244` 调用 `aispAlgoRun()` | 处理状态和帧数据继续传给外部处理器；不能在包装层直接认定降噪数学实现已全部还原 |
| offcam MFNR | `HWPostProcIntf` 构造函数位于 `0x30594`；`0x305b8` 调用 `dlopen("libcom.xiaomi.offcamadapter.so", ...)`；`0x305cc` 解析 `GetOffCamAdapterIntf`，随后调用返回接口 | 走 OffCam 适配接口，后续处理包含虚函数调用 |
| offline MFNR | `HWPostProcIntf` 构造函数位于 `0x4bea0`；`0x4becc` 加载 `libcom.xiaomi.offlinefeatureintf.so` | 走另一套离线处理接口，不能套用 offcam 的对象布局 |
| offline MFNR | 解析 `CameraPostProc_Create`、`PreProcess`、`Process`、`Flush`、`Reset`、`ReleaseResources`、`Destroy`（均有 `CameraPostProc_` 前缀） | 会话、缓冲区、任务与结果交由该接口进一步处理 |

All-in-One 的 21 项 `DT_NEEDED` 中明确包含 `libaispalgoprocessor.so` 与 `libmialgo_aisp.so`。两套 MFNR 各有 19 项直接依赖，包含 `libpostprocinfo.so`、`libmicamera_hal_core.so` 等；上表中的两个动态加载接口库则由 `dlopen` 取得，不能只看 `DT_NEEDED` 就漏掉。

上一轮 Provider 清单已列出以下实际路径：

```text
/odm/lib64/libaispalgoprocessor.so
/odm/lib64/libmialgo_aisp.so
/odm/lib64/libcom.xiaomi.offcamadapter.so
/odm/lib64/libcom.xiaomi.offlinefeatureintf.so
/odm/lib64/libmetadataHelper.so
```

这是对“包装层下一站在哪里”的确认，尚不是每次拍照的函数命中记录。

### 17.3 MFNR 的内部值不能全部按布尔量处理

APP 层前文已确认的 `n9.d0.P(int, boolean)` 仍是布尔配置接口，旧 postproc client 也有布尔归一化逻辑。**本轮实际 Provider 插件展示了不同的内部消费方式，不能把这几层的类型语义混用。**

- offcam 的 `OfflineMfnr::needEnable()` 位于 `0x22de4`，offline 版本位于 `0x22ea8`。两者均读取 `xiaomi.mfnr.enabled`，还检查 SmartAE、HDR、融合、人像／Remosaic 等相关状态及实例信息。
- offcam 的 `overrideInputBufferNum()` 在 `0x263bc` 把读到的单字节与 **2** 比较；offline 版本在 `0x28a6c` 也比较 **2**。
- 因而 Provider 内部存在针对值 2 的特殊分支。不能再用“所有消费者只会区分 0 与 1”描述该标签。

这并不构成向 APP 强行发送 2 的依据。值 2 由哪一层产生、对应哪些会话和输入帧准备，尚未完整确认。新模块应分别记录 APP 配置、送入 Provider 的实际元数据、插件选择与最终结果，不能把开启状态误显示为算法已执行。

### 17.4 已找到帧数覆盖逻辑，而非任意可设帧数

这两个样本的 `OfflineMfnr::validateInputNum(int)`：

| 插件 | 函数地址 | 返回条件 |
| --- | --- | --- |
| offcam MFNR | `0x2702c` | `inputNum > 2` |
| offline MFNR | `0x29684` | `inputNum > 2` |

这是这两个函数的条件，不是所有拍照算法的统一最小帧数，也没有给出全部合法上限。

更关键的是它们读取／更新的是 **`xiaomi.multiframe.inputNum`**。前文 APP 可请求的 **`xiaomi.mfnr.frameNum`** 是另一名称，不能假设两个值在所有中间环节始终一致。

**offcam 分支：** `overrideInputBufferNum()` 位于 `0x26340`。当读到的 MFNR 字节为 2、内部模式字段为 `0x8005`、节点名为 `MfnrInstance0`，且原元数据输入数量至少为 5 时，该分支把数量参数设为 **5**，并写回 `xiaomi.multiframe.inputNum`。本轮没有把 `0x8005` 擅自映射成 APP 模式 ID。

**offline 分支：** 对应函数位于 `0x287c4`。在上述类似条件下，它还读取 `AECFrameControl` 中的两个 float；日志将其分别标记为 `shortGain` 与 `adrc_gain`。满足增益阈值、阈值上下界有效且原数量至少为 8 时，数量设为 **8**，否则设为 **5**。该段日志标记为前摄快照处理；不能外推为后摄普通／两亿像素的普遍规则。

其阈值在库的全局初始化中通过属性读取：

| 属性 | 代码缺省值 | 用途边界 |
| --- | ---: | --- |
| `persist.vendor.algoengine.mfnr.minshortgain` | 8 | 上述特定分支的短帧增益下界 |
| `persist.vendor.algoengine.mfnr.maxshortgain` | 256 | 短帧增益上界 |
| `persist.vendor.algoengine.mfnr.minadrcgain` | 0 | ADRC 增益下界 |
| `persist.vendor.algoengine.mfnr.maxadrcgain` | 3 | ADRC 增益上界 |

这里的数字是**属性缺失时的代码默认值**，不是手机当前属性实测值，也不是这些属性允许随意取值的范围。它们控制特定条件下的数量选择，不是明度／色度降噪强度。以上 5／8 也是代码中的数量覆盖结果，尚未经过本次实际照片的缓冲区／融合帧数验证。

实施含义：MFNR 调节应检查原始采集帧数、到达插件的有效缓冲区、元数据数量和最终采用数量之间是否一致。只改变数字不会凭空生成曝光帧，更不能把不满足输入要求的任务强制送入该节点。

### 17.5 Tuning 和元数据仍有下一层消费者

All-in-One 的 `metahelper::MetaHelperClient::Load()` 位于 `0x54504`。在 `0x54554` 明确加载 `/odm/lib64/libmetadataHelper.so`，于 `0x5456c` 解析 `GetInstance`；`setMetaInfo()` 中大量字段通过该接口的虚函数读取或更新。

两套 MFNR 的 `updateInputMatadata()`（原符号拼写如此）读取 `org.quic.camera2.tuning.mode.TuningMode`，处理物理与逻辑元数据中的 tuning 选择。该结构包含场景／特征选择信息，不应把任一整数项直接命名为“降噪强度”。

它们也读取 `/odm/etc/camera/xiaomi/chiofflinesetting.json`。上一轮已经采集到该文件，不必再要一份。本机有效内容为 `UltraHdr` 的直方图、曝光目标、ADRC／lux 等配置。本轮核对到 `getDataFromJsonFile()`、`getUltraHdrConfigInfoFromJsonData()` 的消费者关系；这些属于 UltraHDR／Gainmap 相关候选，不等于独立的传感器降噪或锐化控件。具体数值编码、镜头条件和是否实际应用仍需进一步核对。

### 17.6 已识别但不能算作优化的属性

All-in-One 在全局初始化函数中读取：

```text
persist.vendor.camera.capture.bypass.AllinOneAlgo
persist.vendor.camera.algoengine.AllinOne.dump
persist.vendor.camera.algoengine.AllinOne.debug
vendor.camera.algosim.algoType
vendor.camera.algosim.algoIO
```

两套 MFNR 同样有 `persist.vendor.algoengine.bypass.mfnr`。这些名称与读取点为旁路／调试／仿真调查提供线索，不是“画质全开”开关。旁路还可能绕过原有处理，不能预设画质更好。

这些读取发生在库的初始化代码中，并缓存到各自全局变量；不能承诺在设置页修改某个属性后，已加载的库立即重新读取。本轮未改动任何系统属性或重启相机服务。

### 17.7 当前能做到的自定义范围

| 用户目标 | 当前证据状态 | 合适的开发方式 |
| --- | --- | --- |
| 减少额外加锐、调整纹理和色彩 | APP 入口与映射已确认，见第 3、4 节 | 优先做每镜头／模式的参数面板，以原厂值为默认，单变量拍摄验证 |
| HDR／MFNR 策略选择 | APP 入口、Provider 消费者与条件判断已见 | 显示真实支持情况，并记录中间覆盖；保留原场景与运动判断 |
| MFNR／SR 输入数量实验 | 配置候选与 MFNR 覆盖逻辑已有证据 | 作为受限实验项，验证采集、缓冲区、耗时和鬼影，不开放无约束整数 |
| 明度／色度降噪分别调节 | 当前活动链的有效强度入口／合法范围仍未确定 | 继续核对 AISP 和离线接口的实际参数消费者 |
| 锐化半径、阈值、边缘保护分别调节 | 尚未找到对应的已验证结构与范围 | 不能把风格锐化或 debug 开关包装成这些功能 |
| 修改 AI 模型／去马赛克实现 | 包装插件不包含足够实现证据 | 需要算法本体、相关 tuning／模型与效果验证 |

本轮已经把“可做策略和已有参数自定义”与“算法内部强度尚待确认”进一步分清。未生成可安装调参模块、未修改原始 APK／设备库、未拍摄 A/B 样张，因此没有“已改善锐化或降噪”的实测结论。

### 17.8 上轮定位的五份文件（本轮已取得）

本次不再按库名猜测索取全部依赖。优先取得已由实际调用和 Provider 映射共同定位的五份文件：

| 文件，均在 `/odm/lib64/` | 需要核对的内容 |
| --- | --- |
| `libaispalgoprocessor.so` | `AllinOnePrivData` 进入算法前如何转换；实际调用的算法接口与参数 |
| `libmialgo_aisp.so` | AISP 本体的导出、参数消费者、tuning／模型入口 |
| `libmetadataHelper.so` | 当前虚函数槽位对应的真实元数据语义及转换，避免伪造未知结构 |
| `libcom.xiaomi.offcamadapter.so` | `GetOffCamAdapterIntf` 的处理实现与后续消费者 |
| `libcom.xiaomi.offlinefeatureintf.so` | `CameraPostProc_*` 的参数接收、离线硬件／软件处理分发 |

五份文件现已由本轮归档提供，后续结果见第 18 节，无需重复采集。

## 18. 五份底层库：AISP 参数语义与高通离线通路

本轮收到 `camera67_algorithm_backends.tar.gz`，已取得上一轮指定的五个文件。全部为 ELF64 AArch64。完成了直接／动态依赖检查、关键函数反汇编、字符串引用与调用关系索引，以及元数据虚函数表的重定位解析。仅做静态分析，没有运行这些原生库或修改手机。

### 18.1 文件指纹

以下文件均来自本轮归档，目标位置为 `/odm/lib64/`。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `libaispalgoprocessor.so` | 598,352 | `8d1df0a34f22c4fba2ff74a23975487e5a1d6fe0d1a3c30c3c0f37deee5504a0` |
| `libmialgo_aisp.so` | 2,726,360 | `dd6feb00c44d106265ff3cb7694e502fcf987e7d5822aa6ecf1b5797686a92aa` |
| `libmetadataHelper.so` | 330,720 | `d8b6c18c18ac63bfb5c82d7a08bf77b2bcacc76cd4da5c351a34246021c61418` |
| `libcom.xiaomi.offcamadapter.so` | 152,656 | `a0efe7d4c18fe1495c370bf00650feec0751e0fe58af70fe78e1c1a2e2b174c9` |
| `libcom.xiaomi.offlinefeatureintf.so` | 367,376 | `3cc53011ad3488dbb7f87d29f1c4a9722c4069adaca0e917a19f198379f7723b` |

下文的虚函数偏移、函数地址与对象布局只对应这些具体文件，不能直接用于其他 ROM 或相机版本。

### 18.2 三条通路已进一步明确

| 上层插件 | 本轮确认的处理通路 | 对调参的含义 |
| --- | --- | --- |
| `mialgoallinone` | 插件 → `AispAlgoProcessor` → `AIsp*` SDK → 由框架选择算法后端；包含 ArcAIsp 和动态 Mialgo 后端接口 | 可以观察／研究 SDK 输入与算法选择；细节强度不能仅凭包装层名称推定 |
| `offcammfnr` | `libcom.xiaomi.offcamadapter.so` → `/odm/lib64/hw/com.qti.chi.offline.so` 的 `ChiOfflineOpenContext` → 离线会话与请求执行 | 已进入高通离线处理接口；不能把它当作一段可用通用 0—100 强度替换的独立 C 函数 |
| `offlinemfnr` | `libcom.xiaomi.offlinefeatureintf.so` → `ChiOfflineFeatureManager` → 对应 CHI Feature2 实现 | 按特征类型创建不同实现，需要继续遵循会话、流、元数据和输入依赖 |

offcam 适配库的初始化代码在 **`0x111d0`** 加载 `/odm/lib64/hw/com.qti.chi.offline.so`，于 **`0x111f4`** 解析 `ChiOfflineOpenContext`。会话实现随后通过取得的接口执行配置与请求。这份高通库也出现在上一轮 Provider 映射中。

offline 接口的 `ChiOfflineFeatureManager::CreateFeature2()` 位于 **`0x35590`**，确认存在以下创建调用：

| 调用位置 | 被调用的创建入口 | 当前直接依赖中的对应文件 |
| --- | --- | --- |
| `0x3569c` | `ChiFeature2Generic::Create` | `com.qti.feature2.generic.so` |
| `0x35610` | `ChiFeature2Raw2YUVHDR::Create` | `com.qti.feature2.raw2yuvhdr.so` |
| `0x35674` | `ChiFeature2EnhancedHDR::Create` | `com.qti.feature2.enhancedhdr.so` |
| `0x35788` | `ChiFeature2Statsregeneration::Create` | `com.qti.feature2.statsregeneration.so` |
| `0x357e8` | `ChiFeature2HWmultiframe::Create` | `com.qti.feature2.mfsr.so` |

这些文件都在上一轮 Provider 的映射清单中。它们是可选择的实现，不能理解成每张照片必定依次执行五个算法。

### 18.3 AISP SDK 的入口已经核对到实际调用

`libaispalgoprocessor.so` 有 17 项直接依赖，其中包含 `libmialgo_aisp.so`。处理器的调用与 SDK 导出可以一一对应：

| 处理器中的调用位置 | `libmialgo_aisp.so` 接口 | SDK 入口地址 |
| --- | --- | --- |
| `0x25e08` | `AIspCreate` | `0xa7fb8` |
| `0x276f8` | `AIspInit` | `0xa817c` |
| `0x2c708` | `AIspStart` | `0xa825c` |
| `0x39bc0` | `AIspAddFrame` | `0xa83a4` |
| `0x4be04` | `AIspRun` | `0xa8498` |
| `0x4b914` | `AIspSetDepthParam` | `0xa88f0` |

这比仅看到导出名称更具体：可以把初始化、启动参数、逐帧输入和结果执行分别作为观察点。仍须通过真机调用记录确认目标模式实际经过哪些入口。

处理器还包含 `AIspInitParam`／`AIspStartParam` 的 JSON 序列化代码，便于识别结构体字段的语义。已见字段包括：

| 结构 | 可确认的字段示例 | 正确解释 |
| --- | --- | --- |
| `AIspInitParam` | `is_anchor_select`、`force_algo`、`exp_targets`、`sensor_type`、`lux_index`、`on_tripod` | 算法选择、曝光／场景与持稳条件；不能任意伪造为所有场景的“最高画质” |
| `AIspStartParam` | `frame_num`、宽高／stride／位深、`sensor_mode`、`ui_ev`、`input_mode` | 输入帧、格式、传感器模式与曝光相关信息；需与真实输入匹配 |
| 同上 | `bps_gamma_table`、`ipe_gamma_table`、`gtm_table`、`y_hist_info` | 传入的曲线／统计信息；其存在不等于可安全替换成任意用户曲线 |
| 同上 | `zoom_info`、`face_info`、`assign_anchor`、`sdsr_flag`、`flash_mode`、`live_photo` | 变焦、人物、选帧与模式条件；不同拍摄路径必须分别验证 |

SDK 序列化还出现 `rgb_dehaze_saturation_adjust` 等去雾色彩字段。当前没有确认它在所有模式的合法范围、实际消费者与成片变化，因此暂不把它作为通用饱和度或降噪控件。

### 18.4 两个名称容易被误读的入口已澄清

**`AIspSetParam` 不能据名称称为通用画质滑杆接口。**

该导出位于 `0xa89bc`，在 `0xa8a14` 转到内部 `0xbaa50`。本轮追踪的内部代码使用 `AISP_DEPTH` 标识，调用 `0xd9968`，后者具有 `DepthAddFrame` 标识并属于 `aisp_algo_depth.cpp`。其参数序列化含 `total_frame`、`frame_type`、`slave_img`、位深、增益与帧时间等字段。

因此，本样本的这个入口进入深度处理相关分支，尚不是已证实能接收“明度降噪／色度降噪／锐化半径”的通用设置器。处理器当前可见的直接调用列表中也没有 `AIspSetParam`；它明确调用的是另一导出 `AIspSetDepthParam`。二者不应混为一个函数。

**`clarity` 是选帧相关结构中的字段，不能直接当作输出锐化强度。**

`libmialgo_aisp.so` 的内部序列化函数 `0xc5a4c` 将它与 `anchor_index`、`ambiguity`、`is_final_anchor`、EV 帧索引等一起序列化；该函数由 Arc／Mialgo 的 `AlgoSelectAnchor` 路径调用。结合这些消费者，它属于选帧相关数据，而非已经确认的用户加锐入口。不能把这个名字转换成“清晰度 0—100”设置。

这两项说明参数的名称必须与调用方向、结构体和消费者一起判断。仅搜索到 `SetParam`、`clarity` 或 `TuningMode`，不足以证明找到了用户可调的图像强度。

### 18.5 元数据虚函数的语义得到还原

本轮解析 `libmetadataHelper.so` 的 Android 打包重定位，再结合虚函数表、定义符号与函数体，得到当前 Qcom 实例的部分映射：
| Qcom 虚函数表的字节偏移 | 具体方法 | 函数地址 |
| --- | --- | --- |
| `0x20` | `GetSmartAeInfo` | `0x19f64` |
| `0x58` | `GetEHDREnable` | `0x1b8f8` |
| `0x1b8` | `SetIspGain` | `0x42734` |
| `0x200` | `GetTuningSensorMode` | `0x3cfe0` |
| `0x2f0` | `SetSnapshotReqInfo` | `0x40b10` |
| `0x450` | `GetTuningMode` | `0x45a20` |

这些偏移以本文件的 Qcom 虚函数地址点为基准。不是跨版本 ABI，也不是可直接向任意对象写入的内存偏移。

其中，上一轮 All-in-One `setMetaInfo()` 里 `0x49f80` 的间接调用使用 `0x2f0` 槽位，现可对应到 **`SetSnapshotReqInfo`**。该 helper 通过标签索引查找、更新 `xiaomi.ai.asd.SnapshotReqInfo`，可见写回的是 **100 字节**结构；`GetSnapshotReqInfo()` 位于 `0x40208`，也逐项读取这一结构。

因此，上一轮日志中的“sat denoise mode”涉及快照请求结构的更新，不应把整个结构替换成一个整数或未经验证的独立降噪强度。现有证据尚未完成该结构全部字段的枚举含义与边界还原。

### 18.6 SDK 仍包含外部后端选择

`libmialgo_aisp.so` 的 5 项 `DT_NEEDED` 主要是运行时基础库，不能据此认定所有核心融合算法都静态包含在这个文件中。其代码还存在动态加载：

- Arc 分支的加载器位于 `0xcf5b0`，解析 `ArcAIspInit`、`ArcAIspStart`、`ArcAIspAddFrame`、`ArcAIspRun`、`ArcAIspSelectAnchor` 等真实入口。对应库名 `libarc_aisp.so` 由 `0xd13d8` 的初始化代码构造。
- 另一加载器位于 `0xdfb58`，解析 `MialgoInit`、`MialgoAddFrame`、`MialgoRun`、`MialgoUnit` 等入口，库路径由其对象／配置传入。本轮没有擅自给所有这类分支指定同一个算法库名。
- 深度支路另有 `MialgoCaptureDepth*` 接口，与普通降噪强度应分开分析。

上一轮 Provider 映射包含 `/odm/lib64/libarc_aisp.so`。这确认存在可继续追踪的在机后端，但加载并不证明每次拍照选择它。

SDK 引擎初始化时尝试读取 **`/odm/etc/camera/aisp.json`**：构造函数在 `0xb4820` 取得该路径，于 `0xb4850` 调用内部配置加载函数 `0xb4994`。已见配置读取涉及 `aisp`、`algo`、`lib_fixed`、旁路、dump、日志和保护等选项。

该路径位于 `/odm/etc/camera/`，与此前采集的 `/odm/etc/camera/xiaomi/` 不同。现有归档尚未提供它，不能声称手机上该文件已经存在或已知其中的实际参数。即使取得，也应先分清调度／调试配置与算法本体 tuning。

### 18.7 可落地的第一版范围与验证顺序

目前已经足以形成第一版调参模块的明确范围，后续开发可从 APP 的已知入口推进，不必等到还原每个算法实现：

| 优先级 | 可做的功能 | 必须保留的真实含义 |
| --- | --- | --- |
| 高 | 每镜头、每模式保存原厂锐化级别和纹理覆盖值 | 读取设备范围，区分 ISP／厂商纹理与额外风格加锐 |
| 高 | 额外锐化、对比度、饱和度、色温、色调、柔光等 | 沿原 APP 映射同步预览与最终成片，属于已知风格／请求参数 |
| 高 | 原厂值与自定义值切换、恢复原厂、单变量对照 | 能够保留真正未覆盖的对照组 |
| 中 | HDR／MFNR 策略与按模式支持提示 | APP 请求值、Provider 策略和最终执行状态分别记录 |
| 实验 | 设备接受的多帧数量和静物策略 | 遵循第 17 节的输入校验、数量覆盖和缓冲区约束 |
| 暂不开放 | 独立明度／色度降噪、锐化半径／边缘阈值 | 当前活动链仍缺有效强度字段、合法范围与实拍证据 |

建议先核对“减少额外加锐”的自然细节方案，再单独测试原有纹理／锐化级别，最后研究多帧策略。每一步都应比较最终原图的细纹、白边、噪声、鬼影与耗时，避免把风格变化或等待变长当作细节提升。

普通、高像素、专业、RAW 伴随 JPEG 和录像仍需分别适配。不能把照片多帧输入数量设置用于录像，也不能用某一路径调用成功替代全部模式验证。APP Java 模块对 `com.android.camera` 中已有请求入口的覆盖，与 Provider 原生进程中的参数覆盖属于不同工作。

截至本轮：**已经确认可以做已有参数与拍摄策略的自定义；尚未确认当前算法的独立细粒度降噪接口，也没有验证任何设置能改善成片。** 本轮未制作或安装新的调参模块。

### 18.8 上轮指定的两项材料（本轮已取得）

| 对象 | 当前定位依据 | 用途 |
| --- | --- | --- |
| `/odm/lib64/libarc_aisp.so` | SDK 的 ArcAIsp 加载器，加上 Provider 实际映射 | 分析该候选算法后端真正接收的参数和 tuning 消费者 |
| `/odm/etc/camera/aisp.json`（若存在） | SDK 引擎的默认配置读取路径 | 核对在机配置、算法分支和进一步的具体库／资源路径 |

这两项现已收到；对实际配置与 Arc 适配层的分析见第 19 节，无需重复采集。

## 19. 在机 AISP 配置与 Arc 适配层：已明确各分支后端

本轮收到 `camera67_aisp_core.tar.gz`，包含 `aisp.json` 和 `libarc_aisp.so`。已完成安全解包、JSON 解析、ELF 依赖／接口检查、关键函数反汇编，并与此前 Provider 的加载记录对照。没有执行上传的 `.so`。

### 19.1 文件核对

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `/odm/etc/camera/aisp.json` | 8,082 | `b957397991b90b8daee47625f9a5cc2d1a7b8d5f91ab3ac1031c66496821b1a2` |
| `/odm/lib64/libarc_aisp.so` | 908,072 | `562b834c1a88e6c7aec228298c46a8a4f1cb8d91132cce72b213e6b9dc5e2fc3` |

Arc 文件为 ELF64 AArch64，直接依赖仅有 `liblog.so`、`libc.so`、`libm.so`、`libdl.so`，但还会动态加载具体算法库。小量 `DT_NEEDED` 不能代表算法实现已全部包含其中。

### 19.2 配置确认了多个算法分支

`aisp.json` 中共有 **19 个 `aisp.algo` 条目**。下表记录实际字段，不代表已经测得每个分支的执行情况。

| 配置分支 | `lib` 字段 | 本轮需关注的状态 |
| --- | --- | --- |
| `AISP_BYPASS` | 未指定 | 旁路相关条目 |
| `AISP_NR`、`AISP_NR_LL` | `mialgo_ainr_ll` | `enable=1`，`bypass=0` |
| `AISP_HDR` | `arc_aisp` | `vendor_type=1`，`enable=1`，`bypass=0` |
| `AISP_HDR_LL`、`AISP_SE`、`AISP_SN` | `mi_supernight_raw` | 各分支仍有不同的输入／输出与同步设置 |
| `AISP_SR` | 默认 `mialgo_hdsr_sr` | 另有条件策略切到 `arc_aisp`，见下节 |
| `AISP_HDSR`、`AISP_HDR_F`、`AISP_SN_F` | 本条目未显式指定 | `vendor_type=1`；不能仅从省略字段推断最终库名 |
| `AISP_ELL` | `mialgo_ellc` | 极低照相关候选分支 |
| `AISP_SNSC`、`AISP_SNSC_HDR` | `mialgo_snsc` | 两个独立条目 |
| `AISP_NR_50M` | `mialgo_aiur` | `enable=1`，同时 `bypass=1` |
| `AISP_NR_LL_50M` | `mialgo_aiur` | `enable=1`，`bypass=0` |
| `AISP_DEPTH` | `miphone_capture_depth` | 深度分支 |
| `AISP_SA` | `mialgo_anchor_selection` | 本条目 `lib_fixed=1` |
| `AISP_SDSR` | 未指定 | `enable=1`，同时 `bypass=1` |

**重要范围修正：Arc 的 NR 类存在，不等于普通 AINR 默认就调用 Arc。** 这份配置将 `AISP_NR`／`AISP_NR_LL` 指向 `mialgo_ainr_ll`，将 `AISP_HDR` 指向 `arc_aisp`。上一轮对 Arc 的定位是实际加载的候选后端；本轮配置让不同算法分支的默认分工更明确。

此前那一次 Provider 采样未列出 `libmialgo_ainr_ll.so`，但列出了 Arc 和 Turbo HDR 相关库。这个差别只能描述当时的加载情况；不能据此断言 AINR 在所有场景永远不用，也不能把配置名直接当作拍照模式命中记录。

`AISP_NR_50M.bypass=1` 是值得进一步核对的具体字段，但还不能解释成“所有 5000 万／两亿像素拍照都关闭降噪”。该条目是否被选择、是否有其他算法接替以及高像素路径的实际输入，都需要结合调用记录。`enable`、`bypass`、`bypass_func` 和其他模式条件的含义应分别处理。

### 19.3 高像素／SR 具有明确的条件切换

`AISP_SR.policy` 中有两条实际策略：

| `/start/sensor_mode` | `/config/camera_mode` | 覆盖设置 |
| ---: | ---: | --- |
| 20 | 18 | `vendor_type=1`，`input_format=7`，`output_format=201`，`lib=arc_aisp` |
| 4 | 18 | `vendor_type=1`，`output_format=201`，`lib=arc_aisp` |

同一条件也在 Arc 的 `CreateAlgoWraper()` 中得到代码侧对应：

- 工厂函数位于 `0x6aba0`。
- 当内部 `camera_mode=18`、算法类型字段为 7、`sensor_mode` 为 20 或 4 时，特殊分支在 `0x6ac24` 构造 `ArcAlgoTFPSR`。

这是配置与消费者之间更具体的联系。这里的 18 是 SDK 的内部相机模式字段，不是 APP 的专业模式 ID，也不能直接作为 LSPosed 的模式条件。格式编号 7／201 也不是可任意修改的强度值。

前文已经在设备传感器配置中发现模式 20 的约两亿级尺寸；这为调查高像素流程提供关联线索。但当前还没有一张照片的运行记录把全部条件、缓冲区尺寸和算法调用完整串联起来。

### 19.4 `libarc_aisp.so` 的角色与已定位的真实接口

Arc 文件提供 `ArcAIspInit`、`Start`、`AddFrame`、`Run`、`Unit`、`SelectAnchor` 等入口，内部再按算法类型和配置构造不同包装类。

与当前重点有关的加载器如下：

| 本文件中的函数 | 地址 | 加载目标与参数接口 |
| --- | --- | --- |
| `ArcAlgoTFHDR::LoadAlgorithm()` | `0x925f4` | `/odm/lib64/libarcsoft_turbo_hdr_raw.so`；解析 `ARC_Turbo_HDR_Init`、`AddOneInputInfo`、`Process`、`PostProcess`、`SetParam`、`SetEffectMode` 等 |
| `ArcAlgoWraperTF::LoadGRFAlgorithm()` | `0x7ef94` | `/odm/lib64/libarcsoft_turbo_hdr_grf.so`；解析 `ARC_TFR_GRF_Init`、`AddOneInputInfo`、`SetParam` 与 `ARC_Turbo_HDR_GRF_GetBaseFrameIndexV4` 等 |
| `ArcAlgoTFNR::LoadAlgorithm()` | `0x94f04` | `/odm/lib64/libarcsoft_turbo_fusion_mfnr.so`；解析 MFNR 初始化、逐帧输入、处理、参数与效果入口 |
| `ArcAlgoRawHDR::LoadAlgorithm()` | `0xa576c` | `/odm/lib64/libarcsoft_hdr_raw.so`；另一套 RAW HDR 实现 |

上表中简写的函数名共享各自的 `ARC_Turbo_HDR_`、`ARC_TFR_GRF_` 或 MFNR 前缀，并非所有实现都有相同签名。

**此前 Provider 映射同时包含 `libarcsoft_turbo_hdr_raw.so` 和 `libarcsoft_turbo_hdr_grf.so`。** 对这两份文件的定位同时具有“明确加载代码”和“实际进程映射”依据。其他实现虽然有静态路径，也不能直接当作本次已执行分支。

`ArcAlgoTFHDR::ArcAlgoRun()` 位于 `0x937a4`。本轮可见其经加载所得的函数指针，多次调用 `SetParam` 并传入不同类型编号及结构地址；它不是一个已经确认接受单个浮点“强度”的设置器。字段语义、结构长度和范围仍要由真正接收这些结构的实现来确认。

### 19.5 `.bin` 配置的读取方式与 `ALGO_STYLE` 的实际用途

Arc 的 `loadConfig(ArcAIspConfigData*)` 位于 **`0x7d104`**。它在 `0x7d13c` 打开：

```text
/odm/etc/camera/arc_aisp_config.bin
```

尽管文件后缀为 `.bin`，**本样本的读取代码使用 `fgets`／`strstr`／`sscanf` 逐行解析文本键值**。第 19 轮分析时尚未取得文件本体；随后收到的实际文件及其内容见第 20.2 节。

已核对到的键包括：

| 配置键 | 代码中可确认的用途边界 |
| --- | --- |
| `process_timeout_ms` | 处理时间限制 |
| `enable_xdr_callback` | XDR 回调相关开关 |
| `ALGO_STYLE_HDR_DEFAULT`、`ALGO_STYLE_HDR_PORTRAIT` 等 | 参与对应算法实现的选择 |
| `ALGO_STYLE_NR_DEFAULT`、`ALGO_STYLE_NR_PORTRAIT` 等 | NR 实现选择候选，尚非独立降噪强度 |
| `city_night_enable`、`city_night_lux_range` | 城市夜景分支选择条件 |
| `hdsr_ae_ratio_strategy`、`flash_capture_mode` | 特定拍摄策略 |
| `error_code_*` | 错误码映射相关配置 |

`ALGO_STYLE` 不能仅凭“style”这个名字解释成胶片／色彩滤镜。本轮已见工厂函数读取 `ALGO_STYLE_HDR_DEFAULT` 对应字段：值为 1 的路径构造 TF HDR 或条件满足时的 CityNight 实现，另一条路径构造 RAW HDR。NR 分支在相应字段为 1 时构造 `ArcAlgoTFNR`；不能假设所有算法都有通用的 0／1 强度含义。

这种配置能研究算法策略的替换或选择，但替换实现涉及输入格式、场景、输出与下游处理。当前不把它作为面向用户的“柔和／标准／增强”画质预设，也没有给它编造合法数值范围。

### 19.6 已经可以确定的开发结论

| 功能目标 | 本轮结束时的状态 |
| --- | --- |
| 每镜头／模式的锐化、纹理、色彩调节 | 已有 APP 入口与转换依据，可进入实现与真机验证阶段 |
| 减少额外加锐的自然细节配置 | 有明确切入点；是否减少白边、保留更多真实细节仍需原图对照 |
| HDR／MFNR 策略 | 已知 APP 请求入口以及部分 Provider 消费、覆盖和路由条件，可做受限调节与状态记录 |
| 独立明度／色度降噪 | 已明确普通 AINR 的配置目标；有效强度结构和范围仍未获得 |
| HDR 内部参数细调 | 已定位实际加载的 Turbo HDR／GRF 接口；其具体参数结构消费者仍需继续分析 |
| 修改 `aisp.json` 的分支、旁路或格式字段 | 有配置消费者证据；尚不构成经过验证的画质优化方案 |
| 一套参数覆盖普通、高像素、专业与录像 | 现有证据显示多路策略与实现，仍需逐路径适配 |

因此，第一版已有参数与策略面板的开发可以先推进。继续还原算法内部参数属于更深一层工作，不应把这部分不确定性隐藏在已经可用的普通锐化／色彩控件中。

本轮取得的是静态证据与配置映射，未安装新的调参模块、未修改手机库或配置，也未做画质 A/B 实拍。

### 19.7 上一轮的采集目标（本轮已收到）

继续分析独立降噪和 HDR 内部参数时，可以明确分成两路：

1. **普通 AINR：** 按 `aisp.json` 中的 `mialgo_ainr_ll` 寻找实际库文件，并核对目标场景中的加载／调用；当前不能假设它一定在 `/odm/lib64/` 或已进入本次进程。
2. **当前已加载的 HDR：** 优先读取已确认的 `libarcsoft_turbo_hdr_raw.so`、`libarcsoft_turbo_hdr_grf.so`，以及存在时的 `arc_aisp_config.bin`。无需先遍历所有 Arc 夜景／人像实现。

下面保留上一轮的只读采集命令供追溯；其四项目标已经在本轮归档中收到，**无需重新采集**。其中普通 AINR 来自 `/odm/lib64/`。

```bash
su -c '
set --
for p in \
    odm/lib64/libarcsoft_turbo_hdr_raw.so \
    odm/lib64/libarcsoft_turbo_hdr_grf.so \
    odm/etc/camera/arc_aisp_config.bin \
    odm/lib64/libmialgo_ainr_ll.so \
    vendor/lib64/libmialgo_ainr_ll.so
do
    if [ -f "/$p" ]; then
        set -- "$@" "$p"
    else
        printf "MISSING /%s\n" "$p"
    fi
done
if [ "$#" -gt 0 ]; then
    tar -czf /sdcard/Download/camera67_quality_targets.tar.gz -C / "$@"
fi
'
```

这批材料的接收代码分析见第 20 节。是否改善成片，仍以实际图像和拍摄行为为准。

## 20. Turbo HDR／GRF 接收参数、噪声回填与 AINR 的 JDD 依赖

### 20.1 本轮文件与分析边界

本轮上传归档为 `camera67_quality_targets.tar.gz`。归档中的路径、文件大小与 SHA-256 如下；三个库均为 ELF64 AArch64。本轮仅进行静态分析，没有运行上传的库、替换手机文件或安装调参模块。

| 归档路径 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `odm/etc/camera/arc_aisp_config.bin` | 228 | `1336d6e2167d051b408c2332da2eba1918be6c37d02025880e89389b5c79ad83` |
| `odm/lib64/libarcsoft_turbo_hdr_raw.so` | 178,337,816 | `525b67928edb0d859033e151961cf15bda8a16b70b7253dc515ed669af9b8372` |
| `odm/lib64/libarcsoft_turbo_hdr_grf.so` | 690,184 | `4f927ef7bbbec9624dfa102436cfe52364caa54a0b63c1cfb6c28c19ea98d4fc` |
| `odm/lib64/libmialgo_ainr_ll.so` | 5,847,400 | `8af61865dd95866bf69cfe235b798fe8e6b50601cbd5f93466633063881c0b5d` |

下文地址均为对应 ELF 的链接虚拟地址，运行时必须按实际加载基址换算，不能直接拿来写手机进程内存。参数编号也仅对应这些精确样本。

### 20.2 实际 Arc 配置已确认是文本

文件使用 CRLF 换行，内容为：

```text
device_name:Q11_series
process_timeout_ms:10000
error_code_remap_algo:201,202,203,204,225,227
error_code_remap_origin:1006,1300,1400,1005,1010,1011
error_code_remap_mapper:1801,1802,1803,1804,1701,1702
enable_xdr_callback:0
```

这份实际文件没有 `ALGO_STYLE_*`、独立降噪强度或锐化半径等覆盖项。加载器支持某个键，不等于在机文件已配置该键。`Q11_series` 是文件内的设备标签，不能据此推断零售机型；`enable_xdr_callback:0` 只描述该回调设置，不能解释为全相机关闭 XDR。`10000` 是配置中的超时值，不能当作实测拍照耗时，也不能与上层 `aisp.json` 的超时字段混为一项。

### 20.3 Turbo HDR 的参数编号已经追到接收函数

已核对的调用关系为：`ARC_Turbo_HDR_SetParam()`（`0x929e740`）→ 内部 `ARC_TF_RAW_SetParam`（`0x92c01c8`）→ `TF_wrapper::SetParam(int, void*, DumpCommonInfo&)`（`0x92a9a6c`）。最后一层以编号查找回调，经虚表 `+0x30` 调用；本轮结合 `.rela.dyn` 的 AArch64 相对重定位解析回调，随后逐个检查接收代码，没有仅凭字符串顺序猜编号。

| 编号（十进制／十六进制） | 接收代码标识或用途 | 接收函数地址 | 对调参的实际意义 |
| --- | --- | --- | --- |
| 1／`0x01` | `IPE_GAMMA_TABLE` | `0x92b4134` | 表或结构数据；不能传入单个“锐化值” |
| 9／`0x09` | `GRF_INFO` | `0x92b450c` | GRF 处理信息 |
| 16／`0x10` | `EXTPARAM` | `0x92b474c` | 外部 AE、人脸亮度与直方图相关参数；详见下文 |
| 12／`0x0c` | `XDR_LINEARRAW` | `0x92b49f8` | RAW 数据传递相关结构 |
| 20／`0x14` | `XDR_LINEARRAW_EVBASE_FRAME` | `0x92b4d10` | EV 基础帧相关信息 |
| 11／`0x0b` | `ULTRARAW_LINEARRAW` | `0x92b4f48` | UltraRAW 数据传递相关结构 |
| 61／`0x3d` | `PREVIEW_ADRC_GAIN` | `0x92b51b4` | 预览 ADRC 增益信息 |
| 54／`0x36` | `FOGGING` | `0x92b54b8` | 接收代码保存一个 64 位值，尚不能假定是浮点“雾感强度” |
| 23／`0x17` | `AE_RATIO` | `0x92b5668` | 读取 float，并以是否大于 0 设置使用标记；完整合理范围仍未知 |
| 60／`0x3c` | `SUNSET` | `0x92b5988` | 日落场景相关结构 |
| 98／`0x62` | `FACE_TARGET_LUM` | `0x92b5bdc` | 人脸目标亮度信息 |
| 106／`0x6a` | `FACE_TARGET_LUM_CONFIDENCE` | `0x92b5f10` | 上述信息的置信度 |
| 5／`0x05` | `IR_RATIO_PARAM` | `0x92b6220` | 特定比例信息，尚未还原为用户控件 |
| 99／`0x63` | `ASD_INFO` | `0x92b651c` | 当前回调中可见的是条件写入 dump 信息，不能当作降噪滑杆 |
| 88／`0x58` | `SCREEN_FORM` | `0x92b6784` | 屏幕／形态状态信息 |
| 105／`0x69` | `outerFoggyLevel` | `0x92b6a94` | 读取 32 位整数；无符号检查接受 0–3，写入 usable 与 human_foggy_mode 字段 |
| 166／`0xa6` | `GET_PARAM_AI_MODEL` | `0x92b6c74` | 从内部向调用者缓冲区复制 64 字节，是获取信息的方向 |
| 72／`0x48` | `LIVEPHOTO_MODE` | `0x92b6e14` | 动态照片模式信息 |

此外，内部入口单独处理 24／`0x18` 的 `SHOT_JPG_NAME` 和 53／`0x35` 的 `INPUT_MODE`。这些编号属于不同类型的数据，不能采用同一套 float 指针或同一数值范围调用。

`EXTPARAM` 进一步调用 `0x92a78b4`：从输入读取前三个 float 并转整数，随后保存其他 float；对应日志明确列出 `face_lum`、`frame_lum`、`preview_face_lum`、`foggy_con_val` 以及 `face_hist_lum`。因此这里的“扩展参数”已有具体 AE／人脸亮度语义，不能仅凭名称包装成通用 AI 降噪强度。

`outerFoggyLevel` 的 0–3 是**这一接收函数的代码接受范围**，还不是四档画质效果的实拍结论。当前未确定 APP 如何提供它、哪个场景使用它、后续策略是否覆盖它，也没有把它与此前“迷雾森林”色彩滤镜混用。

### 20.4 返回成功可能掩盖参数未被接受

在内部入口的普通转发路径中：`0x92c039c` 调用 `TF_wrapper::SetParam`，`0x92c03a0` 跳往 `0x92c01fc`，后者直接令返回值为 0。被调用的 wrapper 自身存在“不支持此参数”并返回 2 的分支，但此路径没有把该返回值继续传出。

例如公开接口对 56／`0x38` 的 `CONTRASTINFO` 有复制、日志分支，但本次还原出的 wrapper 参数映射没有这一编号。对这种路径，不能根据公开名称或上层成功返回断言算法使用了对比度参数。

后续模块需要记录具体消费者命中、参数类型、帧／场景以及处理后的状态，并配合成片对照；仅以 SetParam 返回、APP 中数值回显或没有崩溃作为成功标准，会把无效调参误报为有效。

### 20.5 已找到实际的整数 0–100 检查，但属于 HDR 噪声回填

库中 `0x67503` 的断言文本为 `denoise_intensity >= 0 && denoise_intensity <= 100`。本轮继续核对交叉引用与指令，而非只记录字符串：

- `0x941987c` 对整数参数执行无符号 `>=101` 拒绝检查，对应日志函数名 `backfill_raw_noise_gray`。
- `0x9419bec` 对另一位置的整数参数做同样检查，对应亮度阈值相关的噪声回填函数。
- `0x941a038` 亦检查该范围，涉及 mask 的 RAW 噪声回填；另外两处引用位于 RGB 亮度噪声回填函数。
- 在这些代码中可见以 `100 - value` 计算比例，再乘以 1024 并取整；例如第一处在 0 时产生系数 1024，在 100 时产生系数 0。这个系数在该回填步骤中的方向，不能直接推广为整个降噪算法的强度方向。

直接调用点也已找到：`0x932b5b0` 从上游对象 `+0x4c` 读取整数传入第一处；`0x932b604` 还传入更多相邻参数；`0x932c1b8` 调用带 mask 的实现。上游对象的完整类型、其参数来源以及 APP 的可达入口尚未还原。

这说明 HDR 库内部确实存在受数值控制的噪声回填步骤，为研究降噪后纹理／噪声保留提供了具体入口。它仍不能证明已找到普通 AINR 的独立明度／色度降噪，也不能直接做成覆盖普通、专业、高像素和录像的统一 0–100 滑杆。

另一个容易误读的接口是 `SetEffectMode`：公开入口 `0x929e94c` 调用 `0x92c087c`，其中参数为 0 时写内部状态 2，非 0 时写状态 1。这里看到的是两个内部状态的映射，尚非多个胶片风格或连续强度控件。

### 20.6 GRF 的可见设置是拍摄状态与辅助信息

`ARC_TFR_GRF_SetParam()` 位于 `0x3a12c`。其分派检查和接收代码对应如下：

| 编号 | 标识 | 本轮核对到的输入 |
| --- | --- | --- |
| 22／`0x16` | `IS_HDSR` | 32 位整数，写入实例字段 |
| 23／`0x17` | `AE_RATIO` | float，写入实例字段 |
| 24／`0x18` | `SHOT_JPG_NAME` | 字符串 |
| 72／`0x48` | `LIVEPHOTO_MODE` | 32 位整数 |
| 88／`0x58` | `SCREEN_FORM` | 32 位整数 |
| 109／`0x6d` | `CCT` | float；遍历当前条目写入色温相关字段 |

这个入口对其他编号存在“不支持”分支。上述可见接收代码没有提供一套通用的锐化、明度降噪、色度降噪滑杆；AE 比例和 CCT 是上下文信息，擅自改成画质强度会改变其含义。

### 20.7 普通 AINR 继续调用 JDD，实现仍有下一层

`libmialgo_ainr_ll.so` 导出 `MialgoInit`、`MialgoAddFrame`、`MialgoRun` 等会话接口。其 ELF `DT_NEEDED` 明确包含 `libmialgo_ainr_jdd.so`，并存在对 `AinrJdd::MialgoJddInit`、`ModelInit`、`Run`、`ModelDeInit`、`DeInit` 的未定义导入。

本轮也核对到真实调用指令：

| 本库调用点 | 被调用接口 | 可确认的结构传递 |
| --- | --- | --- |
| `0x1c276c` | `MialgoJddInit` | 句柄地址、初始化参数、错误信息指针位置 |
| `0x1c2968` | `MialgoJddModelInit` | 调用前复制 `0x198`（408）字节的参数块 |
| `0x1c3184` | `MialgoJddRun` | 调用前复制 `0x440`（1088）字节的参数块 |

这些证据足以确认包装层会把初始化和运行交给 JDD，不能把当前库当成全部算法本体。复制长度也不足以恢复完整 C 结构、每个字段的名称和安全取值。

这批归档未包含 JDD 文件。此前 Provider 采样也未列出 `libmialgo_ainr_ll.so`；现在确认文件存在及静态调用链，仍不等于目标拍照场景已执行该分支。当前没有获得独立 luma／chroma 降噪强度的有效字段与范围。

三份库的主要额外依赖为：HDR RAW 的 `libarc.ion.so`、`libarcsoft_qnnhtp.so`、`libcdsprpc.so`、`libmpbase.so`；GRF 的 `libarc.ion.so`、`libmpbase.so`；AINR 的 `libmialgo_ainr_jdd.so`、`libc++_shared.so`。这描述的是链接依赖，不等同于每个依赖都参与每一张照片。

### 20.8 对开发顺序的具体判断

1. **已有依据的第一版功能：** 按镜头／模式保存锐化、纹理和色彩配置，接入原有 HDR／MFNR 策略，并保留原厂默认值与一键恢复。仍须逐项确认目标设备执行与预览／成片一致性。
2. **适合继续研究的底层功能：** HDR 噪声回填参数的上游来源、有限场景中的雾等级／人脸亮度参数，以及普通 AINR 的 JDD 参数结构。尚不将这些实验点作为已生效的用户功能。
3. **目前不能承诺：** 独立明度／色度降噪、改变 AI 模型必然更好、一套参数覆盖两亿像素／专业／录像，以及已经改善的解析力或动态范围。

若继续深入普通 AINR，新增材料应收窄为 **`libmialgo_ainr_jdd.so`**，无需重新发送已收到的 HDR、GRF 或 AINR 包装层。其绝对路径尚未从本次归档确定；可以只读查找 `/odm/lib64` 和 `/vendor/lib64`，确认存在后再采集。HDR 这一侧已能继续研究当前文件中的上游参数，不需要先盲目收集所有 Arc 库。

本轮完成的是参数消费者和依赖链的进一步还原。尚未生成新的可安装相机／调参模块，尚未连接手机验证调用或做原图 A/B 测试。

## 21. “画质实验室”0.1.0 第一版模块交付

用户随后明确要求先开发锐化、纹理、色彩及 HDR／MFNR 策略面板。本轮新增独立工程 `camera67-panel`，包名 `cn.camera67.quality`，构建 `Camera67_QualityPanel_LSPosed_v0.1.0.apk`；没有复用此前滤镜模块／相机的界面资源、代码、LUT、原生库或签名。

### 21.1 已实现的范围

| 项目 | 本版行为 |
| --- | --- |
| 总开关与覆盖 | 初始关闭；单项默认继承，仅修改主动设置的参数 |
| 分组 | 全局、某模式、某镜头、某模式＋某镜头，逐字段合并；支持 JSON 导入／导出 |
| 拍摄锐化 | 接入 `n9.d0.W(int)`、旧 `r9.e.m0(int, Builder)`、新 `Wp.e.F(b0,int)`；读取实际镜头 `sharpness.range`，与 0–6 取交集，未报告或超范围时跳过 |
| 纹理 | 本版采用 `StyleAdjustEffect` 的风格锐化；不把它称为已还原的独立厂商纹理算法强度 |
| 色彩 | 对比度、饱和度、冷暖、色调；按原 APP 风格转换，维护掩码并保留其他通道 |
| 预览／照片风格 | 接入 `EffectController.c()` 与成片 `TagForCandy.getPictureStyleCandyParams(Wu.g)`；预览请求刷新 |
| HDR | 沿用相机设置／请求关闭；不强制开启或重写曝光融合 |
| MFNR | 沿用原厂／请求关闭；4、6、8 帧请求为实验项，仅在原厂已启用时覆盖应用帧数 |
| 模式 | 识别 163／175／167／162／180；其他模式沿用原厂；录像不应用拍照 HDR／MFNR 策略；专业 RAW／UltraRAW 跳过这两项策略覆盖 |
| 状态 | 记录配置、实际 Builder 写入及风格属性生成；最多 96 条去重事件，可查看／复制诊断 |
| 恢复 | 恢复当前分组、恢复全部原厂、停用模块；未改原相机偏好、系统库或设备配置 |

首次启用 LSPosed 后必须结束并重开相机。保存新配置或恢复原厂后同样以重开相机为准，避免会话／请求缓存造成误判。源码及完整操作说明随模块交付。

### 21.2 已执行的验证及边界

- 33 项策略／配置断言：分组继承、范围限制、原厂 MFNR 关闭时不改启用、录像不套用拍照帧数、色彩转换、掩码保留、导入校验与默认关闭。
- 对固定 SHA-256 的原 APK 核对 27 项关键方法／字段契约，包括旧锐化参数顺序为 `(int, Builder)`，新路径为 `(b0,int)`；并核对 RAW 状态字段、风格字段和能力对象类型。
- APK 资源编译、Java 编译、DEX 转换与独立 v2／v3 密码学签名验证；未打包 Xposed API 实现、原相机／旧模块类或资源、原生库及签名私钥；不声明网络、相机或存储权限。
- 配置保存在模块私有数据区，通过检查模块／相机 UID 的 Provider 通信；相机主进程之外不注入。版本不匹配时参数覆盖停用，读取配置失败时回到不覆盖状态。

本轮没有连接真机或 Android 模拟器，未实际安装、拍摄 A/B 样张或录制对照视频。因此，高像素／专业／录像的各项支持和预览／成片一致性、实际帧数、HAL 执行、稳定性与性能都需要设备验证；该 APK 为第一版测试模块，不能宣称已优化原生算法或证明画质改善。

## 22. 0.1.1：初始化与状态连接修复

用户反馈 0.1.0 一直显示“尚未收到相机状态”。当前未收到真机异常日志，不能据此断言是某一唯一原因；本轮完成代码中可确认的初始化与诊断问题修正，并提供覆盖安装包。

- 原版只依赖 `Application.attach` 进入初始化，且入口实现类在静态初始化时就创建主线程 Handler。新版把 LSPosed 入口分离为不访问 Looper／Context 的 `HookEntry`，由 attach、Instrumentation 的 application／activity 回调、Activity resume 及已存在的 Application 共同提供初始化机会。主进程判断也兼容 Manifest 声明的进程名。
- 原版 Provider 回传失败只写日志，面板无法区分未注入、初始化失败、版本不符与回传失败。新版连接卡片显示本机版本、面板通道自检、启动来源、回传通道、配置结果和错误，并区分旧版本遗留状态。
- 保留 Provider；新增显式一次性 PendingIntent 回传至模块内未导出的 `StatusReceiver`，校验随机数、一次性使用与 60 秒窗口。配置备用通道由该模块接收器调用相机给出的 Binder 回调，检查真实 Binder 调用 UID 必须等于模块 UID 后才接受保存的配置；不信任普通广播附带的配置内容。
- “打开相机并检测”只发送有限次数握手；返回面板／手动刷新时也做有限检测，没有持续后台轮询。Provider 失败时保留已经通过验证的配置，避免无条件把可信的备用通道配置清空。
- APK versionCode 从 100 升至 101，包名、配置 schema 与独立签名不变，不需要卸载旧版或清除数据。建议覆盖安装后重启手机一次，打开面板点击“打开相机并检测”，在相机停留约 8 秒后返回查看。

本轮验证：45 项策略／配置／连接规则断言；入口类和核心类在 Android SDK 抛异常桩环境下、不创建 Looper／Context 的类加载回归检查；原 APK 27 项调用／字段契约；v2／v3 签名验证；与旧 APK 签名证书一致性检查。目标 APK 中仍不打包相机／旧滤镜模块类、资源、原生库或私钥，也不增加系统权限。

本轮仍未连接真机或模拟器，实际 LSPosed 注入、Android 跨进程消息、配置生效与拍摄效果需要用户设备验证。若仍未收到响应，新面板的“查看／复制诊断”可提供进一步定位所需的本机检查与连接阶段；框架日志的 `[QualityPanel] ENTRY 0.1.1` 用于判断是否进入模块入口。

## 23. 0.1.1 仍无响应：等待框架加载证据

本轮收到用户截图及面板 JSON：`module=cn.camera67.quality / 0.1.1`；相机为 `6.7.000280.0 / 670002800`；`providerSelfTest=通过`；`runtime={}`、`replyTime=0`、`pingError=""`。总开关为 true，但 `profiles={}`，说明尚未配置具体覆盖项目；这个配置状态本身不能解释连接回传为何缺失。

能确认的是面板进程的本地 Provider 调用成功，并且面板已发出检测；尚不能据此证明相机进程读到了配置或加载了入口。需要框架加载日志、入口日志或进程映射，才能进一步判断未注入、入口加载／执行异常、或系统限制跨进程通道。

已对实际交付 APK 复核：

- `assets/xposed_init` 精确指向 `cn.camera67.quality.HookEntry`，文件结尾换行正常。
- 该入口类在 DEX 中真实存在，声明实现 `IXposedHookLoadPackage`，具有 public 无参构造，以及 public `handleLoadPackage(XC_LoadPackage.LoadPackageParam)`。
- Manifest 声明 legacy Xposed 元数据，最低 API 82；原相机没有另外指定应用进程名，此前设备采样也记录 `com.android.camera`。这些静态事实仍不等于当前手机已按作用域加载该模块。

新增 `Camera67_Check_Injection_ReadOnly.sh`：以 root 读取指定包版本、安装 APK SHA-256、已知框架进程及属性、相机进程的相关映射条目，以及包含本模块包名／QualityPanel／HookEntry 的框架日志片段。检查 logd 状态；没有运行的日志服务时跳过限时 logcat 采样，不启动服务。不复制照片、图像缓冲区、应用偏好或框架数据库，不修改模块作用域和设备设置；只在 Download 新建诊断目录和压缩包。模块日志相邻上下文可能包含其他模块名称。

脚本通过 POSIX sh 与 Bash 语法检查，未在用户手机上执行。使用方法：保持相机打开，在 Termux 执行 `su -c 'sh /sdcard/Download/Camera67_Check_Injection_ReadOnly.sh'`，提供生成的 `Camera67_Injection_*.tar.gz`。日志或映射缺失也可能由记录服务或读取限制导致，不能单凭缺失判定未注入。

本轮进展为收窄故障范围与提供采集工具，连接问题尚未解决，尚不能宣称画质参数已生效。

## 24. 真机采集结果与相机作用域复测

已检查 `Camera67_Injection_20261109_133843_16642.tar.gz`，采集时间为 2026-11-09 13:38:43（北京时间）。设备运行 Android 17（SDK 37）、LSPosed 2.2.1（7912）和 Zygisk Next 1.5.2（864）。

| 采集项 | 观察结果 |
| --- | --- |
| 已安装包 | 主用户 `user 0` 安装了 `cn.camera67.quality` 0.1.1（101）与 `com.android.camera` 6.7.000280.0（670002800），两份 APK 的 SHA-256 均匹配对应样本。 |
| 相机进程 | 主进程 PID `18349`，UID `u0_a149`，命令行 `com.android.camera`。`lspd` 正在运行，进程映射中包含 LSPosed 的 `zygisk/arm64-v8a.so` 和 Zygisk Next 的 `libzygisk.so`。 |
| Java 入口 | 模块过滤日志及 `module_logcat.txt` 未记录 `cn.camera67.quality`、`HookEntry` 或 `[QualityPanel] ENTRY 0.1.1`。本次采集未保留无匹配的框架原始日志。 |
| 作用域与通信 | 采集未读取 LSPosed 的启用状态或相机作用域。`dumpsys package` 中的 `enabled=0` 是 Android 的应用默认启用状态。面板同进程 Provider 自检通过，来自相机的握手仍为 `replyTime=0`。 |

原生库映射只证明框架原生代码进入了相机进程。采样缺少框架对本模块的加载决策与 Java 入口记录，无法在作用域未生效、入口加载或初始化失败、相机端回传失败之间定因。采集中部分 `cmd` 或 `pm` 调用报 `Failed transaction (2147483646)`，随后仍读出了安装包路径和哈希。该现象只对应采集命令，缺少与面板握手的直接关联。

1. 在 LSPosed 的「模块 → 画质实验室」中确认模块已启用，并勾选主用户的系统相机 `com.android.camera`。如果列表隐藏相机，打开系统应用筛选选项。 [LSPosed 作用域说明](https://github.com/LSPosed/LSPosed/wiki/Module-Scope)
2. 在系统的相机应用详情页强行停止相机，再从画质实验室点击「打开相机并检测」。在普通拍照界面停留约 8 秒，返回面板查看连接诊断。
3. 若仍是 `replyTime=0`，记录作用域页及刚重开相机时包含 `cn.camera67.quality`、`HookEntry` 或 `QualityPanel` 的 LSPosed 日志。若有异常，保留紧接的异常信息。若无匹配，记录该结果即可。

出现 `[QualityPanel] ENTRY 0.1.1` 表明模块回调已进入，之后检查相机端初始化和状态回传。有加载记录但伴随类加载异常时，按异常修正入口。已确认作用域却仍缺少加载证据时，先核对框架对新相机进程的模块分配和日志采集。当前测试继续使用 0.1.1。

## 25. 0.1.2 状态回传与配置同步

用户运行只读探针后报告相机 PID 为 `23923`，`camera_ipc_thread=present`，`camera_SYNC_V1=registered`，`camera_CONFIG_CHANGED=registered`。该采样确认 0.1.1 的 Java 模块已经启动并注册相机端接收器。面板的偏好可读，`panel_status=empty` 且 `panel_replyTime=0`。进程线程采样停在 `do_epoll_wait`，仅反映检查时刻，具体失败的 IPC 调用仍未观测到。

0.1.1 的备用回传与 Provider 读写共用线程，回传前还会先调用 Provider。0.1.2 使用系统有序广播结果回传状态，Binder 配置同步与 Provider 后台读写独立执行。握手校验包名、同一 Android 用户及本次随机编号，Binder 还校验实际调用 UID、有效期和单次使用。旧版本或较早的配置结果受到版本及修订号检查。面板读取最新状态，无须浮窗取得焦点。配置同步后尝试向目标相机授予专用只读 URI，帮助相机在之后的启动中发现 Provider。 [Android 有序广播参考](https://developer.android.com/reference/android/content/Context) · [Android 包可见性参考](https://developer.android.com/training/package-visibility/automatic)

APK 为 `cn.camera67.quality` 0.1.2（102）。完成 54 项策略、旧配置和握手规则测试，入口类加载测试、v2／v3 签名验证，以及与 0.1.1 的签名证书比对。模块仍适配 `com.android.camera` 6.7.000280.0（670002800）。Android 17 真机安装、握手、实际拍摄与 HAL 执行由后续测试确认。

用户希望降低锐化，让直出更柔和。可先在普通拍照及常用镜头分组启用纹理并设为 −10，拍摄同一场景作对照。若相机上报有效的锐化范围和原厂默认值，再尝试降一档。拍摄锐化使用应用的请求入口，纹理使用预览和成片风格属性。对照原图检查细边缘白边和细节，结合 `sharp`、`photo/style` 等运行事件判断。

## 26. 锐化强度的请求与成片通路

本轮复核相机 6.7.000280.0（670002800）的原 APK，SHA-256 为 `4637b77d5b365260f8089318179206d42d0ba842fb08109f203f1ea9d3908f63`。直接扫描 DEX 的方法、字段引用和原 APK 中的 `libMiFilterSDK.so` 着色器，另对照此前设备采集的 79 份配置。

### 26.1 拍摄请求级别

`Camera2Module.updateSharpness()` 从当前镜头能力对象调用 `n9.e.o0(n9.d)`，然后执行 `n9.d0.W(int)`。`o0()` 从 `la.x0.X1` 读取 `org.codeaurora.qcamera3.sharpness.strength` 的静态默认值，缺少能力或读不到该值时应用回退到 `1`。`s2.T0` 从 `la.x0.W1` 读取 `org.codeaurora.qcamera3.sharpness.range`。专业模式在对应功能开关允许时从 `s2.T0` 取手动档，其余可执行分支回到镜头默认值。两者都将值保存到 `n9.e0.G0`。

| 路径 | 从配置到请求的写入链 |
| --- | --- |
| 旧请求构造 | `n9.e0.G0 → n9.k0.M0(Builder,e0) → r9.e.m0(int,Builder) → la.F0.f() → la.F0.m() → Builder.set()` |
| 新请求构造 | `n9.e0.G0 → Mp.e.a(pa.b0,int) → Wp.e.F(pa.b0,int) → pa.b0.i() → la.F0.e() → la.F0.m() → Builder.set()`。包装器还按标签名缓存值。 |
| 高通请求标签 | 两条均使用 `la.B0.C1`，名称由 `la.N.get()` 提供，为 `org.codeaurora.qcamera3.sharpness.strength`，值为 `Integer`。`G0=-1` 时跳过该写入，两个高通适配器将大于 `6` 的输入改成 `0`。 |

还有一条可能覆盖 `C1` 的厂商纹理路径。 `Camera2Module.updateStyleTexture()` 按设备条件选择 `EffectController.m0(int)` 或 `n9.d0.z(int) → n9.e0.D0`。后者由旧 `n9.k0.P()` 或新 `Mp.e.a()` 写入。两套实现均在部分条件下于专用纹理键 `la.B0.A1`（高通 `com.xiaomi.sharpness.strength`）和 `C1` 之间选择，相关判断在两条实现中的分支方向不同。同一请求若写 `C1` 多次，验证应以提交前的最后值为准。

Android 的标准 `CaptureRequest.EDGE_MODE` 提供 `OFF`、`FAST`、`HIGH_QUALITY` 等边缘增强模式。本次直接字段引用扫描未在原 APK DEX 找到对该字段的引用。当前定位到的整数强度来自厂商 `C1` 标签。 [Android Camera2 EDGE_MODE 参考](https://developer.android.com/reference/android/hardware/camera2/CaptureRequest#EDGE_MODE)

### 26.2 成片渲染强度

| 成片入口 | 取值和触发条件 |
| --- | --- |
| 单独的 `SharpenEffect` | `EffectController.B → x() → MIVIRenderTag.mSharpenDegree`。构造时 `B=0`，还找到 `C9.o.b()` 中的直接写入。 `mSharpenDegree` 非零时 `initType()` 设置 `mType` 的 `256` 位。 `initParams()` 按 `mSharpenDegree / 100.0` 写出 `SharpenIntensity`，并保存为 `sharpenCandyParams`。 |
| `StyleAdjustEffect` 的风格细节 | `EffectController.c() → Wu.g.d → TagForCandy.getPictureStyleCandyParams()`。 `initType()` 在 `mAlgo>0` 或 `mSoftLight>0` 时设置 `mType` 的 `512` 位。 `initParams()` 在该位存在时调用风格脚本生成器。生成器用 `Wu.g.c` 作 `Algos`，其中 `64` 位启用锐化项，`d` 为浮点强度。原厂 UI 的纹理 `-10` 映射为 `-0.10`。 |
| 滤镜额外加锐 | `TagForCandy.getFilterCandyParams(p3.b)` 在滤镜描述的 `Wu.d.i` 为真时，从参数数组第 `5` 号索引取值，追加一段独立的 `SharpenEffect`。 |

已追到成片参数的提交位置。旧 `n9.A0.K1()` 在 MIVI 功能开关开启时构造 `MIVIRenderTag`，写入 `com.xiaomi.mivi2.renderType`。渲染类型非零且参数可用时，经 `n9.k0.u0()` 把带结束符的 JSON 字节写到 `com.xiaomi.mivi2.render`。新 `Mp.e.b()` 也有通过 `pa.b0.i()` 写入同名类型和 JSON 数据的分支。 `Camera2Module.getParallelTaskDataParameter()` 与新 `Mp.c.a()` 另有读取 `getCandyParams()` 的任务数据路径。

原 APK 的 `libMiFilterSDK.so` 中，独立 `SharpenEffect` 与风格锐化的 GLSL 都使用中心像素加上高频残差。若中心为 $c$，四个邻域采样平均为 $a$，强度为 $s$，核心式为 $c+s(c-a)$。 `s=-0.10` 时这一步等价于 `0.9 × 中心 + 0.1 × 邻域平均`。风格 shader 检查 `Algos` 的 `64` 位，再执行该计算。

### 26.3 简化版的优先验证点

普通拍照优先观察最终 `C1` 是否写入、当前值和镜头实际范围，确认后再试降一档。成片脚本中若已有正的 `SharpenEffect`，可单独验证减小其系数。只修改 `getPictureStyleCandyParams()` 的参数时，原厂未启用风格或柔光的拍摄可能跳过整条调用。普通拍照、高像素与专业照片分别需要实际请求和直出对照。

在设备已采集的 79 份配置里，搜索锐化、边缘增强和纹理相关键及以上标签名均未匹配到可验证的强度字段。当前已有依据的控制点位于相机请求和成片脚本。拍摄请求写入和原厂渲染计算均已定位，目标机 HAL 的最终响应及正常拍摄会命中哪些成片分支仍须真机验证。 [KernelSU 模块覆盖机制](https://kernelsu.org/guide/module.html)