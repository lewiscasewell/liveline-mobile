plugins {
    id("com.android.application") version "8.7.3" apply false
    id("com.android.library") version "8.7.3" apply false
    kotlin("android") version "2.0.21" apply false
    kotlin("jvm") version "2.0.21" apply false
    id("com.vanniktech.maven.publish") version "0.30.0" apply false
}

// Single source of truth for the published version: the npm package.json.
// The podspec reads the same file, so one bump (npm version) moves all three.
val livelineVersion: String = run {
    val pkg = file("../packages/liveline-mobile/package.json").readText()
    Regex(""""version"\s*:\s*"([^"]+)"""").find(pkg)!!.groupValues[1]
}
extra["livelineVersion"] = livelineVersion
extra["livelineGroup"] = "io.github.lewiscasewell"
