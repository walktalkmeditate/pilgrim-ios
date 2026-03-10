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