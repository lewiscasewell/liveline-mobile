// Tells React Native autolinking exactly how to register the Android view-
// manager package. Nitro sets up the HybridObjects, but the `Liveline` *view*
// is registered by `LivelinePackage` (a `ReactPackage`), which must appear in
// the app's package list — otherwise Fabric can't resolve `<Liveline>` and
// throws "Can't find ViewManager 'Liveline'". Declaring it here makes the link
// deterministic rather than relying on source scanning, which doesn't reliably
// find the class across every package-manager node_modules layout.
module.exports = {
  dependency: {
    platforms: {
      android: {
        packageImportPath: 'import com.liveline.mobile.LivelinePackage',
        packageInstance: 'new LivelinePackage()',
      },
    },
  },
}
