Pod::Spec.new do |s|
  s.name             = 'discourse_voice'
  s.version          = '1.0.0'
  s.summary          = 'Native Voice adapters for discourse_native.'
  s.description      = <<-DESC
CallKit and audio-session integration for the always-bundled Voice feature.
                       DESC
  s.homepage         = 'https://github.com/discourse/discourse-native'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Discourse' => 'team@discourse.org' }
  s.source           = { :path => '.' }
  s.source_files     = 'discourse_voice/Sources/discourse_voice/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'AVFoundation', 'CallKit'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }

  s.test_spec 'Tests' do |test_spec|
    test_spec.source_files =
      'discourse_voice/Tests/discourse_voiceTests/**/*.swift'
    test_spec.dependency 'Flutter'
  end
end
