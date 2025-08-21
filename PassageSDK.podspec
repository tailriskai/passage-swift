Pod::Spec.new do |spec|
  spec.name         = "PassageSDK"
  spec.version      = "0.0.1"
  spec.summary      = "Passage SDK for iOS"
  spec.description  = <<-DESC
    The everywhere API
    Authenticate users, extract data, and enrich with AI across any web app with Passage SDKs.
  DESC
  
  spec.homepage     = "https://github.com/tailriskai/passage-swift"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Passage" => "developers@tailrisk.ai" }
  
  spec.swift_version = "5.7"
  
  # Source-based distribution
  spec.source       = { 
    :git => "https://github.com/tailriskai/passage-swift.git",
    :tag => "v#{spec.version}"
  }
  
  # Source files
  spec.source_files = "Sources/PassageSDK/**/*.swift"
  
  # Platform support
  spec.ios.deployment_target = "13.0"
  
  # Dependencies
  spec.dependency "Socket.IO-Client-Swift", "~> 16.1.1"
  
  # Framework settings
  spec.requires_arc = true
  spec.static_framework = false
  
  # Build settings
  spec.pod_target_xcconfig = { 
    'SWIFT_VERSION' => '5.7',
    'BUILD_LIBRARY_FOR_DISTRIBUTION' => 'YES'
  }
end
