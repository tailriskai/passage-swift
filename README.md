# Passage Swift SDK

A lightweight native Swift SDK for integrating Passage into iOS apps. This document focuses on the external, user‑facing API only.

For complete integration guides and examples, visit our [documentation](https://docs.getpassage.ai/).

## Requirements

- iOS 13+
- Swift 5+
- Xcode 13+

## Installation

### Swift Package Manager (recommended)

Add the package in Xcode:

1. File → Add Package Dependencies
2. Enter the repository URL
3. Choose a version and add to your app target

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/tailriskai/passage-swift.git", from: "0.0.1")
]
```

### CocoaPods

Add to your `Podfile` and `pod install`:

```ruby
pod 'PassageSDK'
```

## Quick Start

### 1) Configure once (e.g., on app launch)

```swift
import PassageSDK

Passage.shared.configure(
    PassageConfig(
        debug: true // Optional
    )
)
```

### 2) Open a connection

```swift
// If you already have an intent token
Passage.shared.open(
    token: "your_intent_token",
    presentationStyle: .modal,   // .modal (default) or .fullScreen
    onConnectionComplete: { data in
        print("Connection complete: \(data.connectionId)")
    },
    onConnectionError: { error in
        print("Error: \(error.error)")
    },
    onDataComplete: { result in
        print("Data: \(String(describing: result.data))")
    },
    onExit: { reason in
        print("Closed (reason: \(reason ?? "unknown"))")
    }
)

// Or use the options-based API
let options = PassageOpenOptions(
    intentToken: "your_intent_token",
    onConnectionComplete: { data in /* ... */ },
    onConnectionError: { error in /* ... */ },
    onDataComplete: { result in /* ... */ },
    onExit: { reason in /* ... */ },
    presentationStyle: .modal
)
Passage.shared.open(options)
```

### 3) Close programmatically (optional)

```swift
Passage.shared.close()
```

## Public API

### Configuration

```swift
public struct PassageConfig {
    public init(
        baseUrl: String? = nil,
        socketUrl: String? = nil,
        socketNamespace: String? = nil,
        debug: Bool = false
    )
}
```

Use defaults in production. Only override URLs for custom environments.

### Methods

```swift
// Singleton
Passage.shared

// Configure SDK
func configure(_ config: PassageConfig)

// Open connection UI
func open(
    token: String,
    presentationStyle: PassagePresentationStyle = .modal,
    onConnectionComplete: ((PassageSuccessData) -> Void)? = nil,
    onConnectionError: ((PassageErrorData) -> Void)? = nil,
    onDataComplete: ((PassageDataResult) -> Void)? = nil,
    onExit: ((String?) -> Void)? = nil
)

// Options-based overload
func open(_ options: PassageOpenOptions = PassageOpenOptions())

// Close connection UI
func close()
```

### Types

```swift
public enum PassagePresentationStyle {
    case modal
    case fullScreen
}

public struct PassageSuccessData {
    public let connectionId: String
    public let history: [PassageHistoryItem]
}

public struct PassageHistoryItem {
    public let structuredData: Any?
    public let additionalData: [String: Any]
}

public struct PassageErrorData {
    public let error: String
    public let data: Any?
}

public struct PassageDataResult {
    public let data: Any?
}

public struct PassageOpenOptions { /* contains: intentToken, callbacks, presentationStyle */ }
```

## Example App

Open `Example/PassageExample.xcodeproj`, build, and run. Provide an intent token, then tap "Connect with Passage".

## Performance Overhead

The Passage SDK is designed to be lightweight with minimal impact on your app's performance.

### Benchmarking Results

Performance measurements conducted on iPhone 15 Pro with iOS 26 using real-time monitoring during typical SDK usage:

#### Kroger.com (Complex E-commerce Website)

| Metric      | Baseline | With Passage SDK | Overhead                                      |
| ----------- | -------- | ---------------- | --------------------------------------------- |
| Memory      | 9.2 MB   | 22.8 MB          | **+13.6 MB**                                  |
| CPU         | 0.0%     | 0.0% avg         | **Minimal** (spikes to 18% during operations) |
| App Startup | N/A      | N/A              | **No impact**                                 |

#### Audible.com (Media/Content Website)

| Metric      | Baseline | With Passage SDK | Overhead                                     |
| ----------- | -------- | ---------------- | -------------------------------------------- |
| Memory      | 8.7 MB   | 23.4 MB          | **+14.7 MB**                                 |
| CPU         | 0.0%     | 0.0% avg         | **Minimal** (spikes to 7% during operations) |
| App Startup | N/A      | N/A              | **No impact**                                |

### Performance Characteristics

- **Memory Usage**: ~14-15 MB overhead for full SDK functionality including WebView rendering
- **CPU Impact**: Minimal sustained usage with brief spikes during web page loading operations
    - Kroger.com (complex e-commerce): Spikes up to 18% during heavy page load
    - Audible.com (media content): Spikes up to 7% during typical page operations
- **Web Page Complexity**: Performance scales with website complexity and JavaScript usage
- **UI Responsiveness**: Maintains smooth 120/60+ FPS during normal usage
- **Startup Time**: No measurable impact on app launch performance

## Support

- Open an issue on GitHub
- Email support@getpassage.ai
- Visit `https://getpassage.ai`

## License

See `LICENSE`.
