# Passage Swift SDK

## Project Overview
This is the **Passage Swift SDK**, a native iOS SDK for integrating Passage authentication, data capture, and "Autopilot" features into iOS applications. It allows developers to authenticate users, extract data, and enrich applications with AI capabilities.

**Key Features:**
- **Authentication & Data Capture:** Easy integration with Passage's authentication flows.
- **Autopilot:** WebSocket-based remote control for webviews, enabling backend-driven navigation and command execution.
- **WebView Management:** robust handling of cookies, local storage, and navigation state.

## Architecture & Key Files

### Core SDK (`Sources/PassageSDK/`)
*   **`PassageSDK.swift`**: The main singleton class (`Passage.shared`) acting as the public API surface. Handles initialization, configuration, and opening the modal interface.
*   **`PassageConfig.swift`**: Defines the `PassageConfig` struct for setting API URLs and debug flags.
*   **`WebViewModalViewController.swift`**: Manages the internal `WKWebView` for displaying Passage UI and handling web content.
*   **`RemoteControlManager.swift`**: Manages WebSocket connections (using Socket.IO) for the Autopilot feature.

### Example Applications
*   **`ExampleLocal/PassageExample`**: A complete example iOS application demonstrating standard SDK integration.
*   **`AutopilotApp/`**: Contains source files for a dedicated Autopilot app. Note that the `.xcodeproj` might need to be generated or is missing, but the source code (`AutopilotViewController.swift`, etc.) is available.

### Configuration
*   **`Package.swift`**: Swift Package Manager configuration.
*   **`PassageSDK.podspec`**: CocoaPods configuration.

## Building & Running

### Prerequisites
*   **Xcode 14+** (Swift 5.7+)
*   **CocoaPods** (for some example setups)

### Installation
The SDK can be installed via:
1.  **Swift Package Manager:** Add the package URL to your project.
2.  **CocoaPods:** Add `pod 'PassageSDK'` to your `Podfile`.

### Running the Example App (`ExampleLocal`)
1.  Navigate to the example directory:
    ```bash
    cd ExampleLocal
    ```
2.  Install dependencies:
    ```bash
    pod install
    ```
3.  Open the workspace:
    ```bash
    open PassageExample.xcworkspace
    ```
4.  Run the app in the iOS Simulator.

## Autopilot Integration
For detailed instructions on integrating the Autopilot features (remote control, WebSocket connection), refer to **`AUTOPILOT_IOS_INTEGRATION.md`**.

The recommended approach is to integrate Autopilot files into the existing `PassageExample` app:
1.  Copy Autopilot Swift files from `AutopilotApp/AutopilotApp/*.swift` to `ExampleLocal/PassageExample/`.
2.  Add `pod 'Socket.IO-Client-Swift', '~> 16.0.1'` to the `Podfile`.
3.  Register the `AutopilotViewController` in your app navigation.

## Development Workflow
*   **Build Script:** `build-xcframework.sh` allows building the binary framework.
*   **Publishing:** Scripts like `publish-cocoapods.sh` handle distribution.
*   **Code Style:** Follows standard Swift conventions. Use `PassageLogger` for logging within the SDK.

## Common Tasks
*   **Configure SDK:**
    ```swift
    Passage.shared.configure(PassageConfig(uiUrl: "...", apiUrl: "..."))
    ```
*   **Open Modal:**
    ```swift
    Passage.shared.open(token: "YOUR_INTENT_TOKEN")
    ```
*   **Clear Cookies:**
    ```swift
    Passage.shared.clearAllCookies()
    ```
