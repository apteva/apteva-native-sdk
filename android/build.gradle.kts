plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.plugin.serialization")
    id("maven-publish")
}

group = "ai.apteva"
version = providers.gradleProperty("aptevaSdkVersion").getOrElse("1.2.0")

android {
    namespace = "ai.apteva.client"
    compileSdk = 37

    defaultConfig {
        minSdk = 28
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.11.0")
    implementation("com.squareup.okhttp3:okhttp:5.4.0")
    testImplementation("junit:junit:4.13.2")
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                groupId = "ai.apteva"
                artifactId = "native-sdk"
                version = project.version.toString()
                from(components["release"])
            }
        }
        repositories {
            val publishURL = providers.gradleProperty("aptevaSdkPublishUrl").orNull
                ?: System.getenv("APTEVA_SDK_PUBLISH_URL")
            if (!publishURL.isNullOrBlank()) {
                maven {
                    name = "aptevaReleases"
                    url = uri(publishURL)
                    credentials {
                        username = providers.gradleProperty("aptevaSdkPublishUser").orNull
                            ?: System.getenv("APTEVA_SDK_PUBLISH_USER")
                        password = providers.gradleProperty("aptevaSdkPublishToken").orNull
                            ?: System.getenv("APTEVA_SDK_PUBLISH_TOKEN")
                    }
                }
            }
        }
    }
}
