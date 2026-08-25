package com.liveline.mobile

import com.facebook.react.ReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.uimanager.ViewManager
import com.margelo.nitro.liveline.views.HybridLivelineManager

/**
 * Registers the Nitro-generated `Liveline` view manager with React Native, so
 * the `<Liveline>` component resolves on Android. Picked up by autolinking.
 */
class LivelinePackage : ReactPackage {
    override fun createNativeModules(reactContext: ReactApplicationContext): List<NativeModule> =
        emptyList()

    override fun createViewManagers(reactContext: ReactApplicationContext): List<ViewManager<*, *>> =
        listOf(HybridLivelineManager())
}
