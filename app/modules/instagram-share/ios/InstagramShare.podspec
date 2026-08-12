# 로컬 Expo 모듈의 CocoaPods 스펙.
# ⚠ 이게 없으면 expo-modules-autolinking이 모듈을 **찾기는 하는데**(search에 뜬다) pod install이
#   타깃을 만들지 않아 Podfile.lock에 아무것도 안 들어가고, 앱은 조용히 모듈 없이 빌드된다.
#   그 상태에서 requireOptionalNativeModule은 null을 돌려주므로 크래시는 없고 — 기능만 없다.
#   찾았다는 로그를 성공으로 읽으면 안 되는 자리다.
Pod::Spec.new do |s|
  s.name           = 'InstagramShare'
  s.version        = '1.0.0'
  s.summary        = 'Instagram Stories sticker share (keyed pasteboard + deep link)'
  s.description    = 'Hands a captured PNG to Instagram Stories via the keyed iOS pasteboard dictionary that RN Share cannot build.'
  s.author         = 'dogshigh'
  s.homepage       = 'https://dogshigh.app'
  s.platforms      = { :ios => '15.1' }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_COMPILATION_MODE' => 'wholemodule'
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
