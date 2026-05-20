buildscript {
    repositories {
        google()
        mavenCentral()
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
        maven {
            url = uri("file:///D:/flutter/packages/flutter_tools/gradle/flutter_repo")
        }
        maven {
            url = uri("https://mirrors.tuna.tsinghua.edu.cn/flutter/download.flutter.io")
        }
    }
}

tasks.register("clean", Delete::class) {
    delete(rootProject.layout.buildDirectory)
}