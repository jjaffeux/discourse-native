Pod::Spec.new do |s|
  s.name = 'discourse_video_optimizer'
  s.version = '0.1.0'
  s.summary = 'Optional native video preparation for Discourse uploads.'
  s.description = s.summary
  s.homepage = 'https://github.com/discourse'
  s.license = { :type => 'MIT', :file => '../../../LICENSE' }
  s.author = 'Discourse'
  s.source = { :path => '.' }
  s.source_files = 'discourse_video_optimizer/Sources/discourse_video_optimizer/**/*.swift'
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
