allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// The build directory redirection was causing issues with cross-drive relative paths.
// Reverting to default build directory location.
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
