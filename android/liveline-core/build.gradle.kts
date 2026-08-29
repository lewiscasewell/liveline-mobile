import com.vanniktech.maven.publish.SonatypeHost

plugins {
    kotlin("jvm")
    id("com.vanniktech.maven.publish")
    signing
}

repositories {
    mavenCentral()
}

dependencies {
    testImplementation(kotlin("test"))
}

kotlin {
    jvmToolchain(17)
}

tasks.test {
    useJUnitPlatform()
}

// Central requires signed artifacts. Sign locally via the gpg agent
// (signing.gnupg.keyName) or, in CI, via an in-memory key (signingInMemoryKey,
// which vanniktech picks up automatically). Neither present ⇒ unsigned, so
// publishToMavenLocal dry-runs still work before any key exists.
val gpgKeyName = providers.gradleProperty("signing.gnupg.keyName").orNull
val useLocalGpg = !gpgKeyName.isNullOrBlank() && gpgKeyName != "PASTE_GPG_KEY_ID"
val hasInMemoryKey = !providers.gradleProperty("signingInMemoryKey").orNull.isNullOrBlank()
val signingEnabled = useLocalGpg || hasInMemoryKey
if (useLocalGpg) {
    signing { useGpgCmd() }
}

mavenPublishing {
    publishToMavenCentral(SonatypeHost.CENTRAL_PORTAL)
    if (signingEnabled) signAllPublications()

    coordinates(
        rootProject.extra["livelineGroup"] as String,
        "liveline-core",
        rootProject.extra["livelineVersion"] as String,
    )

    pom {
        name.set("liveline-core")
        description.set("Platform-agnostic maths + model for the Liveline real-time chart engine.")
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
