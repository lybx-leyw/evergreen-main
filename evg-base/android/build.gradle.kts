// P1b：Chaquopy 在 app/build.gradle.kts 的 plugins {} 块内声明并应用
// （id("com.chaquo.python") version "17.0.0"），由 Maven Central 的
// com.chaquo.python.gradle.plugin marker 解析；其 Python 运行时亦在 Maven Central。
// 阿里云镜像前置加速（无 VPN 环境下 Maven Central / Google 直连极慢）。
allprojects {
    repositories {
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
