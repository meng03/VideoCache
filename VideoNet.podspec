Pod::Spec.new do |s|
  s.name             = 'VideoNet'
  s.version          = '0.9.2'
  s.summary          = '接管系统VideoPlayer的数据加载逻辑.'
  s.description      = <<-DESC
接管系统VideoPlayer的数据加载逻辑，用户用户体验
                       DESC
 
  s.homepage         = 'https://github.com/meng03/VideoCache'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'mengbingchuan' => 'mengbingchuan@36kr.com' }
  s.source           = { :git => 'https://github.com/meng03/VideoCache.git', :tag => s.version.to_s }
 
  s.ios.deployment_target = '10.0'
  s.source_files = 'VideoPlayer/cache/*.swift'
 
end
