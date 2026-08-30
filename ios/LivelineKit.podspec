require "json"

# Single source of truth for the version: the npm package.json (same as the
# git tag and the Maven artifacts), so one bump moves everything.
package = JSON.parse(File.read(File.join(__dir__, "..", "packages", "liveline-mobile", "package.json")))

Pod::Spec.new do |s|
  s.name             = 'LivelineKit'
  s.version          = package["version"]
  s.summary          = 'Real-time line/candle chart engine for iOS (Swift).'
  s.description       = 'Native Swift implementation of the liveline chart. Consumed by liveline-mobile (React Native) via Nitro Modules.'
  s.homepage         = 'https://github.com/lewiscasewell/liveline-mobile'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Lewis Casewell' => 'lewiscasewell@hotmail.co.uk' }
  s.source           = { :git => 'https://github.com/lewiscasewell/liveline-mobile.git', :tag => "v#{s.version}" }
  s.platforms        = { :ios => '16.0' }
  s.swift_version    = '5.9'
  # Compile the LivelineKit Swift Package sources as a standalone module so the
  # RN binding can `import LivelineKit` (its types would otherwise collide with
  # the Nitrogen-generated ones).
  s.source_files     = 'Sources/LivelineKit/**/*.swift'
end
