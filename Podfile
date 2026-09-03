project 'Pilgrim.xcodeproj'
platform :ios, '18.0'

def data_pods
  pod 'Cache'
  pod 'CombineExt'
  pod 'CoreStore'
  pod 'CoreGPX'
  pod 'ZIPFoundation'
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

  # CombineExt 1.8.0's DemandBuffer reads `completion` outside its lock and
  # traps when a value lands after a cancel — reachable when a walk ends
  # with a location sample in flight. Pods are checked in, so the patched
  # source is in git; this re-applies it after any `pod install`.
  demand_buffer = 'Pods/CombineExt/Sources/Common/DemandBuffer.swift'
  if File.exist?(demand_buffer)
    src = File.read(demand_buffer)
    unless src.include?('Pilgrim patch')
      src = src.sub(
        "    func buffer(value: S.Input) -> Subscribers.Demand {\n        precondition(self.completion == nil,\n                     \"How could a completed publisher sent values?! Beats me 🤷‍♂️\")\n        lock.lock()\n        defer { lock.unlock() }\n",
        "    func buffer(value: S.Input) -> Subscribers.Demand {\n        lock.lock()\n        defer { lock.unlock() }\n\n        // Pilgrim patch (see Podfile post_install): `completion` used to be\n        // read here OUTSIDE the lock and trapped when non-nil. A relay\n        // cancelled on one thread while another is still delivering a value\n        // — ending a walk with a location sample in flight — races that\n        // read. A value that arrives after completion is dropped instead.\n        guard self.completion == nil else { return .none }\n"
      )
      src = src.sub(
        "    func complete(completion: Subscribers.Completion<S.Failure>) {\n        precondition(self.completion == nil,\n                     \"Completion have already occured, which is quite awkward 🥺\")\n\n        self.completion = completion\n",
        "    func complete(completion: Subscribers.Completion<S.Failure>) {\n        lock.lock()\n        defer { lock.unlock() }\n\n        // Pilgrim patch: a second completion is ignored rather than trapped.\n        guard self.completion == nil else { return }\n\n        self.completion = completion\n"
      )
      raise 'CombineExt DemandBuffer patch did not apply — the pod changed; update Podfile post_install' unless src.include?('Pilgrim patch')
      File.write(demand_buffer, src)
    end
  end

  # Inject Secrets.xcconfig into Pilgrim target xcconfigs
  secrets_include = '#include? "../../../Secrets.xcconfig"'
  Dir.glob('Pods/Target Support Files/Pods-Pilgrim/*.xcconfig').each do |path|
    content = File.read(path)
    unless content.include?(secrets_include)
      File.write(path, "#{secrets_include}\n#{content}")
    end
  end
end