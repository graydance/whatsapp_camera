#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint whatsapp_camera.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'whatsapp_camera'
  s.version          = '1.0.0'
  s.summary          = 'A Flutter plugin for WhatsApp-style camera with gallery selection.'
  s.description      = <<-DESC
This is a package to open a camera along with a photo gallery, to simplify the steps of the end user.
It provides native camera detection capabilities using Platform Channels.
                       DESC
  s.homepage         = 'https://github.com/welitonsousa/whatsapp_camera'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Weliton Sousa' => 'https://github.com/welitonsousa' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end

