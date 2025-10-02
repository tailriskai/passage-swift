#!/bin/bash

# Create Xcode Project for AutopilotApp
# This script sets up a complete iOS app structure

set -e

echo "🚀 Creating Xcode project for AutopilotApp..."

PROJECT_DIR="/Users/mw/passage/core/passage-swift/AutopilotApp"
cd "$PROJECT_DIR"

# Create project structure
mkdir -p AutopilotApp.xcodeproj
mkdir -p AutopilotApp.xcodeproj/project.xcworkspace
mkdir -p AutopilotApp.xcodeproj/project.xcworkspace/xcshareddata
mkdir -p AutopilotApp.xcodeproj/xcuserdata

echo "📁 Creating project.pbxproj..."

# Create project.pbxproj file
cat > AutopilotApp.xcodeproj/project.pbxproj << 'EOF'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
		AA0000000000000000000001 /* AppDelegate.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000001 /* AppDelegate.swift */; };
		AA0000000000000000000002 /* AutopilotViewController.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000002 /* AutopilotViewController.swift */; };
		AA0000000000000000000003 /* AutopilotWebSocketManager.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000003 /* AutopilotWebSocketManager.swift */; };
		AA0000000000000000000004 /* StateTracker.swift in Sources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000004 /* StateTracker.swift */; };
		AA0000000000000000000005 /* Assets.xcassets in Resources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000005 /* Assets.xcassets */; };
		AA0000000000000000000006 /* LaunchScreen.storyboard in Resources */ = {isa = PBXBuildFile; fileRef = BB0000000000000000000006 /* LaunchScreen.storyboard */; };
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		AA0000000000000000000010 /* AutopilotApp.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = AutopilotApp.app; sourceTree = BUILT_PRODUCTS_DIR; };
		BB0000000000000000000001 /* AppDelegate.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AppDelegate.swift; sourceTree = "<group>"; };
		BB0000000000000000000002 /* AutopilotViewController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AutopilotViewController.swift; sourceTree = "<group>"; };
		BB0000000000000000000003 /* AutopilotWebSocketManager.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = AutopilotWebSocketManager.swift; sourceTree = "<group>"; };
		BB0000000000000000000004 /* StateTracker.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = StateTracker.swift; sourceTree = "<group>"; };
		BB0000000000000000000005 /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; };
		BB0000000000000000000006 /* Base */ = {isa = PBXFileReference; lastKnownFileType = file.storyboard; name = Base; path = Base.lproj/LaunchScreen.storyboard; sourceTree = "<group>"; };
		BB0000000000000000000007 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		CC0000000000000000000001 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		DD0000000000000000000001 = {
			isa = PBXGroup;
			children = (
				DD0000000000000000000002 /* AutopilotApp */,
				DD0000000000000000000003 /* Products */,
			);
			sourceTree = "<group>";
		};
		DD0000000000000000000002 /* AutopilotApp */ = {
			isa = PBXGroup;
			children = (
				BB0000000000000000000001 /* AppDelegate.swift */,
				BB0000000000000000000002 /* AutopilotViewController.swift */,
				BB0000000000000000000003 /* AutopilotWebSocketManager.swift */,
				BB0000000000000000000004 /* StateTracker.swift */,
				BB0000000000000000000005 /* Assets.xcassets */,
				BB0000000000000000000006 /* LaunchScreen.storyboard */,
				BB0000000000000000000007 /* Info.plist */,
			);
			path = AutopilotApp;
			sourceTree = "<group>";
		};
		DD0000000000000000000003 /* Products */ = {
			isa = PBXGroup;
			children = (
				AA0000000000000000000010 /* AutopilotApp.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		EE0000000000000000000001 /* AutopilotApp */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = EE0000000000000000000002 /* Build configuration list for PBXNativeTarget "AutopilotApp" */;
			buildPhases = (
				FF0000000000000000000001 /* Sources */,
				CC0000000000000000000001 /* Frameworks */,
				FF0000000000000000000002 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = AutopilotApp;
			productName = AutopilotApp;
			productReference = AA0000000000000000000010 /* AutopilotApp.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		DD0000000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					EE0000000000000000000001 = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = DD0000000000000000000004 /* Build configuration list for PBXProject "AutopilotApp" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = DD0000000000000000000001;
			productRefGroup = DD0000000000000000000003 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				EE0000000000000000000001 /* AutopilotApp */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		FF0000000000000000000002 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AA0000000000000000000006 /* LaunchScreen.storyboard in Resources */,
				AA0000000000000000000005 /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		FF0000000000000000000001 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				AA0000000000000000000002 /* AutopilotViewController.swift in Sources */,
				AA0000000000000000000001 /* AppDelegate.swift in Sources */,
				AA0000000000000000000003 /* AutopilotWebSocketManager.swift in Sources */,
				AA0000000000000000000004 /* StateTracker.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXVariantGroup section */
		BB0000000000000000000006 /* LaunchScreen.storyboard */ = {
			isa = PBXVariantGroup;
			children = (
				BB0000000000000000000006 /* Base */,
			);
			name = LaunchScreen.storyboard;
			sourceTree = "<group>";
		};
/* End PBXVariantGroup section */

/* Begin XCBuildConfiguration section */
		GG0000000000000000000001 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		GG0000000000000000000002 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		GG0000000000000000000003 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = AutopilotApp/Info.plist;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.passage.AutopilotApp;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		GG0000000000000000000004 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = AutopilotApp/Info.plist;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchStoryboardName = LaunchScreen;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				IPHONEOS_DEPLOYMENT_TARGET = 15.0;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.passage.AutopilotApp;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		DD0000000000000000000004 /* Build configuration list for PBXProject "AutopilotApp" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				GG0000000000000000000001 /* Debug */,
				GG0000000000000000000002 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		EE0000000000000000000002 /* Build configuration list for PBXNativeTarget "AutopilotApp" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				GG0000000000000000000003 /* Debug */,
				GG0000000000000000000004 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = DD0000000000000000000001 /* Project object */;
}
EOF

echo "📱 Creating workspace files..."

# Create workspace data
cat > AutopilotApp.xcodeproj/project.xcworkspace/contents.xcworkspacedata << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
EOF

# Create workspace settings
mkdir -p AutopilotApp.xcodeproj/project.xcworkspace/xcshareddata
cat > AutopilotApp.xcodeproj/project.xcworkspace/xcshareddata/IDEWorkspaceChecks.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>IDEDidComputeMac32BitWarning</key>
	<true/>
</dict>
</plist>
EOF

echo "🎨 Creating Assets.xcassets..."
mkdir -p AutopilotApp/Assets.xcassets
mkdir -p AutopilotApp/Assets.xcassets/AppIcon.appiconset
mkdir -p AutopilotApp/Assets.xcassets/AccentColor.colorset

cat > AutopilotApp/Assets.xcassets/Contents.json << 'EOF'
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

cat > AutopilotApp/Assets.xcassets/AppIcon.appiconset/Contents.json << 'EOF'
{
  "images" : [
    {
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

cat > AutopilotApp/Assets.xcassets/AccentColor.colorset/Contents.json << 'EOF'
{
  "colors" : [
    {
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
EOF

echo "📄 Creating LaunchScreen.storyboard..."
mkdir -p AutopilotApp/Base.lproj
cat > AutopilotApp/Base.lproj/LaunchScreen.storyboard << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="22155" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" useTraitCollections="YES" useSafeAreas="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
    <device id="retina6_12" orientation="portrait" appearance="light"/>
    <dependencies>
        <deployment identifier="iOS"/>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="22131"/>
        <capability name="Safe area layout guides" minToolsVersion="9.0"/>
        <capability name="documents saved in the Xcode 8 format" minToolsVersion="8.0"/>
    </dependencies>
    <scenes>
        <!--View Controller-->
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <rect key="frame" x="0.0" y="0.0" width="393" height="852"/>
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <label opaque="NO" clipsSubviews="YES" userInteractionEnabled="NO" contentMode="left" horizontalHuggingPriority="251" verticalHuggingPriority="251" text="Autopilot" textAlignment="center" lineBreakMode="tailTruncation" baselineAdjustment="alignBaselines" minimumFontSize="18" translatesAutoresizingMaskIntoConstraints="NO" id="GJd-Yh-RWb">
                                <rect key="frame" x="20" y="396" width="353" height="60"/>
                                <fontDescription key="fontDescription" type="boldSystem" pointSize="50"/>
                                <color key="textColor" systemColor="systemBlueColor"/>
                                <nil key="highlightedColor"/>
                            </label>
                        </subviews>
                        <viewLayoutGuide key="safeArea" id="6Tk-OE-BBY"/>
                        <color key="backgroundColor" systemColor="systemBackgroundColor"/>
                        <constraints>
                            <constraint firstItem="GJd-Yh-RWb" firstAttribute="centerY" secondItem="Ze5-6b-2t3" secondAttribute="centerY" id="SkM-Qb-NbX"/>
                            <constraint firstItem="GJd-Yh-RWb" firstAttribute="leading" secondItem="6Tk-OE-BBY" secondAttribute="leading" constant="20" id="bfN-EH-0h3"/>
                            <constraint firstItem="6Tk-OE-BBY" firstAttribute="trailing" secondItem="GJd-Yh-RWb" secondAttribute="trailing" constant="20" id="hZw-8Q-VNK"/>
                        </constraints>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="53" y="375"/>
        </scene>
    </scenes>
    <resources>
        <systemColor name="systemBackgroundColor">
            <color white="1" alpha="1" colorSpace="custom" customColorSpace="genericGamma22GrayColorSpace"/>
        </systemColor>
        <systemColor name="systemBlueColor">
            <color red="0.0" green="0.47843137254901963" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
        </systemColor>
    </resources>
</document>
EOF

echo "⚙️  Updating Podfile..."
cat > Podfile << 'EOF'
platform :ios, '15.0'

target 'AutopilotApp' do
  use_frameworks!

  # Passage SDK (local path)
  pod 'PassageSDK', :path => '../'

  # Socket.IO for WebSocket communication
  pod 'Socket.IO-Client-Swift', '~> 16.0.1'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    end
  end
end
EOF

echo "🔧 Installing CocoaPods dependencies..."
pod install

echo ""
echo "✅ Xcode project created successfully!"
echo ""
echo "📂 Project location: $PROJECT_DIR/AutopilotApp.xcodeproj"
echo "🚀 To open: open AutopilotApp.xcworkspace"
echo ""
echo "Next steps:"
echo "1. Open AutopilotApp.xcworkspace in Xcode"
echo "2. Select a simulator or device"
echo "3. Press Cmd+R to build and run"
echo ""
