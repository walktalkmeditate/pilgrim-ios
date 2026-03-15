project 'Pilgrim.xcodeproj'
platform :ios, '18.0'

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
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '18.0'
    end
  end

  # Inject Secrets.xcconfig into Pilgrim target xcconfigs
  secrets_include = '#include? "../../Secrets.xcconfig"'
  Dir.glob('Pods/Target Support Files/Pods-Pilgrim/*.xcconfig').each do |path|
    content = File.read(path)
    unless content.include?(secrets_include)
      File.write(path, "#{secrets_include}\n#{content}")
    end
  end
end