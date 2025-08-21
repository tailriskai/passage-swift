# Passage Swift SDK

A native Swift SDK for integrating Passage secure data connections into iOS applications.

## Features

- 🔐 Secure automated data connections to third-party services
- 📱 Native Swift implementation (no JavaScript required)
- 🎨 Customizable presentation styles (modal/fullscreen)
- 🔄 Dual WebView system for UI and automation
- 🌐 Real-time remote control via WebSocket
- 📊 Built-in analytics and logging
- 🍪 Cookie management
- 📦 Swift Package Manager support

## Requirements

- iOS 13.0+
- Swift 5.0+
- Xcode 13.0+

## Installation

### Swift Package Manager

Add the following to your `Package.swift` file:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/passage-swift.git", from: "1.0.0")
]
```

Or in Xcode:

1. File → Add Package Dependencies
2. Enter the repository URL
3. Select the version and add to your target

## Quick Start

### 1. Configure the SDK

```swift
import PassageSDK

// Configure on app launch
let config = PassageConfig(
    baseUrl: "https://ui.getpassage.ai",     // Optional: custom base URL
    socketUrl: "https://api.getpassage.ai",  // Optional: custom socket URL
    debug: true                              // Enable debug logging
)

Passage.shared.configure(config)
```

### 2. Open a Connection

```swift
Passage.shared.open(
    token: "your_intent_token",
    presentationStyle: .modal,
    from: viewController,
    onSuccess: { data in
        print("Connection successful!")
        print("Connection ID: \(data.connectionId)")
        print("History: \(data.history)")
    },
    onError: { error in
        print("Connection failed: \(error.error)")
    },
    onClose: {
        print("User closed the modal")
    }
)
```

## API Reference

### PassageSDK

The main SDK singleton class.

```swift
public class PassageSDK {
    public static let shared: PassageSDK

    public func configure(_ config: PassageConfig)

    public func open(
        token: String,
        presentationStyle: PassagePresentationStyle = .modal,
        from viewController: UIViewController? = nil,
        onSuccess: ((PassageSuccessData) -> Void)? = nil,
        onError: ((PassageErrorData) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    )

    public func close()

    public func releaseResources() // Force cleanup of all WebView resources
}
```

### Configuration

```swift
public struct PassageConfig {
    public let baseUrl: String
    public let socketUrl: String
    public let socketNamespace: String
    public let debug: Bool

    public init(
        baseUrl: String? = nil,
        socketUrl: String? = nil,
        socketNamespace: String? = nil,
        debug: Bool = false
    )
}
```

### Data Types

```swift
public struct PassageSuccessData {
    public let history: [PassageHistoryItem]
    public let connectionId: String
}

public struct PassageHistoryItem {
    public let structuredData: Any?
    public let additionalData: [String: Any]
}

public struct PassageErrorData {
    public let error: String
    public let data: Any?
}

public enum PassagePresentationStyle {
    case modal      // Sheet presentation
    case fullScreen // Full screen presentation
}
```

## Advanced Usage

### Cookie Management

```swift
// Get cookies for a URL
Passage.shared.getCookies(for: "https://example.com") { cookies in
    for cookie in cookies {
        print("\(cookie.name): \(cookie.value)")
    }
}

// Set a cookie
let cookie = HTTPCookie(properties: [
    .name: "session",
    .value: "abc123",
    .domain: ".example.com",
    .path: "/"
])!
Passage.shared.setCookie(cookie)

// Clear cookies
Passage.shared.clearCookies(for: "https://example.com")
```

### JavaScript Injection

```swift
let script = "document.title"
Passage.shared.injectJavaScript(script) { result, error in
    if let title = result as? String {
        print("Page title: \(title)")
    }
}
```

### Navigation Control

```swift
// Navigate to a URL
Passage.shared.navigate(to: "https://example.com")

// Browser navigation
Passage.shared.goBack()
Passage.shared.goForward()
```

## Debug Logging

Enable debug logging to see detailed SDK operations:

```swift
let config = PassageConfig(debug: true)
Passage.shared.configure(config)
```

Log levels:

- `DEBUG`: Detailed debugging information
- `INFO`: General information
- `WARN`: Warning messages
- `ERROR`: Error messages

## Example App

See the `Example` directory for a complete sample application demonstrating:

- Token-based connection flow
- Success/error handling
- Debug mode toggle
- Result display

To run the example:

1. Open `Example/PassageExample.xcodeproj`
2. Build and run the app
3. Enter your intent token
4. Tap "Connect with Passage"

## Architecture

The SDK uses a dual WebView architecture:

1. **UI WebView**: Displays the connection flow UI to users
2. **Automation WebView**: Runs automation scripts in the background

This allows for seamless user interactions while automation runs in the background when needed.

### WebView Lifecycle Management

The SDK efficiently manages WebView resources to optimize performance:

- **Lazy Initialization**: WebViews are created only when first needed
- **Resource Reuse**: WebViews are preserved between sessions and reused for subsequent connections
- **Automatic State Reset**: Each new session automatically resets WebView state while preserving the instances
- **Manual Cleanup**: Call `releaseResources()` to force cleanup if needed (e.g., for memory management)

This approach provides:

- ⚡ Faster subsequent connection launches
- 💾 Efficient memory usage
- 🔄 Clean state for each new session

## Security

- All network communication uses HTTPS
- Intent tokens are used for session authentication
- Cookies are isolated per domain
- JavaScript execution is controlled and sandboxed

## Building as XCFramework

To build the SDK as an XCFramework for distribution:

```bash
# Build for iOS Simulator
xcodebuild archive \
  -scheme PassageSDK \
  -archivePath ./build/PassageSDK-iphonesimulator.xcarchive \
  -sdk iphonesimulator \
  SKIP_INSTALL=NO

# Build for iOS Device
xcodebuild archive \
  -scheme PassageSDK \
  -archivePath ./build/PassageSDK-iphoneos.xcarchive \
  -sdk iphoneos \
  SKIP_INSTALL=NO

# Create XCFramework
xcodebuild -create-xcframework \
  -framework ./build/PassageSDK-iphonesimulator.xcarchive/Products/Library/Frameworks/PassageSDK.framework \
  -framework ./build/PassageSDK-iphoneos.xcarchive/Products/Library/Frameworks/PassageSDK.framework \
  -output ./build/PassageSDK.xcframework
```

## Support

For questions or issues:

- Open an issue on GitHub
- Contact support at support@getpassage.ai
- Visit [getpassage.ai](https://getpassage.ai) for documentation

## License

This SDK is proprietary software. See LICENSE file for details.
