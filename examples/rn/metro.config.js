// Monorepo Metro config: watch the repo root so the local
// react-native-liveline-mobile package resolves, and force a single instance
// of shared deps (react, react-native, react-native-nitro-modules) from this
// app's node_modules — otherwise the Nitro view registers in one module
// instance and the renderer reads another ("view config … undefined").
const { getDefaultConfig } = require('expo/metro-config')
const path = require('path')

const projectRoot = __dirname
const monorepoRoot = path.resolve(projectRoot, '../..')

const config = getDefaultConfig(projectRoot)

config.watchFolders = [monorepoRoot]
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(monorepoRoot, 'node_modules'),
]

// Force singletons to this app's copy, so the local package (which has its own
// node_modules for TypeScript/codegen) doesn't pull a second instance —
// otherwise the Nitro view registers in one instance and the renderer reads
// another ("view config … undefined").
const singletons = ['react', 'react-native', 'react-native-nitro-modules']
const upstreamResolveRequest = config.resolver.resolveRequest
config.resolver.resolveRequest = (context, moduleName, platform) => {
  if (singletons.some((s) => moduleName === s || moduleName.startsWith(s + '/'))) {
    return context.resolveRequest(
      { ...context, originModulePath: path.join(projectRoot, 'index.ts') },
      moduleName,
      platform
    )
  }
  return (upstreamResolveRequest ?? context.resolveRequest)(context, moduleName, platform)
}

module.exports = config
