allprojects {
    repositories {
        maven("https://maven.aliyun.com/repository/public")
        maven("https://maven.aliyun.com/repository/google")
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

// تنظیم compileSdk روی 36 برای پکیج‌های وابسته (قبل از ارزیابی app)
subprojects {
    if (project.name != "app") {
        afterEvaluate {
            if (project.hasProperty("android")) {
                val androidExtension = project.extensions.findByName("android")
                if (androidExtension != null) {
                    try {
                        val method = androidExtension.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                        method.invoke(androidExtension, 36)
                    } catch (_: Exception) {
                        try {
                            val method = androidExtension.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType)
                            method.invoke(androidExtension, 36)
                        } catch (_: Exception) {}
                    }
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}