allprojects {
    repositories {
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

// AGP 的 lint 在 image_picker_android 的 ExifDataCopier.java 上崩掉
// （CommentDetector 触发 NoSuchMethodError: List.removeLast()，是 AGP/JDK
// 兼容性 bug，不是代码问题）。关掉 release 的 lintVital 检查，
// 否则 assembleRelease 永远过不了。Dart 侧的 flutter analyze 已覆盖静态检查。
subprojects {
    tasks.matching { it.name.startsWith("lintVital") }.configureEach {
        enabled = false
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
