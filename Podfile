project 'Pilgrim.xcodeproj'
platform :ios, '16.0'

def data_pods
  pod 'Cache'
  pod 'CombineExt'
  pod 'CoreStore'
  pod 'CoreGPX'
end

target 'Pilgrim' do
  use_frameworks!

  data_pods

  target 'UnitTests' do
    inherit! :search_paths
  end

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
    end
  end
end