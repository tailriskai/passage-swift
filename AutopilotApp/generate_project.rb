#!/usr/bin/env ruby
require 'xcodeproj'

project_path = 'AutopilotApp.xcodeproj'

# Remove existing project if it exists
FileUtils.rm_rf(project_path) if File.exist?(project_path)

# Create new project
project = Xcodeproj::Project.new(project_path)

# Create main target
target = project.new_target(:application, 'AutopilotApp', :ios, '16.0')

# Get main group
main_group = project.main_group

# Create AutopilotApp group
app_group = main_group.new_group('AutopilotApp')

# Add source files
source_files = [
  'AutopilotApp/AppDelegate.swift',
  'AutopilotApp/AutopilotViewController.swift'
]

source_files.each do |file|
  file_ref = app_group.new_file(file)
  target.add_file_references([file_ref])
end

# Add Info.plist
info_plist = app_group.new_file('AutopilotApp/Info.plist')

# Add Assets.xcassets
assets = app_group.new_file('AutopilotApp/Assets.xcassets')
target.resources_build_phase.add_file_reference(assets)

# Add LaunchScreen.storyboard
launch_screen = app_group.new_file('AutopilotApp/Base.lproj/LaunchScreen.storyboard')
target.resources_build_phase.add_file_reference(launch_screen)

# Configure build settings
target.build_configurations.each do |config|
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.passage.autopilot'
  config.build_settings['INFOPLIST_FILE'] = 'AutopilotApp/Info.plist'
  config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '16.0'
  config.build_settings['TARGETED_DEVICE_FAMILY'] = '1,2'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
  config.build_settings['DEVELOPMENT_TEAM'] = 'FHSCXF7LC4'
  config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  config.build_settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  config.build_settings['INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents'] = 'YES'
  config.build_settings['INFOPLIST_KEY_UILaunchStoryboardName'] = 'LaunchScreen'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  config.build_settings['INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone'] = 'UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight'
  config.build_settings['LD_RUNPATH_SEARCH_PATHS'] = '$(inherited) @executable_path/Frameworks'
  config.build_settings['MARKETING_VERSION'] = '1.0'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '1'
end

# Save the project
project.save

puts "✅ Xcode project created successfully at #{project_path}"
puts "📦 Now run: pod install"
