require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "LivelineMobile"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = "https://github.com/lewiscasewell/liveline-mobile"
  s.license      = "MIT"
  s.author       = { "Lewis Casewell" => "lewiscasewell@hotmail.co.uk" }
  s.platforms    = { :ios => "16.0" }
  s.source       = { :git => "https://github.com/lewiscasewell/liveline-mobile.git", :tag => "#{s.version}" }
  s.swift_version = "5.9"

  # Compile the binding in Swift 5 language mode: Nitro applies view props on
  # the main thread, but its `HybridView` protocol is not `@MainActor`, so
  # forwarding to the `@MainActor` LivelineView would otherwise trip Swift 6
  # strict-concurrency errors. (LivelineKit itself stays on its own default.)
  s.pod_target_xcconfig = { "SWIFT_VERSION" => "5.0" }

  # The thin Nitro HybridView shell (wraps LivelineKit's LivelineView).
  s.source_files = "ios/**/*.{swift}"

  # The native chart engine, as its own module (avoids type-name collisions
  # with the Nitrogen-generated types).
  s.dependency "LivelineKit"

  # React Native / Fabric dependencies for the view.
  install_modules_dependencies(s)

  # All Nitrogen-generated C++/Swift specs + NitroModules dependency.
  load "nitrogen/generated/ios/LivelineMobile+autolinking.rb"
  add_nitrogen_files(s)
end
