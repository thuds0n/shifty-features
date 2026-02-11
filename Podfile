# Uncomment the next line to define a global platform for your project
platform :osx, '10.12'

target 'Shifty' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!

  pod 'AXSwift'
  pod 'LetsMove'
  pod 'MASPreferences+Shifty'
  pod 'MASShortcut'
  pod 'PublicSuffix'
  pod 'Sparkle'
  pod 'SwiftLog'

end

target 'ShiftyHelper' do
  # Comment the next line if you're not using Swift and don't want to use dynamic frameworks
  use_frameworks!

  # Pods for ShiftyHelper

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '10.12'
    end
  end
end
