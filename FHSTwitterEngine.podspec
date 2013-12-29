Pod::Spec.new do |s|
  s.name     = 'FHSTwitterEngine'
  s.version  = '1.7'
  s.platform = :ios, '5.1'
  s.license  = 'MIT'
  s.summary  = 'The synchronous Twitter engine that doesn’t suck!! USE THE MASTER BRANCH'
  s.homepage = 'https://github.com/tuoxie007/FHSTwitterEngine'
  s.author   = { 'Jason Hsu' => 'support@tuoxie.me' }
  s.source   = { :git => 'https://github.com/tuoxie007/FHSTwitterEngine.git', :tag => s.version.to_s }
  s.description = 'The synchronous Twitter engine that doesn’t suck!! USE THE MASTER BRANCH'
  s.source_files = 'FHSTwitterEngine/*.{h,m}'
  s.framework    = ['Foundation', 'UIKit', 'CoreGraphics', 'SystemConfiguration']
  s.requires_arc = false 
  s.subspec 'OAuthConsumer' do |oa|
    s.source_files = 'FHSTwitterEngine/OAuthConsumer/**/*.{h,m}'
  end
end
