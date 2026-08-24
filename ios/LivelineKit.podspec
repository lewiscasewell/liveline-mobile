Pod::Spec.new do |s|
  s.name             = 'LivelineKit'
  s.version          = '0.0.0'
  s.summary          = 'Real-time line/candle chart engine for iOS (Swift).'
  s.description       = 'Native Swift implementation of the liveline chart. Consumed by react-native-liveline-mobile via Nitro Modules.'
  s.homepage         = 'https://github.com/lewiscasewell/liveline-mobile'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Lewis Casewell' => 'lewiscasewell@hotmail.co.uk' }
  s.source           = { :git => 'https://github.com/lewiscasewell/liveline-mobile.git', :tag => s.version.to_s }
  s.platforms        = { :ios => '16.0' }
  s.swift_version    = '5.9'
  # Compile the LivelineKit Swift Package sources as a standalone module so the
  # RN binding can `import LivelineKit` (its types would otherwise collide with
  # the Nitrogen-generated ones).
  s.source_files     = 'Sources/LivelineKit/**/*.swift'
end
