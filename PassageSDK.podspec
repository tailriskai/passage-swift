Pod::Spec.new do |spec|
  spec.name         = "PassageSDK"
  spec.version      = "0.0.7"
  spec.summary      = "Passage SDK for iOS"
  spec.description  = <<-DESC
    The everywhere API
    Authenticate users, extract data, and enrich with AI across any web app with Passage SDKs.
  DESC
  
  spec.homepage     = "https://github.com/tailriskai/passage-swift"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Passage" => "developers@tailrisk.ai" }
  
  spec.swift_version = "5.10"
  
  # Source-based distribution
  spec.source       = { 
    :git => "https://github.com/tailriskai/passage-swift.git",
    :tag => "v#{spec.version}"
  }
  
  # Source files
  spec.source_files = "Sources/PassageSDK/**/*.{swift,h,m}"
  spec.public_header_files = "Sources/PassageSDK/include/*.h"

  # Platform support
  spec.ios.deployment_target = "13.0"
  
  # Dependencies
  spec.dependency "Socket.IO-Client-Swift", "~> 16.1.1"
  
  # Framework settings
  spec.requires_arc = true
  spec.static_framework = true

  # Build settings
  spec.pod_target_xcconfig = { 
    'SWIFT_VERSION' => '5.10',
    'DEFINES_MODULE' => 'YES',
    'CLANG_ENABLE_MODULES' => 'YES',
    'SWIFT_EMIT_LOC_STRINGS' => 'NO',
    'OTHER_SWIFT_FLAGS' => '-DCocoaPods',
    'SWIFT_INSTALL_OBJC_HEADER' => 'YES',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) COCOAPODS=1'
  }
  
  # Ensure module map is properly generated
  spec.module_name = 'PassageSDK'
end
