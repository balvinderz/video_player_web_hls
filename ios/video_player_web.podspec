Pod::Spec.new do |s|
    s.name             = 'video_player_web_hls'
    s.version          = '0.1.5'
    s.summary          = 'No-op implementation of video_player_web_hls web plugin to avoid build issues on iOS'
    s.description      = <<-DESC
  temp fake video_player_web_hls plugin
                         DESC
    s.homepage         = 'https://github.com/balvinderz/video_player_web_hls'
    s.license          = { :file => '../LICENSE' }
    s.author           = { 'Balvinder Singh' => 'balvindersi2@gmail.com' }
    s.source           = { :path => '.' }
    s.source_files = 'Classes/**/*'
    s.public_header_files = 'Classes/**/*.h'
    s.dependency 'Flutter'
  
    s.ios.deployment_target = '8.0'
  end