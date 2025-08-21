Pod::Spec.new do |spec|
  spec.name         = "PassageSDK"
  spec.version      = "1.0.0"
  spec.summary      = "Passage SDK for iOS"
  spec.description  = <<-DESC
    The everywhere API
    Authenticate users, extract data, and enrich with AI across any web app with Passage SDKs.
  DESC
  
  spec.homepage     = "https://github.com/tailriskai/passage-swift"
  spec.license      = { :type => "MIT", :text => "Copyright (c) 2025 Passage Inc. All rights reserved." }
  spec.author       = { "Passage" => "developers@tailrisk.ai" }
  
  spec.platform     = :ios, "13.0"
  spec.swift_version = "5.7"
  
  spec.source       = { 
    :http => "https://github.com/tailriskai/passage-swift/releases/download/v#{spec.version}/PassageSDK-#{spec.version}.xcframework.zip",
    :sha256 => "e0065e551bcdaf16d23158327eef5328ebb091b8a19d18689705105a00c4c513"
  }
  
    spec.vendored_frameworks = "PassageSDK.xcframework"
  spec.static_framework = true

  spec.dependency "Socket.IO-Client-Swift", "~> 16.1.1"
  
  spec.ios.deployment_target = "13.0"
  
  # Build settings for XCFramework
  spec.pod_target_xcconfig = { 
    'ONLY_ACTIVE_ARCH' => 'NO'
  }
  spec.user_target_xcconfig = { 
    'ONLY_ACTIVE_ARCH' => 'NO'
  }
end