# Publishing PassageSDK to CocoaPods

This document describes how to publish PassageSDK as an XCFramework to CocoaPods.

## Prerequisites

Before you can publish, ensure you have:

1. **Xcode** with command line tools installed
2. **CocoaPods** installed (`sudo gem install cocoapods`)
3. **CocoaPods Trunk** account set up (`pod trunk register YOUR_EMAIL 'YOUR_NAME'`)
4. **Git** repository with proper access
5. **GitHub** repository access for creating releases

## Files Overview

- `PassageSDK.podspec` - CocoaPods specification file
- `build-xcframework.sh` - Builds the XCFramework
- `publish-cocoapods.sh` - Main publishing script
- `scripts/version-utils.sh` - Version management utilities

## Quick Start

### 1. Set Version

```bash
# Set a specific version
./scripts/version-utils.sh set 1.2.3

# Or increment current version
./scripts/version-utils.sh increment patch   # 1.0.0 -> 1.0.1
./scripts/version-utils.sh increment minor   # 1.0.1 -> 1.1.0
./scripts/version-utils.sh increment major   # 1.1.0 -> 2.0.0
```

### 2. Test Build (Dry Run)

```bash
./publish-cocoapods.sh --dry-run
```

### 3. Publish for Real

```bash
./publish-cocoapods.sh
```

## Detailed Publishing Process

### Step 1: Version Management

Check current version:

```bash
./scripts/version-utils.sh get
```

Update version in `PassageSDK.podspec`:

```bash
./scripts/version-utils.sh set 1.2.3
```

### Step 2: Validate Changes

Validate the podspec:

```bash
./scripts/version-utils.sh validate
```

### Step 3: Build and Publish

Run the publishing script:

```bash
./publish-cocoapods.sh
```

The script will:

1. ✅ Check all prerequisites
2. 🏗️ Build the XCFramework using `build-xcframework.sh`
3. 🔐 Calculate SHA256 checksum
4. 📝 Update podspec with the checksum
5. ✅ Validate the podspec
6. 🏷️ Create a git tag (if in a git repository)
7. ⏸️ Pause for manual GitHub release creation
8. 🚀 Publish to CocoaPods trunk

### Step 4: Manual GitHub Release

When the script pauses, you need to:

1. Go to your GitHub repository releases page
2. Create a new release for the tag (e.g., `v1.2.3`)
3. Upload the generated XCFramework zip file from `./build/PassageSDK-VERSION.xcframework.zip`
4. Ensure the download URL matches what's in the podspec
5. Press Enter to continue the script

## Troubleshooting

### Common Issues

**"CocoaPods not installed"**

```bash
sudo gem install cocoapods
```

**"Not logged in to CocoaPods trunk"**

```bash
pod trunk register your-email@example.com 'Your Name'
# Check your email for verification
```

**"Podspec validation failed"**

- Check the podspec syntax
- Ensure all URLs are accessible
- Verify dependencies are correct

**"XCFramework build failed"**

- Check Xcode is properly installed
- Ensure the project builds successfully in Xcode
- Check for any compilation errors

### Manual Fixes

If something goes wrong during publishing:

1. **Reset podspec**: `git checkout PassageSDK.podspec`
2. **Remove build artifacts**: `rm -rf build/`
3. **Remove git tag**: `git tag -d v1.2.3 && git push origin :refs/tags/v1.2.3`

## Version Strategy

We recommend following [Semantic Versioning](https://semver.org/):

- **MAJOR** version for incompatible API changes
- **MINOR** version for backwards-compatible functionality additions
- **PATCH** version for backwards-compatible bug fixes

## Testing Integration

After publishing, test the integration:

```ruby
# In a test Podfile
pod 'PassageSDK', '~> 1.2.3'
```

## Automation Considerations

For CI/CD automation, you can:

1. Set environment variables for credentials
2. Use the `--dry-run` flag for testing
3. Automate GitHub releases using GitHub CLI or API
4. Run validation steps in your CI pipeline

## Security Notes

- SHA256 checksums are automatically calculated and embedded
- The XCFramework is distributed via GitHub releases
- CocoaPods pulls the framework from the release URL
- Always verify the checksum matches after upload
