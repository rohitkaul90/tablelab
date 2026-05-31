buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.google.gms:google-services:4.4.2")
        classpath("com.google.firebase:firebase-crashlytics-gradle:3.0.3")
    }
}

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

// gradle.afterProject fires per-project immediately after its build script
// finishes, before task configuration — safe to override compileSdk here.
// Forces file_picker 8.x (hardcoded at 34) to 36 so the
// flutter_plugin_android_lifecycle AAR metadata check passes.
gradle.afterProject {
    extensions.findByType<com.android.build.gradle.LibraryExtension>()?.apply {
        compileSdkVersion(36)
    }
}

// KGP 2.3+ dropped support for Kotlin language/api version 1.6.
// Force all plugin subprojects (posthog_flutter, share_plus, etc.) to 2.0.
gradle.afterProject {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            languageVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0)
            apiVersion.set(org.jetbrains.kotlin.gradle.dsl.KotlinVersion.KOTLIN_2_0)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
