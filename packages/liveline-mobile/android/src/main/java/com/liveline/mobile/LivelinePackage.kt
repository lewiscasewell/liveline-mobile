package com.liveline.mobile

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager
import com.margelo.nitro.liveline.LivelineMobileOnLoad
import com.margelo.nitro.liveline.views.HybridLivelineManager

/**
 * Registers the Nitro-generated `Liveline` view manager with React Native, so
 * the `<Liveline>` component resolves on Android. Picked up by autolinking.
 */
class LivelinePackage : ReactPackage {
    init {
        // Load the native library at app startup (packages are created during
        // ReactInstance init, before any surface commits). This runs the C++
        // JNI_OnLoad → registerAllNatives(), which registers the "Liveline"
        // Fabric component descriptor. It must be registered BEFORE the first
        // <Liveline> mounts, or Fabric resolves it as a legacy view and props
        // never reach native. Loading it lazily on first view construction is
        // too late.
        LivelineMobileOnLoad.initializeNative()
    }

    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> =
        emptyList()

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> =
        listOf(HybridLivelineManager())
}
