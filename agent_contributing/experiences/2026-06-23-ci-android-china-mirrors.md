---
task_type: bug-fix
tags: [ci, github-actions, android, gradle, mirrors, kotlin, release]
files_touched:
  - android/settings.gradle.kts
  - android/build.gradle.kts
  - android/gradle/wrapper/gradle-wrapper.properties
  - .github/workflows/release.yml
difficulty: medium
outcome: success
date: 2026-06-23
related_pr: 2026-06-23-palace-core.md
---

## 做了什么

修复 Android CI 构建在 GitHub Actions 上因中国镜像仓库不可达导致的构建失败，同时添加 Android APK 到 Release 流程。

## 关键决策

1. **Gradle 分发 URL 改回官方**：`gradle-wrapper.properties` 指向腾讯云镜像 (`mirrors.cloud.tencent.com`)，CI runner 在美国无法下载。改为 `services.gradle.org` 官方地址。
2. **仓库顺序标准化**：`pluginManagement` 和 `allprojects` 中标准仓库 (`google()`, `mavenCentral()`, `gradlePluginPortal()`) 前置，aliyun 镜像后置作后备。CI 优先走标准仓库，国内开发者 fallback 镜像。
3. **Release 双平台**：`build-android` 和 `build-windows` 并行，`release` job 等两者完成后同时挂载两个附件。

## 踩过的坑

### 1. Kotlin 插件在 aliyun 镜像中缺失
- **现象**：`org.jetbrains.kotlin.android:2.1.0` 在 `pluginManagement` 中解析失败
- **根因**：`settings.gradle.kts` 的 `pluginManagement.repositories` 中 aliyun 镜像在 `gradlePluginPortal()` 之前，aliyun 的 `gradle-plugin` 仓库没有 Kotlin 2.1.0
- **解决**：`google()` → `mavenCentral()` → `gradlePluginPortal()` 前置，aliyun 镜像后置

### 2. Tencent Cloud Gradle 镜像不可达
- **现象**：CI 无法下载 `gradle-8.11.1-all.zip`
- **根因**：`mirrors.cloud.tencent.com` 在 GitHub Actions 美国 runner 上响应极慢或超时
- **解决**：改为 `services.gradle.org/distributions/gradle-8.11.1-all.zip`

### 3. `workflow_dispatch` 不触发 Release
- **根因**：`release` job 有 `if: startsWith(github.ref, 'refs/tags/v')`，手动触发时 `github.ref` 是 `refs/heads/#`
- **解决**：维持该 guard，手动触发只跑 test + build，发布仅由 tag push 触发

## 可复用的模式

### Android CI 仓库配置模板
```kotlin
// settings.gradle.kts - pluginManagement
pluginManagement {
    repositories {
        google()           // 标准仓库优先（CI 可用）
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://maven.aliyun.com/repository/google") }       // 镜像后备（国内开发者）
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
}
```

```kotlin
// build.gradle.kts - allprojects
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/gradle-plugin") }
    }
}
```

```properties
# gradle-wrapper.properties
distributionUrl=https\://services.gradle.org/distributions/gradle-8.11.1-all.zip
```

### Release 双平台附件命名
- Windows: `EvergreenSetup-{VERSION}-Win.exe`
- Android: `Evergreen-{VERSION}-android.apk`
- 标题: `Evergreen v{VERSION}`（由 `name: Evergreen ${{ github.ref_name }}` 渲染）

## 注意事项

- GitHub Actions 取**默认分支 (main)** 上的 `release.yml`，其他分支的 workflow 更新必须在合并后才生效
- Android 构建需要 JDK 17（`actions/setup-java@v4` with `java-version: '17'`）
- `local.properties` 不应提交到 Git（已在 `.gitignore`），CI 通过环境变量 `ANDROID_HOME` 和 `FLUTTER_ROOT` 配置
- 阿里云/腾讯云镜像在国内开发环境下体验更好，但在 CI 中会导致构建失败。保留镜像作为 fallback 而非删除，兼顾两者
