#!/bin/bash

# Build script for PassageSDK XCFramework
# This script builds the SDK for both iOS device and simulator architectures

set -e

echo "🏗️  Building PassageSDK XCFramework..."

# Clean build directory
rm -rf build
mkdir -p build

# Get the SDK version from Package.swift or set manually
SDK_VERSION="1.0.0"

echo "📦 Building version: $SDK_VERSION"

# Build for iOS Simulator
echo "📱 Building for iOS Simulator..."
xcodebuild archive \
  -scheme PassageSDK \
  -destination "generic/platform=iOS Simulator" \
  -archivePath ./build/PassageSDK-iphonesimulator.xcarchive \
  -derivedDataPath ./build/DerivedData \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Build for iOS Device
echo "📱 Building for iOS Device..."
xcodebuild archive \
  -scheme PassageSDK \
  -destination "generic/platform=iOS" \
  -archivePath ./build/PassageSDK-iphoneos.xcarchive \
  -derivedDataPath ./build/DerivedData \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES

# Create XCFramework
echo "🔨 Creating XCFramework..."
xcodebuild -create-xcframework \
  -framework ./build/PassageSDK-iphonesimulator.xcarchive/Products/Library/Frameworks/PassageSDK.framework \
  -framework ./build/PassageSDK-iphoneos.xcarchive/Products/Library/Frameworks/PassageSDK.framework \
  -output ./build/PassageSDK.xcframework

echo "✅ XCFramework built successfully!"
echo "📍 Location: ./build/PassageSDK.xcframework"

# Create a zip for distribution
echo "📦 Creating distribution zip..."
cd build
zip -r PassageSDK-${SDK_VERSION}.xcframework.zip PassageSDK.xcframework
cd ..

echo "✅ Distribution zip created!"
echo "📍 Location: ./build/PassageSDK-${SDK_VERSION}.xcframework.zip"

# Calculate checksums
echo "🔐 Calculating checksums..."
cd build
shasum -a 256 PassageSDK-${SDK_VERSION}.xcframework.zip > PassageSDK-${SDK_VERSION}.xcframework.zip.sha256
cd ..

echo "✅ Build complete!"
echo ""
echo "📊 Build artifacts:"
echo "  - XCFramework: ./build/PassageSDK.xcframework"
echo "  - Distribution: ./build/PassageSDK-${SDK_VERSION}.xcframework.zip"
echo "  - Checksum: ./build/PassageSDK-${SDK_VERSION}.xcframework.zip.sha256"
