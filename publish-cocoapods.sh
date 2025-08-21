#!/bin/bash

# Publish PassageSDK to CocoaPods
# This script builds the XCFramework and publishes it to CocoaPods
#
# Usage:
#   ./publish-cocoapods.sh           - Full publish process
#   ./publish-cocoapods.sh --dry-run - Dry run (no actual publishing)
#   ./publish-cocoapods.sh --resume  - Resume from manual GitHub release step

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_step() {
    echo -e "${BLUE}🔄 $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
print_step "Checking prerequisites..."

if ! command_exists pod; then
    print_error "CocoaPods is not installed. Please install it first:"
    print_info "sudo gem install cocoapods"
    exit 1
fi

if ! command_exists xcodebuild; then
    print_error "Xcode command line tools are not installed"
    exit 1
fi

if ! command_exists git; then
    print_error "Git is not installed"
    exit 1
fi

print_success "All prerequisites are met"

# Check flags first
DRY_RUN=false
RESUME=false

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            print_warning "This is a dry run - no actual publishing will occur"
            ;;
        --resume)
            RESUME=true
            print_info "Resuming from manual steps - skipping build and SHA256 calculation"
            ;;
        *)
            print_error "Unknown argument: $arg"
            print_info "Usage: $0 [--dry-run] [--resume]"
            exit 1
            ;;
    esac
done

