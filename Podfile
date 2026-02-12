# Uncomment the next line to define a global platform for your project
platform :osx, '10.12'

def patch_mas_shortcut_transformers(installer)
  patch_targets = [
    {
      relative_path: "MASShortcut/Framework/UI/MASShortcutView+Bindings.m",
      from: "    if (@available(macOS 10.13, *)) {\n        return NSSecureUnarchiveFromDataTransformerName;\n    }\n    return NSKeyedUnarchiveFromDataTransformerName;\n",
      to: "    // MASShortcut instances are archived custom objects. The default secure\n    // unarchive transformer only allows Foundation top-level classes unless a\n    // custom allowed-class transformer is registered, which MASShortcut does\n    // not provide. Use keyed unarchive transformer to keep shortcut recording\n    // functional.\n    return NSKeyedUnarchiveFromDataTransformerName;\n"
    },
    {
      relative_path: "MASShortcut/Framework/User Defaults Storage/MASShortcutBinder.m",
      from: "    if (@available(macOS 10.13, *)) {\n        return NSSecureUnarchiveFromDataTransformerName;\n    }\n    return NSKeyedUnarchiveFromDataTransformerName;\n",
      to: "    // MASShortcut instances are archived custom objects. The default secure\n    // unarchive transformer only allows Foundation top-level classes unless a\n    // custom allowed-class transformer is registered, which MASShortcut does\n    // not provide. Use keyed unarchive transformer to keep shortcut binding\n    // and persistence functional.\n    return NSKeyedUnarchiveFromDataTransformerName;\n"
    }
  ]

  patch_targets.each do |patch|
    file = File.join(installer.sandbox.root.to_s, patch[:relative_path])
    next unless File.exist?(file)

    original = File.read(file)
    next unless original.include?(patch[:from])

    updated = original.sub(patch[:from], patch[:to])
    File.write(file, updated)
  end
end

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
  patch_mas_shortcut_transformers(installer)

  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '10.12'
    end
  end
end
