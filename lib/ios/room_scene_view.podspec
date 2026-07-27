Pod::Spec.new do |s|
  s.name             = 'room_scene_view'
  s.version          = '0.0.1'
  s.summary          = 'SceneKit USDZ viewer with tap hit-test.'
  s.description      = 'Displays a RoomPlan USDZ in SCNView and reports tapped node names.'
  s.homepage         = 'https://github.com/dazzle8313/room_scene_view'
  s.license          = { :type => 'MIT' }
  s.author           = { 'dazzle8313' => 'dazzle8313@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '17.0'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
