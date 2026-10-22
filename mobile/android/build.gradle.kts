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
    if (name == "video_player_android") {
        // The plugin's isolated release-lint classpath asks for collection 1.2;
        // the compatible 1.4.2 implementation is already in the local cache.
        // Align that old request without constraining future plugin upgrades.
        configurations.configureEach {
            resolutionStrategy.eachDependency {
                if (requested.group == "androidx.collection" &&
                    requested.name == "collection" && requested.version == "1.2.0") {
                    useVersion("1.4.2")
                    because("Keep video player release validation available offline")
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
