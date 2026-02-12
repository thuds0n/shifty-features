# Uncomment the next line to define a global platform for your project
platform :osx, '14.0'

def patch_axswift_compatibility(installer)
  file = File.join(installer.sandbox.root.to_s, "AXSwift/Sources/Error.swift")
  return unless File.exist?(file)

  original = File.read(file)
  updated = original.dup
  unless updated.include?("extension AXError: Swift.Error {}")
    updated = updated.sub(
      "import Foundation\n",
      "import Foundation\n\nextension AXError: Swift.Error {}\n"
    )
  end
  updated = updated.gsub(
    "extension AXError: CustomStringConvertible {",
    "extension AXError: @retroactive CustomStringConvertible {"
  )
  updated = updated.gsub(
    "extension AXError: @retroactive Swift.Error {}",
    "extension AXError: Swift.Error {}"
  )
  return if updated == original

  File.chmod(0o644, file) rescue nil
  File.write(file, updated)
end

target 'Shifty' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!

  pod 'AXSwift'
  pod 'MASPreferences+Shifty'
  pod 'PublicSuffix'
  pod 'Sparkle'
  pod 'SwiftLog'

end

target 'ShiftyTests' do
  inherit! :search_paths
end

post_install do |installer|
  patch_axswift_compatibility(installer)

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '14.0'

      if target.name == 'AXSwift'
        config.build_settings['SWIFT_SUPPRESS_WARNINGS'] = 'YES'
      end
    end
  end
end
