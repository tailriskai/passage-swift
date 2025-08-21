# Passage SDK CocoaPods Example

This example demonstrates how to integrate and use the Passage SDK in an iOS app using CocoaPods for dependency management.

## Prerequisites

- Xcode 14.0 or later
- iOS 13.0 or later
- CocoaPods installed on your system

## Installation

### 1. Install CocoaPods (if not already installed)

```bash
sudo gem install cocoapods
```

### 2. Install Dependencies

Navigate to the project directory and install the pods:

```bash
cd ExampleCocoaPods
pod install
```

This will:

- Download and install PassageSDK from the git repository
- Create a `.xcworkspace` file
- Set up the necessary project configurations

**Note**: The Podfile is configured to use the git source directly since PassageSDK may not be indexed in the CocoaPods trunk yet.

### 3. Open the Project

**Important**: After running `pod install`, always open the `.xcworkspace` file, not the `.xcodeproj` file:

```bash
open PassageExampleCocoaPods.xcworkspace
```

## Project Structure

```
ExampleCocoaPods/
├── Podfile                                    # CocoaPods dependency file
├── PassageExampleCocoaPods.xcworkspace       # Workspace file (open this)
├── PassageExampleCocoaPods.xcodeproj/        # Xcode project
├── PassageExampleCocoaPods/                  # App source code
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   ├── ViewController.swift                  # Main example implementation
│   ├── Info.plist
│   ├── Assets.xcassets/
│   └── Base.lproj/
└── Pods/                                     # CocoaPods dependencies (auto-generated)
```

## Key Differences from Swift Package Manager

This CocoaPods example differs from the SPM example in the following ways:

1. **Dependency Management**: Uses `Podfile` instead of Swift Package Manager
2. **Project Structure**: Includes `Pods/` directory and `.xcworkspace` file
3. **Build Configuration**: Uses CocoaPods-generated xcconfig files
4. **Framework Integration**: PassageSDK is linked as a framework via CocoaPods

## Usage

The example app demonstrates:

- **SDK Configuration**: How to configure the Passage SDK with debug logging
- **Intent Token Fetching**: How to fetch an intent token from the Passage API
- **SDK Integration**: How to open the Passage SDK with callbacks
- **Error Handling**: How to handle success and error scenarios
- **UI Updates**: How to update the UI based on SDK callbacks

### Key Features

- Fetches intent tokens from the Passage API
- Opens Passage SDK with proper callbacks
- Displays results in a user-friendly format
- Includes comprehensive logging for debugging
- Shows CocoaPods-specific installation notes

## Running the Example

1. Open `PassageExampleCocoaPods.xcworkspace` in Xcode
2. Build and run the project on a device or simulator
3. Tap the "Connect" button to start the Passage flow
4. Check the console logs for detailed debugging information

## Troubleshooting

### Common Issues

1. **"Unable to find a specification for PassageSDK"**

   - This happens when the pod isn't available in the CocoaPods trunk yet
   - The Podfile is configured to use the git source directly as a workaround
   - If you want to use the trunk version, change the Podfile to: `pod 'PassageSDK', '~> 0.0.1'`

2. **"No such module 'PassageSDK'"**

   - Make sure you ran `pod install`
   - Ensure you're opening the `.xcworkspace` file, not `.xcodeproj`
   - Clean and rebuild the project

3. **Build Errors**

   - Try running `pod install --repo-update` to update CocoaPods specs
   - Clean derived data: Xcode → Product → Clean Build Folder

4. **Git-based Pod Issues**

   - Make sure the git tag `v0.0.1` exists in the repository
   - Try using `:branch => 'main'` instead of `:tag` if the tag doesn't exist

5. **Outdated Dependencies**
   - Update CocoaPods: `gem update cocoapods`
   - Update pods: `pod update`

### Updating Dependencies

To update to the latest version of PassageSDK:

```bash
pod update PassageSDK
```

To update all dependencies:

```bash
pod update
```

## Comparison with Swift Package Manager Example

| Feature           | CocoaPods        | Swift Package Manager         |
| ----------------- | ---------------- | ----------------------------- |
| Setup             | `pod install`    | Add via Xcode                 |
| File to open      | `.xcworkspace`   | `.xcodeproj`                  |
| Dependency file   | `Podfile`        | Package.swift or Xcode config |
| Build integration | xcconfig files   | Native Xcode integration      |
| Offline support   | Local Pods cache | Xcode cache                   |

## API Configuration

The example uses a test integration ID (`netflix`) for demonstration purposes. In a real application, you would:

1. Replace the authorization header with your actual publishable key
2. Use your specific integration ID
3. Implement proper error handling for production use

## Support

For issues specific to:

- **PassageSDK**: Check the main repository documentation
- **CocoaPods**: Visit [CocoaPods.org](https://cocoapods.org)
- **This Example**: Check the console logs for debugging information
