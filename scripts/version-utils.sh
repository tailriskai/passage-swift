#!/bin/bash

# Version utility functions for PassageSDK

# Function to get current version from podspec
get_current_version() {
    grep -E "spec\.version\s*=" PassageSDK.podspec | sed -E 's/.*"([^"]+)".*/\1/'
}

# Function to update version in podspec
update_version() {
    local new_version="$1"
    if [ -z "$new_version" ]; then
        echo "Error: No version specified"
        return 1
    fi
    
    # Validate version format (basic semver check)
    if ! [[ "$new_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Error: Version must be in semver format (e.g., 1.0.0)"
        return 1
    fi
    
    # Update podspec
    sed -i.bak "s/spec\.version.*=.*\".*\"/spec.version      = \"$new_version\"/" PassageSDK.podspec
    rm PassageSDK.podspec.bak
    
    echo "Updated version to $new_version"
    return 0
}

# Function to increment version
increment_version() {
    local version_part="$1"
    local current_version=$(get_current_version)
    
    if [ -z "$current_version" ]; then
        echo "Error: Could not get current version"
        return 1
    fi
    
    IFS='.' read -ra VERSION_PARTS <<< "$current_version"
    local major=${VERSION_PARTS[0]}
    local minor=${VERSION_PARTS[1]}
    local patch=${VERSION_PARTS[2]}
    
    case "$version_part" in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch")
            patch=$((patch + 1))
            ;;
        *)
            echo "Error: Version part must be 'major', 'minor', or 'patch'"
            return 1
            ;;
    esac
    
    local new_version="$major.$minor.$patch"
    update_version "$new_version"
    echo "Incremented $version_part: $current_version -> $new_version"
}

# Function to validate podspec
validate_podspec() {
    echo "Validating podspec..."
    if command -v pod >/dev/null 2>&1; then
        pod spec lint PassageSDK.podspec --allow-warnings
    else
        echo "Warning: CocoaPods not installed, skipping validation"
        return 0
    fi
}

# Main script logic
case "$1" in
    "get")
        get_current_version
        ;;
    "set")
        update_version "$2"
        ;;
    "increment")
        increment_version "$2"
        ;;
    "validate")
        validate_podspec
        ;;
    *)
        echo "Usage: $0 {get|set VERSION|increment {major|minor|patch}|validate}"
        echo ""
        echo "Examples:"
        echo "  $0 get                    # Get current version"
        echo "  $0 set 1.2.3             # Set version to 1.2.3"
        echo "  $0 increment patch        # Increment patch version"
        echo "  $0 increment minor        # Increment minor version"
        echo "  $0 increment major        # Increment major version"
        echo "  $0 validate               # Validate podspec"
        exit 1
        ;;
esac
