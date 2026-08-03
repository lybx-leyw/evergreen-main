plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // P1b：Chaquopy 把 CPython 编译进 APK，提供进程内 Python 执行（对应 ChaquopyRunner）。
    // 必须在 plugins {} 块内声明并应用，Kotlin DSL 才能识别 chaquopy {} 扩展；
    // 版本 17.0.0 由 Maven Central 的 com.chaquo.python.gradle.plugin marker 解析。
    id("com.chaquo.python") version "17.0.0"
}

android {
    namespace = "com.example.evergreen_base"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.evergreen_base"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // P1b：Chaquopy 仅支持其已编译的 ABI。
        // 含 x86_64 以便在本机 x86_64 模拟器上运行验证（真机发布可只留 arm64-v8a 缩小体积）。
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    // 统一 debug 签名：本地 flutter run 与 CI（release.yml 的 flutter build apk --debug）
    // 都使用仓库内 android/app/debug.keystore（标准 debug 密钥）。
    // 否则 CI runner 每次全新 → 每次新生成 ~/.android/debug.keystore → 签名每次不同
    // → adb install -r 覆盖升级报签名不匹配。
    signingConfigs {
        create("evergreenDebug") {
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("evergreenDebug")
        }
        release {
            // 正式发布仍暂用同一 debug 密钥（后续可换独立 release key）。
            signingConfig = signingConfigs.getByName("evergreenDebug")
        }
    }
}

flutter {
    source = "../.."
}

// P1b：Chaquopy 配置（进程内 Python 运行时）。
// 仅用标准库即可运行纯 Python 插件；若某插件需要第三方包（numpy / requests 等），
// 在此 pip { install("包名") } 声明，Chaquopy 会在构建期打包对应 wheel。
// ⚠️ buildPython 探测：环境变量 CHAQUOPY_BUILD_PYTHON 优先（CI / 他人机器），
// 否则回退 PATH 上的 python 命令（Windows: python，Unix: python3）——
// **不硬编码本机用户路径**（仓库可移植性；本机路径由 PATH 解析）。
// buildPython 缺失时 chaquopy 只会警告并**静默跳过** src/main/python 打包
// （2026-08-02 事故：pdf_translate.py 等未进 APK），
// 故对**文件路径**形态的值做存在性检查，把静默失败变成构建期硬失败；
// 命令名形态（python/python3）交给 OS 按 PATH 解析，无法预检。
val chaquopyBuildPython = System.getenv("CHAQUOPY_BUILD_PYTHON")
    ?: (if (System.getProperty("os.name").lowercase().contains("win")) "python" else "python3")
val chaquopyBuildPythonIsPath =
    chaquopyBuildPython.contains('/') || chaquopyBuildPython.contains('\\')
if (chaquopyBuildPythonIsPath && !file(chaquopyBuildPython).exists()) {
    error("Chaquopy buildPython 不存在: $chaquopyBuildPython。请安装 Python 3.11 或设置环境变量 CHAQUOPY_BUILD_PYTHON，否则 src/main/python 依赖会静默不进 APK。")
}

chaquopy {
    defaultConfig {
        version = "3.11"
        buildPython = listOf(chaquopyBuildPython)
        // pip 依赖：requests 全家桶（requests/urllib3/certifi/idna/charset_normalizer）
        // 已手动放入 src/main/python/（纯 Python 源码，构建期由 buildPython 编译打包）。
        // pycryptodome 含 C 扩展（无法手动拷贝源码），必须由 chaquopy 构建期装 wheel 进 APK，
        // 供爬虫脚本 `import Crypto.*`（RSA/AES 加密登录）使用。
        // 安卓 PDF 翻译（pdf_translate_pure.py，纯 Python 管线）：
        // pdfminer.six 读布局 + reportlab 写 PDF + pypdf 合并。
        // 复用 pdf2zh_next 翻译引擎（DeepSeek→OpenAI 兼容）需 openai/httpx/pydantic/
        // tomlkit/peewee/tenacity/rich/requests；babeldoc 的 AtomicInteger 由
        // scripts/babeldoc/ shim 提供（babeldoc 本体依赖 pymupdf 无法安装）。
        // 全部纯 Python，Chaquopy 可装（区别于 babeldoc 的 pymupdf/freetype/cv2 等 C 库）。
        pip {
            install("pycryptodome")
            install("pdfminer.six")
            install("reportlab")
            install("pypdf")
            install("openai")
            install("httpx")
            install("pydantic")
            install("tomlkit")
            install("peewee")
            install("tenacity")
            install("rich")
        }
    }
    // Python 源目录默认 src/main/python（动态插件由 MethodChannel 从设备路径按需加载，无需打包进 APK）。
}
