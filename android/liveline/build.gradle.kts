import com.vanniktech.maven.publish.SonatypeHost

plugins {
    id("com.android.library")
    kotlin("android")
    id("com.vanniktech.maven.publish")
    signing
}

android {
    namespace = "com.liveline"
    compileSdk = 34

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    // `api`, not `implementation`: liveline's public API exposes core types
    // (LivelineCandle, LivelineTheme, …), so consumers need them transitively.
    api(project(":liveline-core"))
}

// Central requires signed artifacts. Only sign once a real GPG key is set, so
// publishToMavenLocal dry-runs work before the key exists. Signs via the local
// gpg agent (signing.gnupg.keyName from ~/.gradle/gradle.properties).
val gpgKey = providers.gradleProperty("signing.gnupg.keyName").orNull
val signingEnabled = !gpgKey.isNullOrBlank() && gpgKey != "PASTE_GPG_KEY_ID"
if (signingEnabled) {
    signing { useGpgCmd() }
}

mavenPublishing {
    publishToMavenCentral(SonatypeHost.CENTRAL_PORTAL)
    if (signingEnabled) signAllPublications()

    coordinates(
        rootProject.extra["livelineGroup"] as String,
        "liveline",
        rootProject.extra["livelineVersion"] as String,
    )

    pom {
        name.set("liveline")
        description.set("Native Android renderer for the Liveline real-time line/candlestick chart.")
        url.set("https://github.com/lewiscasewell/liveline-mobile")
        licenses {
            license {
                name.set("MIT License")
                url.set("https://opensource.org/licenses/MIT")
            }
        }
        developers {
            developer {
                id.set("lewiscasewell")
                name.set("Lewis Casewell")
                url.set("https://github.com/lewiscasewell")
            }
        }
        scm {
            url.set("https://github.com/lewiscasewell/liveline-mobile")
            connection.set("scm:git:git://github.com/lewiscasewell/liveline-mobile.git")
            developerConnection.set("scm:git:ssh://git@github.com/lewiscasewell/liveline-mobile.git")
        }
    }
}
