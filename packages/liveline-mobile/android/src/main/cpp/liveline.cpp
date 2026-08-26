// Nitro's required JNI entrypoint. Loading the "LivelineMobile" library invokes
// this, which registers every generated Hybrid Object AND the view's Fabric
// component descriptor via registerAllNatives(). Without it nothing is
// registered, so RN can't find the "Liveline" Fabric component and falls back to
// the legacy interop path (props never reach native). See LivelineMobileOnLoad.hpp.
#include <fbjni/fbjni.h>
#include <jni.h>

#include "LivelineMobileOnLoad.hpp"

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
  return facebook::jni::initialize(vm, [] {
    margelo::nitro::liveline::registerAllNatives();
  });
}
