package com.example.evergreen_base

import android.graphics.Bitmap
import android.graphics.pdf.PdfRenderer
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import com.chaquo.python.PyException
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 原生侧 Python 执行桥（P1b）。
 *
 * 对应 Dart 端 [ChaquopyRunner]（`lib/core/plugin/plugin_runner.dart`），
 * 经 `MethodChannel('evergreen/python')` 的 `runScript` 在 app 进程内
 * 用 Chaquopy（CPython .so）执行 `.py` 文件。
 *
 * 协议（与 `统一py插件-安卓适配规划.md` §3.2 对齐）：
 *   invokeMethod('runScript', { entry, args, stdinJson, workingDirectory, runtime })
 *   → Future<Map> { stdout: String, stderr: String, exitCode: int }
 *
 * ⚠️ 本文件可经本环境 `flutter build apk` 编译验证（Android SDK 已就绪）；
 *   但**运行时**行为（Chaquopy 后台线程 / 流式回传 / 端口探测）需在
 *   模拟器 / 真机 `flutter run` 上端到端验收。
 *
 * 关键约束：
 *  - `.py` 插件需以**设备文件系统路径**形式传入 `entry`（如 app 私有目录
 *    `/data/data/com.example.evergreen_base/.../plugins/xxx/main.py`）。
 *    通过 `adb push` 预置，或在 Dart 侧把 assets 释放到 app 文件目录后传绝对路径。
 *  - `workingDirectory` / `entry` 所在目录会被加入 Python `sys.path`，
 *    以便插件 import 同目录模块。
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "evergreen/python"
        /// 长驻 server（方案 A）stdout/stderr 流式回传通道。
        private const val STREAM_CHANNEL = "evergreen/python_stream"
        /// PDF 预渲染通道（Task R3-6）：Dart 侧（VisionPdfPreprocess）经
        /// `renderPdfToPngs` 调系统 PdfRenderer 逐页渲染 PNG——安卓 pymupdf 平替。
        private const val PDF_CHANNEL = "evergreen/pdf"
        /// 渲染页最长边上限（px）：防止超大页面（扫描件/图纸）Bitmap OOM；
        /// 超出时等比缩小（对齐常见 OCR 输入上限）。
        private const val MAX_PDF_PAGE_DIM = 4096
    }

    // ── 长驻 server（方案 A）流式回传状态 ──
    // 后台 Python 线程把 stdout/stderr 逐行经 EventChannel 发回；在 Dart 端
    // 订阅前产生的行先缓存，订阅后一次性 flush，避免 PORT: 行丢失。
    private var streamSink: EventChannel.EventSink? = null
    private val streamBuffer = mutableListOf<Map<String, Any>>()
    private val longRunning = AtomicBoolean(false)
    private var longThread: Thread? = null

    // ── 常驻进程 stdin 队列（stdin 双向流规划 §4.2）──
    // Python 侧注入的 queue.Queue 的 PyObject 引用；writeStdin 时 put 数据，
    // 使 Python 脚本的 `for line in sys.stdin` 阻塞读到。单实例（当前只支持
    // 一个常驻进程）。跨线程访问由 Chaquopy GIL 串行化，线程安全。
    private var stdinQueue: com.chaquo.python.PyObject? = null

    // ── Chaquopy 资源路径缓存（避免每次递归遍历文件系统）──
    private val assetPathCache = mutableMapOf<String, String?>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "runScript") {
                    // Python 执行可能耗时，放到后台线程，避免阻塞 UI（ANR）。
                    Thread {
                        try {
                            val resp = runScript(
                                entry = call.argument<String>("entry") ?: "",
                                args = call.argument<List<String>>("args") ?: emptyList(),
                                stdinJson = call.argument<Map<String, Any>>("stdinJson"),
                                workingDirectory = call.argument<String>("workingDirectory"),
                                pythonPath = call.argument<String>("pythonPath"),
                            )
                            runOnUiThread { result.success(resp) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("PY_RUNNER", e.message, e.stackTraceToString())
                            }
                        }
                    }.start()
                } else if (call.method == "startLongServer") {
                    // 长驻 HTTP server（方案 A）：后台线程起 Chaquopy，stdout 经
                    // EventChannel('evergreen/python_stream') 逐行回传（含 PORT: 行），
                    // 使 DataSourceLoader 原样复用端口探测 / /health / {port} 协议。
                    Thread {
                        try {
                            longRunning.set(true)
                            longThread = Thread.currentThread()
                            startLongServer(
                                entry = call.argument<String>("entry") ?: "",
                                args = call.argument<List<String>>("args") ?: emptyList(),
                                workingDirectory = call.argument<String>("workingDirectory"),
                                preferredPort = call.argument<Int>("preferredPort") ?: 0,
                                pythonPath = call.argument<String>("pythonPath"),
                            )
                        } catch (e: Exception) {
                            emit("stderr", "startLongServer error: ${e.message}")
                            emitExit(1)
                        } finally {
                            longRunning.set(false)
                        }
                    }.start()
                    result.success(null)
                } else if (call.method == "stopLongServer") {
                    // 请求停止长驻 server：置标志 + 中断后台线程（尽力而为）。
                    // 同时向 stdin 队列 put 哨兵（None），触发 Python 侧
                    // `for line in sys.stdin` 收到 EOFError 而结束，避免阻塞残留。
                    stdinQueue?.callAttr("put", null)
                    stdinQueue = null
                    longRunning.set(false)
                    longThread?.interrupt()
                    longThread = null
                    result.success(null)
                } else if (call.method == "writeStdin") {
                    // stdin 双向流：把 Dart 侧写入的数据送入 Python 常驻进程的
                    // stdin 队列。fire-and-forget，写入即可（Python 侧异步读）。
                    val data = call.argument<String>("data") ?: ""
                    val q = stdinQueue
                    if (q == null) {
                        result.error("NO_STDIN", "常驻进程未就绪，请先 startLongServer", null)
                    } else {
                        q.callAttr("put", data)
                        result.success(null)
                    }
                } else if (call.method == "getAssetPath") {
                    // 返回 Chaquopy 资源在设备文件系统上的绝对路径。
                    // 不依赖硬编码路径，递归搜索 filesDir/chaquopy/ 子树。
                    val name = call.argument<String>("name") ?: ""
                    result.success(resolveAssetPath(name))
                } else {
                    result.notImplemented()
                }
            }

        // ── PDF 预渲染通道（Task R3-6）──
        // 对应 Dart 侧 VisionPdfPreprocess（lib/core/agent/tools/vision_pdf_preprocess.dart）。
        // 协议：invokeMethod('renderPdfToPngs', { pdfPath, outputDir, dpi })
        //   → Future<Map> { pages: [绝对路径…], outputDir: String }
        // 渲染可能耗时（数百页），放后台线程避免阻塞 UI（与 runScript 同模式）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PDF_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "renderPdfToPngs") {
                    Thread {
                        try {
                            val resp = renderPdfToPngs(
                                pdfPath = call.argument<String>("pdfPath") ?: "",
                                outputDir = call.argument<String>("outputDir") ?: "",
                                dpi = (call.argument<Number>("dpi")?.toDouble()) ?: 150.0,
                            )
                            runOnUiThread { result.success(resp) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("PDF_RENDER", e.message, e.stackTraceToString())
                            }
                        }
                    }.start()
                } else {
                    result.notImplemented()
                }
            }

        // 长驻 server stdout/stderr 流式通道：Dart 端订阅后，原缓冲的行一次性 flush。
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, STREAM_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    synchronized(streamBuffer) {
                        streamSink = events
                        for (m in streamBuffer) events?.success(m)
                        streamBuffer.clear()
                    }
                }
                override fun onCancel(arguments: Any?) {
                    synchronized(streamBuffer) { streamSink = null }
                }
            })
    }

    /// 递归搜索 Chaquopy 提取目录，返回指定文件名的绝对路径。
    /// 结果缓存于 [assetPathCache]，避免重复遍历文件系统。
    private fun resolveAssetPath(name: String): String? {
        assetPathCache[name]?.let { return it }

        val chaquopyDir = File(applicationContext.filesDir, "chaquopy")
        if (!chaquopyDir.exists()) {
            Log.w("P3NATIVE", "resolveAssetPath: $name — chaquopy dir not found")
            assetPathCache[name] = null
            return null
        }
        val found = chaquopyDir.walkTopDown().firstOrNull { it.isFile && it.name == name }
        if (found != null) {
            Log.d("P3NATIVE", "resolveAssetPath: $name -> ${found.absolutePath}")
            assetPathCache[name] = found.absolutePath
            return found.absolutePath
        }
        Log.w("P3NATIVE", "resolveAssetPath: $name not found under $chaquopyDir")
        assetPathCache[name] = null
        return null
    }

    /// 从 CLI 参数列表中提取 --project-root <value>。
    private fun extractProjectRoot(args: List<String>): String? {
        for (i in 0 until args.size - 1) {
            if (args[i] == "--project-root") return args[i + 1]
        }
        return null
    }

    /// 从 CLI 参数列表中提取 --greenix-config <value>。
    /// 对应 Dart 侧 [greenixConfigPath]（greenix_path.dart），即
    /// `.greenix/config.json` 的精确绝对路径。
    private fun extractGreenixConfig(args: List<String>): String? {
        for (i in 0 until args.size - 1) {
            if (args[i] == "--greenix-config") return args[i + 1]
        }
        return null
    }

    /// 生成环境变量注入代码（弥补 Android Chaquopy 进程 CWD=/ 导致
    /// `_get_config()` 各策略均失败的问题）。
    ///
    /// - **PROJECT_ROOT**：供策略2（HTTP）经 `Path(PROJECT_ROOT)/'.config_port'`
    ///   找到 ConfigHttpServer 端口。
    /// - **GREENIX_CONFIG_PATH**：供策略1（本地）直接读取 `.greenix/config.json`，
    ///   不再需要启发式 `_find_greenix_config()` 路径遍历。
    ///
    /// 桌面端 SubprocessRunner 进程 CWD 在项目根附近，向上遍历能碰到这些文件；
    /// 安卓 Chaquopy 进程 CWD 是文件系统根 `/`，必须提前注入环境变量。
    ///
    /// ⚠️ 不能单独 exec 注入（Chaquopy 的 `callAttr("exec", ...)` 单参数形式
    ///   行为不确定）。必须把 env 注入代码**拼接到脚本源码前**，与脚本在同一个
    ///   exec() 调用内执行，确保 `_get_config()` 模块级调用时环境变量已就绪。
    private fun envSetupCode(projectRoot: String, greenixConfig: String?): String {
        val safeRoot = projectRoot.replace("\\", "\\\\").replace("'", "\\'")
        val lines = mutableListOf("import os")
        lines.add("os.environ['PROJECT_ROOT'] = '$safeRoot'")
        if (greenixConfig != null) {
            val safeConfig = greenixConfig.replace("\\", "\\\\").replace("'", "\\'")
            lines.add("os.environ['GREENIX_CONFIG_PATH'] = '$safeConfig'")
        }
        return lines.joinToString("\n") + "\n"
    }

    private fun runScript(
        entry: String,
        args: List<String>,
        stdinJson: Map<String, Any>?,
        workingDirectory: String?,
        pythonPath: String?,
    ): Map<String, Any> {
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
        val py = Python.getInstance()

        // 重定向 stdout / stderr 到内存缓冲，执行后回读。
        val io = py.getModule("io")
        val stdoutBuf = io.callAttr("StringIO")
        val stderrBuf = io.callAttr("StringIO")
        val sys = py.getModule("sys")
        sys["stdout"] = stdoutBuf
        sys["stderr"] = stderrBuf

        // stdin：若 Dart 侧传入 stdinJson，在 Kotlin 侧（org.json）序列化为 JSON 字符串，
        // 再喂入 StringIO，供插件 sys.stdin.read() 读取（与桌面 stdio 协议一致）。
        // ⚠️ 不能把 Java Map 直接交给 Python 的 json.dumps —— Chaquopy 会把它包装成
        //   Java HashMap 代理对象，Python json 不认识，抛 "Object of type HashMap is not
        //   JSON serializable"。故序列化必须在 Kotlin 侧完成。
        val stdinJsonStr: String? =
            if (stdinJson != null) org.json.JSONObject(stdinJson).toString() else null
        if (stdinJsonStr != null) {
            sys["stdin"] = io.callAttr("StringIO", stdinJsonStr)
        }

        // sys.argv = [entry, *args]
        val argv = py.getModule("builtins").callAttr("list")
        argv.callAttr("append", entry)
        for (a in args) argv.callAttr("append", a)
        sys["argv"] = argv

        // 将工作目录 / entry 所在目录加入模块搜索路径。
        val searchDir = if (!workingDirectory.isNullOrEmpty()) {
            workingDirectory
        } else {
            File(entry).parent ?: "."
        }
        sys.get("path")!!.callAttr("insert", 0, searchDir)

        // 平台 Python 库目录（`.greenix/scripts/`，含 evg_lib）：加入 sys.path，
        // 使 `import evg_lib` 在安卓进程内可用（对应桌面 SubprocessRunner 的
        // PYTHONPATH 注入）。
        if (!pythonPath.isNullOrEmpty()) {
            sys.get("path")!!.callAttr("insert", 0, pythonPath)
        }

        // 读取源码并执行（exec，等价于 python entry arg1 arg2）。
        // 以二进制读取源码并显式按 utf-8 解码（等价 open(entry, "r", encoding="utf-8")，
        // 避免 Chaquopy 4 参数版 callAttrKw 的复杂度）。
        val srcFile = io.callAttr("open", entry, "rb")
        val source = srcFile.callAttr("read").callAttr("decode", "utf-8").toString()
        srcFile.callAttr("close")

        // ⚠️ Android Chaquopy 进程 CWD=/，必须把 PROJECT_ROOT + GREENIX_CONFIG_PATH
        // 注入代码拼接到源码前，与脚本在同一个 exec 内执行，
        // 确保 _get_config() 模块级调用时环境变量已就绪。
        val projectRoot = extractProjectRoot(args)
        val greenixConfig = extractGreenixConfig(args)
        val sourceWithEnv = if (projectRoot != null) {
            Log.d("P3NATIVE", "injectEnv prepend: PROJECT_ROOT=$projectRoot GREENIX_CONFIG=$greenixConfig")
            envSetupCode(projectRoot, greenixConfig) + source
        } else {
            source
        }

        val globals = py.getModule("builtins").callAttr("dict")
        // 用 dict 自身的 __setitem__ 设置键（builtins 模块没有 setitem —— 那是 operator
        // 模块的函数）。__setitem__ 接受 Object，Chaquopy 自动转换 String/PyObject。
        globals.callAttr("__setitem__", "__file__", entry)
        // ⚠️ 入口脚本本就是主模块，必须注入 __name__ = "__main__"。否则脚本里
        //   if __name__ == "__main__": main() 这类守卫会因 __name__ 未定义而抛 NameError，
        //   导致 main() 永不执行（长驻 server 不打印 PORT: 即此因）。
        globals.callAttr("__setitem__", "__name__", "__main__")
        // __stdin_json__ 注入为纯 Python dict（经 json.loads 解析 Kotlin 侧序列化出的字符串，
        // 而非 Java Map 代理），使插件既能直接读取，也能对其 json.dumps 而不触发
        // "HashMap not JSON serializable"。
        if (stdinJsonStr != null) {
            val pyStdin = py.getModule("json").callAttr("loads", stdinJsonStr)
            globals.callAttr("__setitem__", "__stdin_json__", pyStdin)
        }

        var exitCode = 0
        try {
            py.getBuiltins().callAttr("exec", sourceWithEnv, globals)
        } catch (e: PyException) {
            // Python 侧异常（含 sys.exit(n) 抛出的 SystemExit）统一视为非零退出。
            // 把异常信息写入 stderr，便于 Dart 侧按既有协议读取。
            exitCode = 1
            val msg = e.message ?: e.toString()
            stderrBuf.callAttr("write", msg)
        }

        val out = stdoutBuf.callAttr("getvalue").toString()
        val err = stderrBuf.callAttr("getvalue").toString()

        val resp = HashMap<String, Any>()
        resp["stdout"] = out
        resp["stderr"] = err
        resp["exitCode"] = exitCode
        return resp
    }

    // ═══════ PDF 预渲染（Task R3-6）：系统 PdfRenderer 逐页渲染 PNG ═══════

    /**
     * 用 Android 系统内置 PdfRenderer（API 21+，零第三方依赖）把 PDF 逐页渲染为
     * PNG，写入 [outputDir]/page_%04d.png（页号零填充，vision.py 按数字排序）。
     *
     * 缩放：PdfRenderer 页面尺寸为 72dpi 点阵，按 [dpi]/72 放大（默认 150，
     * 对齐桌面 fitz dpi=150）；最长边超过 [MAX_PDF_PAGE_DIM] 时等比缩小防 OOM。
     *
     * 返回 { pages: [绝对路径…], outputDir: String }；异常向上抛，由通道处理器
     * 转 result.error（Dart 侧 fail-open：原参透传，vision.py 兜底报错）。
     */
    private fun renderPdfToPngs(pdfPath: String, outputDir: String, dpi: Double): Map<String, Any> {
        val pdfFile = File(pdfPath)
        if (!pdfFile.isFile) {
            throw IllegalArgumentException("PDF 文件不存在: $pdfPath")
        }
        val outDir = File(outputDir)
        if (!outDir.exists() && !outDir.mkdirs()) {
            throw IllegalStateException("无法创建输出目录: $outputDir")
        }

        val fd = ParcelFileDescriptor.open(pdfFile, ParcelFileDescriptor.MODE_READ_ONLY)
        val renderer = try {
            PdfRenderer(fd)
        } catch (e: Exception) {
            // PdfRenderer 构造失败（非 PDF / 损坏）：fd 不再被使用，立即关闭。
            fd.close()
            throw e
        }
        try {
            val pages = mutableListOf<String>()
            var scale = (dpi / 72.0).toFloat()
            if (scale < 1.0f) scale = 1.0f
            for (i in 0 until renderer.pageCount) {
                val page = renderer.openPage(i)
                try {
                    var w = (page.width * scale).toInt()
                    var h = (page.height * scale).toInt()
                    val maxDim = maxOf(w, h)
                    if (maxDim > MAX_PDF_PAGE_DIM) {
                        val f = MAX_PDF_PAGE_DIM.toFloat() / maxDim.toFloat()
                        w = (w * f).toInt()
                        h = (h * f).toInt()
                    }
                    if (w < 1) w = 1
                    if (h < 1) h = 1

                    val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                    // PdfRenderer 输出透明底，OCR/读图前铺白底避免黑块。
                    bmp.eraseColor(android.graphics.Color.WHITE)
                    page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)

                    val name = "page_%04d.png".format(i + 1)
                    val outFile = File(outDir, name)
                    FileOutputStream(outFile).use { os ->
                        if (!bmp.compress(Bitmap.CompressFormat.PNG, 100, os)) {
                            throw IOException("PNG 编码失败: page ${i + 1}")
                        }
                        os.flush()
                    }
                    if (outFile.length() == 0L) {
                        throw IOException("PNG 写入为空: page ${i + 1}")
                    }
                    pages.add(outFile.absolutePath)
                    bmp.recycle()
                } finally {
                    page.close()
                }
            }
            val resp = HashMap<String, Any>()
            resp["pages"] = pages
            resp["outputDir"] = outDir.absolutePath
            return resp
        } finally {
            // 资源释放：renderer.close() 会释放底层 fd，随后 fd.close() 幂等；
            // close 异常不掩盖主流程错误（渲染异常已在循环体内抛出）。
            try {
                renderer.close()
            } catch (_: Exception) {
            }
            try {
                fd.close()
            } catch (_: Exception) {
            }
        }
    }

    // ═══════ 长驻 server（方案 A）支持 ═══════

    /** 注入 Python 的逐行回调（自定义接口，规避 java.util.function.Consumer 的 API24 约束）。 */
    private interface LineSink { fun emit(line: String) }

    /** 把一行 stdout/stderr 事件发往 Dart（已订阅则直发，否则先缓冲）。 */
    private fun emitRaw(map: Map<String, Any>) {
        synchronized(streamBuffer) {
            val sink = streamSink
            // ⚠️ EventSink.success() 标注 @UiThread，必须在主线程调用。长驻 server 的
            //   stdout/stderr 回调发生在后台 Python 线程（Thread-N），直接 success() 会抛
            //   "Methods marked with @UiThread must be executed on the main thread" 导致闪退。
            //   故切回主线程投递。runOnUiThread 从后台线程调用只是 post，不会死锁。
            if (sink != null) runOnUiThread { sink.success(map) } else streamBuffer.add(map)
        }
    }

    private fun emit(stream: String, line: String) {
        emitRaw(mapOf("type" to stream, "line" to line))
    }

    private fun emitExit(code: Int) {
        emitRaw(mapOf("type" to "exit", "code" to code))
    }

    /**
 * 方案 A 长驻 server：后台线程用 Chaquopy 执行 `.py`，但 stdout/stderr 不走
 * 聚合的 StringIO（server 永不退出，StringIO 不会刷新），而是重定向到注入的
 * [LineSink] 回调，逐行经 EventChannel 流式回传。脚本按桌面协议
 * `print("PORT:xxxx", flush=True)`，Dart 侧 [DataSourceLoader] 复用端口探测逻辑。
     */
    private fun startLongServer(
        entry: String,
        args: List<String>,
        workingDirectory: String?,
        @Suppress("UNUSED_PARAMETER") preferredPort: Int,
        pythonPath: String?,
    ) {
        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
        val py = Python.getInstance()
        Log.d("P3NATIVE", "startLongServer: Python instance obtained; entry=$entry args=$args")

        // ⚠️ Android Chaquopy 进程 CWD=/，必须把 PROJECT_ROOT + GREENIX_CONFIG_PATH
        // 注入到 bootstrap 中。与脚本在同一个 exec 内执行，确保已就绪。
        val projectRoot = extractProjectRoot(args)
        val greenixConfig = extractGreenixConfig(args)
        val envPrefix = if (projectRoot != null) {
            Log.d("P3NATIVE", "injectEnv prepend(server): PROJECT_ROOT=$projectRoot GREENIX_CONFIG=$greenixConfig")
            envSetupCode(projectRoot, greenixConfig)
        } else {
            ""
        }

        // 注入 stdout/stderr 回调：Kotlin 侧收到逐行后转发 EventChannel。
        // ⚠️ 诊断：每行同时 Log，便于无 Dart 订阅时也能在 logcat 看到 Python 输出。
        val outCb = object : LineSink { override fun emit(line: String) { Log.d("P3NATIVE", "stdout> $line"); emit("stdout", line) } }
        val errCb = object : LineSink { override fun emit(line: String) { Log.d("P3NATIVE", "stderr> $line"); emit("stderr", line) } }

        // 重定向引导：定义 _CbOut/_CbErr（按 \n 缓冲切分后回调），再把 sys 流换掉。
        // ⚠️ envPrefix 在最前面：PROJECT_ROOT注入 → sys重定向 → 业务脚本。
        // 另注入 stdin 队列（stdin 双向流规划 §4.2）：_CbIn 的 readline() 从
        // queue.Queue 阻塞取数据，供脚本 `for line in sys.stdin` 使用。
        val bootstrap = envPrefix + """
import sys
class _CbOut:
    def __init__(self, cb):
        self._cb = cb
        self._buf = ""
    def write(self, s):
        self._buf += s
        while "\n" in self._buf:
            line, self._buf = self._buf.split("\n", 1)
            self._cb(line)
    def flush(self):
        if self._buf:
            self._cb(self._buf); self._buf = ""
class _CbErr:
    def __init__(self, cb):
        self._cb = cb
        self._buf = ""
    def write(self, s):
        self._buf += s
        while "\n" in self._buf:
            line, self._buf = self._buf.split("\n", 1)
            self._cb(line)
    def flush(self):
        if self._buf:
            self._cb(self._buf); self._buf = ""
import queue
_stdin_q = queue.Queue()
class _CbIn:
    def readline(self):
        s = _stdin_q.get()
        if s is None:
            raise EOFError
        return s if s.endswith("\n") else s + "\n"
    def read(self, *a):
        return self.readline()
    def __iter__(self):
        while True:
            try:
                yield self.readline()
            except EOFError:
                return
"""
        val sys = py.getModule("sys")
        val builtins = py.getModule("builtins")
        val globals = builtins.callAttr("dict")
        // 用 dict 自身的 __setitem__ 设置键（builtins 模块没有 setitem）。
        globals.callAttr("__setitem__", "__file__", entry)
        // 入口脚本即主模块：注入 __name__ = "__main__"，否则 if __name__ 守卫处
        //   NameError，main() 不执行、server 不打印 PORT:（见 runScript 同款注释）。
        globals.callAttr("__setitem__", "__name__", "__main__")
        globals.callAttr("__setitem__", "sys", sys)
        globals.callAttr("__setitem__", "_out_cb", outCb)
        globals.callAttr("__setitem__", "_err_cb", errCb)

        // exec 引导（定义 _CbOut/_CbErr/_CbIn/_stdin_q），再重定向 sys 三个流。
        builtins.callAttr("exec", bootstrap, globals)
        builtins.callAttr("exec",
            "sys.stdout = _CbOut(_out_cb)\nsys.stderr = _CbErr(_err_cb)\nsys.stdin = _CbIn()", globals)
        // 保存 stdin 队列的 PyObject 引用，供 writeStdin 写入数据。
        stdinQueue = globals.get("_stdin_q") as com.chaquo.python.PyObject

        // sys.argv = [entry, *args]
        val argv = builtins.callAttr("list")
        argv.callAttr("append", entry)
        for (a in args) argv.callAttr("append", a)
        sys["argv"] = argv

        // 工作目录 / entry 所在目录加入 sys.path。
        val searchDir = if (!workingDirectory.isNullOrEmpty()) {
            workingDirectory
        } else {
            File(entry).parent ?: "."
        }
        sys.get("path")!!.callAttr("insert", 0, searchDir)

        // 平台 Python 库目录（`.greenix/scripts/`，含 evg_lib）：加入 sys.path，
        // 使 `import evg_lib` 在安卓长驻进程内可用（对应桌面 PYTHONPATH 注入）。
        if (!pythonPath.isNullOrEmpty()) {
            sys.get("path")!!.callAttr("insert", 0, pythonPath)
        }

        // 读取源码并 exec（serve_forever 会一直阻塞，直到被 stopLongServer 中断）。
        val io = py.getModule("io")
        val srcFile = io.callAttr("open", entry, "rb")
        val source = srcFile.callAttr("read").callAttr("decode", "utf-8").toString()
        srcFile.callAttr("close")

        try {
            Log.d("P3NATIVE", "exec begin (serve_forever blocks until stopLongServer)")
            builtins.callAttr("exec", source, globals)
            Log.d("P3NATIVE", "exec returned (serve_forever exited)")
            emitExit(0)
        } catch (e: PyException) {
            Log.e("P3NATIVE", "exec PyException: ${e.message}", e)
            emit("stderr", e.message ?: e.toString())
            emitExit(1)
        }
    }
}
