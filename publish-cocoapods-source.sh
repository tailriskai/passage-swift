#!/bin/bash

# Publish PassageSDK to CocoaPods (Source Distribution)
# This script publishes the Swift Package as a source-based CocoaPods pod
#
# Usage:
#   ./publish-cocoapods-source.sh           - Full publish process
#   ./publish-cocoapods-source.sh --dry-run - Dry run (no actual publishing)

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

if ! command_exists git; then
    print_error "Git is not installed"
    exit 1
fi

if ! command_exists swift; then
    print_error "Swift is not installed"
    exit 1
fi

print_success "All prerequisites are met"

# Check flags
DRY_RUN=false
PODSPEC_FILE="PassageSDK.podspec"

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            print_warning "This is a dry run - no actual publishing will occur"
            ;;
        --podspec=*)
            PODSPEC_FILE="${arg#*=}"
            ;;
        *)
            print_error "Unknown argument: $arg"
            print_info "Usage: $0 [--dry-run] [--podspec=filename.podspec]"
            exit 1
            ;;
    esac
done

# Check if podspec exists
if [ ! -f "$PODSPEC_FILE" ]; then
    print_error "Podspec file '$PODSPEC_FILE' not found"
    exit 1
fi

# Get version from podspec
SDK_VERSION=$(grep -E "spec\.version\s*=" "$PODSPEC_FILE" | sed -E 's/.*"([^"]+)".*/\1/')

if [ -z "$SDK_VERSION" ]; then
    print_error "Could not extract version from $PODSPEC_FILE"
    exit 1
fi

print_info "Publishing PassageSDK version: $SDK_VERSION"
print_info "Using podspec: $PODSPEC_FILE"

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

# Skip Swift Package validation - CocoaPods will handle this during podspec validation
print_info "Skipping direct Swift Package validation (CocoaPods will validate during pod lib lint)"

# Validate podspec syntax
print_step "Validating podspec syntax..."
if pod lib lint "$PODSPEC_FILE" --allow-warnings --skip-import-validation --sources='https://cdn.cocoapods.org/'; then
    print_success "Podspec syntax validation passed"
else
    print_error "Podspec validation failed"
    exit 1
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

# Full podspec validation against remote repository
if [ "$DRY_RUN" = false ]; then
    print_step "Performing full podspec validation against remote repository..."
    
    # Give GitHub a moment to process the new tag
    print_info "Waiting for GitHub to process the new tag..."
    sleep 10
    
    if pod spec lint "$PODSPEC_FILE" --allow-warnings --sources='https://cdn.cocoapods.org/'; then
        print_success "Full podspec validation passed"
    else
        print_error "Full podspec validation failed"
        print_info "The tag might not be available yet, or there might be an issue with the repository"
        read -p "Continue with publishing anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_info "Aborted by user"
            exit 0
        fi
    fi
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
    if pod trunk push "$PODSPEC_FILE" --allow-warnings --sources='https://cdn.cocoapods.org/'; then
        print_success "Successfully published to CocoaPods!"
    else
        print_error "Failed to publish to CocoaPods"
        exit 1
    fi
else
    print_info "Dry run: Would publish to CocoaPods trunk"
fi

print_success "Publication process completed!"

echo ""
print_info "📋 Summary:"
print_info "  - Version: $SDK_VERSION"
print_info "  - Podspec: $PODSPEC_FILE"
print_info "  - Distribution: Source-based"

if [ "$DRY_RUN" = false ]; then
    print_info "  - Git tag: v$SDK_VERSION"
    print_info "  - Published to CocoaPods: ✅"
    echo ""
    print_success "Developers can now use: pod 'PassageSDK', '~> $SDK_VERSION'"
    print_info "Or in their Podfile:"
    print_info "pod 'PassageSDK', '~> $SDK_VERSION'"
else
    print_warning "This was a dry run - no actual publishing occurred"
    echo ""
    print_info "To publish for real, run: ./publish-cocoapods-source.sh"
fi
