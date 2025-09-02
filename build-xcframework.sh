#!/bin/bash

# Build script for PassageSDK XCFramework
# This script builds the SDK for both iOS device and simulator architectures

set -e

echo "🏗️  Building PassageSDK XCFramework..."

# Clean build directory
rm -rf build
mkdir -p build

# Get the SDK version from podspec
SDK_VERSION=$(grep -E "spec\.version\s*=" PassageSDK.podspec | sed -E 's/.*"([^"]+)".*/\1/')

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

# Check if we have frameworks or static libraries
if [ -d "./build/PassageSDK-iphonesimulator.xcarchive/Products/Library/Frameworks/PassageSDK.framework" ]; then
    # Use frameworks (traditional Xcode project)
    echo "📱 Using framework build outputs..."
    xcodebuild -create-xcframework \
      -framework ./build/PassageSDK-iphonesimulator.xcarchive/Products/Library/Frameworks/PassageSDK.framework \
      -framework ./build/PassageSDK-iphoneos.xcarchive/Products/Library/Frameworks/PassageSDK.framework \
      -output ./build/PassageSDK.xcframework
elif [ -f "./build/PassageSDK-iphonesimulator.xcarchive/Products/usr/local/lib/PassageSDK.o" ] || [ -f "./build/PassageSDK-iphonesimulator.xcarchive/Products/Library/libPassageSDK.a" ] || find "./build/PassageSDK-iphonesimulator.xcarchive" -name "*.o" | grep -q .; then
    # Use static libraries (Swift Package Manager)
    echo "📦 Using static library build outputs..."

    # For Swift Package Manager builds, we need to use the library approach
    # since xcodebuild doesn't properly handle static library frameworks
    echo "🔧 Creating XCFramework from static libraries..."

    # Find all object files in the archive
    SIMULATOR_OBJ_FILES=$(find "./build/PassageSDK-iphonesimulator.xcarchive" -name "*.o" 2>/dev/null)
    DEVICE_OBJ_FILES=$(find "./build/PassageSDK-iphoneos.xcarchive" -name "*.o" 2>/dev/null)

    if [ -z "$SIMULATOR_OBJ_FILES" ] || [ -z "$DEVICE_OBJ_FILES" ]; then
        echo "❌ Error: Could not find object files in build outputs!"
        echo "Simulator object files found: $SIMULATOR_OBJ_FILES"
        echo "Device object files found: $DEVICE_OBJ_FILES"
        exit 1
    fi

    # Copy Swift modules and headers if they exist
    SIMULATOR_MODULES=""
    DEVICE_MODULES=""

    # Find Swift modules
    SIM_MODULE_PATH=$(find ./build/DerivedData -path "*Release-iphonesimulator*" -name "PassageSDK.swiftmodule" -type d | head -1)
    DEVICE_MODULE_PATH=$(find ./build/DerivedData -path "*Release-iphoneos*" -name "PassageSDK.swiftmodule" -type d | head -1)

    if [ -n "$SIM_MODULE_PATH" ]; then
        SIMULATOR_MODULES="-headers $SIM_MODULE_PATH"
    fi
    if [ -n "$DEVICE_MODULE_PATH" ]; then
        DEVICE_MODULES="-headers $DEVICE_MODULE_PATH"
    fi

    # Create static libraries from object files
    echo "📚 Creating static libraries from object files..."

    # Create .a files from .o files
    ar rcs ./build/libPassageSDK-iphonesimulator.a $SIMULATOR_OBJ_FILES
    ar rcs ./build/libPassageSDK-iphoneos.a $DEVICE_OBJ_FILES
    
    # Create XCFramework from static libraries
    xcodebuild -create-xcframework \
      -library ./build/libPassageSDK-iphonesimulator.a $SIMULATOR_MODULES \
      -library ./build/libPassageSDK-iphoneos.a $DEVICE_MODULES \
      -output ./build/PassageSDK.xcframework
else
    echo "❌ Error: Could not find build outputs!"
    echo "Expected either:"
    echo "  - ./build/PassageSDK-iphonesimulator.xcarchive/Products/Library/Frameworks/PassageSDK.framework"
    echo "  - Object files (.o) in ./build/PassageSDK-iphonesimulator.xcarchive/"
    echo "  - Static library (.a) in ./build/PassageSDK-iphonesimulator.xcarchive/Products/Library/"
    exit 1
fi

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