# Get version from podspec
SDK_VERSION=$(grep -E "spec\.version\s*=" PassageSDK.podspec | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$SDK_VERSION" ]; then
    print_error "Could not extract version from PassageSDK.podspec"
    exit 1
fi

print_info "Publishing PassageSDK version: $SDK_VERSION"

# Check if we're in a git repository and it's clean
if [ -d ".git" ]; then
    if ! git diff --quiet || ! git diff --cached --quiet; then
        print_warning "Working directory is not clean. Consider committing changes first."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Aborted by user"
            exit 0
        fi
    fi
fi

# Build XCFramework and calculate SHA256 (skip if resuming)
if [ "$RESUME" = false ]; then
    # Build XCFramework
    print_step "Building XCFramework..."
    if ! ./build-xcframework.sh; then
        print_error "Failed to build XCFramework"
        exit 1
    fi

    print_success "XCFramework built successfully"
    
    # Verify XCFramework structure for CocoaPods compatibility
    print_step "Verifying XCFramework structure..."
    XCFRAMEWORK_PATH="./build/PassageSDK-${SDK_VERSION}.xcframework"
    
    # Check that both variants have the same library name (required for CocoaPods)
    DEVICE_LIB=$(find "$XCFRAMEWORK_PATH/ios-arm64" -name "*.a" -exec basename {} \; | head -1)
    SIMULATOR_LIB=$(find "$XCFRAMEWORK_PATH/ios-arm64_x86_64-simulator" -name "*.a" -exec basename {} \; | head -1)
    
    if [ "$DEVICE_LIB" != "$SIMULATOR_LIB" ]; then
        print_error "Library names don't match between device and simulator variants"
        print_error "Device: $DEVICE_LIB, Simulator: $SIMULATOR_LIB"
        print_info "Both variants must have the same library name for CocoaPods compatibility"
        exit 1
    fi
    
    print_success "XCFramework structure verified"

    # Calculate actual SHA256
    print_step "Calculating SHA256 checksum..."
    ACTUAL_SHA256=$(shasum -a 256 "./build/PassageSDK-${SDK_VERSION}.xcframework.zip" | cut -d' ' -f1)
    print_info "SHA256: $ACTUAL_SHA256"

    # Update podspec with actual SHA256
    print_step "Updating podspec with SHA256..."
    # Use a more robust approach to update the SHA256 in the podspec
    sed -i.bak "s/:sha256 => \"[^\"]*\"/:sha256 => \"$ACTUAL_SHA256\"/g" PassageSDK.podspec
    rm PassageSDK.podspec.bak

    print_success "Podspec updated with SHA256"
else
    print_info "Skipping build and SHA256 calculation (resuming from manual steps)"
    # Extract SHA256 from existing podspec for summary
    ACTUAL_SHA256=$(grep -E "sha256.*=>" PassageSDK.podspec | sed -E 's/.*"([^"]+)".*/\1/')
    if [ -z "$ACTUAL_SHA256" ]; then
        print_warning "Could not extract SHA256 from podspec - it may need to be set manually"
        ACTUAL_SHA256="[Not found in podspec]"
    fi
fi

# Validate podspec syntax and dependencies
print_step "Validating podspec syntax and dependencies..."
if ! pod lib lint PassageSDK.podspec --allow-warnings --skip-import-validation --skip-tests --sources='https://cdn.cocoapods.org/' --use-libraries 2>/dev/null; then
    print_warning "Local validation failed (expected - framework not present locally)"
    print_info "Will perform full validation after GitHub release is created"
else
    print_success "Local podspec validation passed"
fi



# Tag the release (if not dry run)
if [ "$DRY_RUN" = false ]; then
    if [ -d ".git" ]; then
        print_step "Creating git tag..."
        if git tag -a "v$SDK_VERSION" -m "Release version $SDK_VERSION" 2>/dev/null; then
            print_success "Created git tag v$SDK_VERSION"
            
            print_step "Pushing tag to origin..."
            if git push origin "v$SDK_VERSION"; then
                print_success "Tag pushed to origin"
            else
                print_warning "Failed to push tag to origin"
            fi
        else
            print_warning "Tag v$SDK_VERSION already exists"
        fi
    fi
fi

# Create GitHub release (manual step reminder)
print_step "GitHub Release Required"
print_warning "Manual step required:"
print_info "1. Go to https://github.com/tailriskai/passage-swift/releases"
print_info "2. Create a new release for tag v$SDK_VERSION"
print_info "3. Upload the file: ./build/PassageSDK-${SDK_VERSION}.xcframework.zip"
print_info "4. Make sure the download URL matches the one in the podspec"

if [ "$DRY_RUN" = false ]; then
    read -p "Press Enter after creating the GitHub release and uploading the XCFramework..."
    
    # Now perform full validation with the actual download
    print_step "Performing full podspec validation..."
    if ! pod spec lint PassageSDK.podspec --allow-warnings --sources='https://cdn.cocoapods.org/' --use-libraries; then
        print_error "Full podspec validation failed after GitHub release"
        print_info "Please check that the GitHub release was created correctly"
        # Restore original podspec
        git checkout PassageSDK.podspec 2>/dev/null || true
        exit 1
    fi
    
    print_success "Full podspec validation passed"
fi

# Publish to CocoaPods
if [ "$DRY_RUN" = false ]; then
    print_step "Publishing to CocoaPods..."
    
    # Check if user is logged in to CocoaPods trunk
    if ! pod trunk me >/dev/null 2>&1; then
        print_error "You are not logged in to CocoaPods trunk"
        print_info "Please run: pod trunk register YOUR_EMAIL 'YOUR_NAME'"
        exit 1
    fi
    
    print_info "Publishing to CocoaPods trunk..."
    if pod trunk push PassageSDK.podspec --allow-warnings --use-libraries; then
        print_success "Successfully published to CocoaPods!"
    else
        print_error "Failed to publish to CocoaPods"
        exit 1
    fi
else
    print_info "Dry run: Would publish to CocoaPods trunk"
fi

# Cleanup: restore original podspec if needed
if [ "$DRY_RUN" = true ]; then
    print_step "Restoring original podspec (dry run)..."
    git checkout PassageSDK.podspec 2>/dev/null || true
fi

print_success "Publication process completed!"

echo ""
print_info "📋 Summary:"
print_info "  - Version: $SDK_VERSION"
print_info "  - XCFramework: ./build/PassageSDK-${SDK_VERSION}.xcframework.zip"
print_info "  - SHA256: $ACTUAL_SHA256"

if [ "$DRY_RUN" = false ]; then
    print_info "  - Git tag: v$SDK_VERSION"
    print_info "  - Published to CocoaPods: ✅"
    echo ""
    print_success "Developers can now use: pod 'PassageSDK', '~> $SDK_VERSION'"
else
    print_warning "This was a dry run - no actual publishing occurred"
    echo ""
    print_info "To publish for real, run: ./publish-cocoapods.sh"
    print_info "To resume from manual steps, run: ./publish-cocoapods.sh --resume"
fi
