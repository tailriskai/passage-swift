# Passage SDK - Implementation Reference

Comprehensive documentation for the Passage Swift SDK, including all implementation details, architectural patterns, and recent enhancements. This guide ensures feature parity across SDK implementations.

## Table of Contents
1. [Architecture Overview](#architecture-overview)
2. [Core Components](#core-components)
3. [Configuration and Initialization](#configuration-and-initialization)
4. [WebView Management](#webview-management)
5. [Navigation Controls](#navigation-controls)
6. [Socket Communication](#socket-communication)
7. [Command Processing](#command-processing)
8. [Recording and Screenshots](#recording-and-screenshots)
9. [Analytics and Logging](#analytics-and-logging)
10. [Cookie and Storage Management](#cookie-and-storage-management)
11. [Constants and Types](#constants-and-types)
12. [Critical Implementation Notes](#critical-implementation-notes)

## Architecture Overview

The Passage SDK is a sophisticated iOS/macOS framework that enables secure authentication and data capture through a dual-webview architecture with real-time socket communication.

### Key Components

1. **PassageSDK.swift** (1336 lines)
   - Main SDK interface (singleton: `Passage.shared`)
   - Manages lifecycle, configuration, and modal presentation
   - Handles callbacks and state management
   - Cross-platform support with `PassageCore` for non-iOS platforms

2. **RemoteControlManager.swift** (2477 lines)
   - Socket.IO WebSocket communication
   - Command processing and execution
   - JWT token parsing for feature flags
   - Screenshot capture and browser state management
   - Success URL matching for navigation control

3. **WebViewModalViewController.swift** (main file + 5 extensions)
   - Dual WebView management (UI and Automation)
   - Split into specialized extensions for maintainability:

   **WebViewModalViewController.swift** (main)
   - Core view controller lifecycle and properties
   - Modal presentation and state management
   - Notification observers and setup
   - Delegate coordination

   **WebViewModalViewController+WebViewSetup.swift** (1097 lines)
   - WebView creation and configuration
   - Dual WebView architecture setup
   - User agent management
   - JavaScript injection (window.passage script with switchWebview and showBottomSheetModal)
   - Global JavaScript injection with WeakMap protection
   - WebView memory management and release
   - WebView readiness checks

   **WebViewModalViewController+JavaScript.swift** (638 lines)
   - Script injection and execution
   - WKScriptMessageHandler implementation
   - Command result handling
   - Page data collection
   - Browser state reporting
   - Message routing (navigate, close, setTitle, switchWebview, showBottomSheet)
   - Backend communication (sendToBackend)
   - Client-side navigation tracking

   **WebViewModalViewController+Screenshot.swift** (332 lines)
   - Screenshot capture functionality
   - Image optimization (resize, quality, format)
   - WebView snapshot using WKWebView.takeSnapshot()
   - Whole UI screenshot using UIGraphicsImageRenderer
   - Screenshot accessor setup for RemoteControlManager
   - Current/previous screenshot management

   **WebViewModalViewController+Navigation.swift** (741 lines)
   - URL loading and navigation
   - WKNavigationDelegate implementation
   - Back button functionality with history management
   - Navigation state tracking
   - Navigation timeout handling
   - Browser state change notifications
   - WebView data clearing
   - KVO for URL changes

   **WebViewModalViewController+UI.swift** (400 lines)
   - Header container with back/close buttons
   - WebView visibility switching (alpha-based)
   - Close confirmation flow
   - Loading indicators
   - Keyboard handling
   - Button animations
   - Title updates
   - Bottom sheet modal presentation and content updates

4. **BottomSheetViewController.swift** (260 lines)
   - Native iOS bottom sheet implementation
   - Adaptive height calculation with content fitting
   - Dynamic content updates (title, description, bullet points)
   - Optional close button with custom text
   - Modal presentation (swipe to dismiss, no tap-outside dismissal)
   - iOS 15+ UISheetPresentationController with custom detents

5. **PassageAnalytics.swift** (645 lines)
   - Comprehensive event tracking
   - Batched HTTP transport with retry logic
   - Device information collection
   - Session management

6. **PassageLogger.swift** (499 lines)
   - Multi-level logging (debug, info, warn, error)
   - HTTP log transport with batching
   - JWT session ID extraction
   - Sensitive data truncation

7. **PassageConstants.swift** (113 lines)
   - Centralized constant definitions
   - Message types (including switchWebview, showBottomSheet)
   - Event names, defaults
   - URL schemes and configuration keys
   - Separate UI and API URL configuration

## Core Components

### PassageSDK Main Class

```swift
public class Passage: NSObject {
    public static let shared = Passage()

    // Configuration
    private var config: PassageConfig

    // WebView components
    private var webViewController: WebViewModalViewController?
    private var navigationController: UINavigationController?

    // Remote control
    private var remoteControl: RemoteControlManager?

    // State management
    private var isClosing: Bool = false
    private var isPresentingModal: Bool = false

    // Callbacks
    private var onConnectionComplete: ((PassageSuccessData) -> Void)?
    private var onConnectionError: ((PassageErrorData) -> Void)?
    private var onDataComplete: ((PassageDataResult) -> Void)?
    private var onPromptComplete: ((PassagePromptResponse) -> Void)?
    private var onExit: ((String?) -> Void)?
    private var onWebviewChange: ((String) -> Void)?
}
```

#### Key Methods

1. **configure(_ config: PassageConfig)**
   - Configures SDK with UI URL, API URL, socket URL, debug flag
   - Initializes logger and analytics
   - Creates/updates RemoteControlManager

2. **open(_ options: PassageOpenOptions)**
   - Main entry point to present the modal
   - Handles auto-configuration if not configured
   - Manages WebView lifecycle (reuse or create)
   - Prevents concurrent presentations
   - Sets up callbacks and initializes remote control

3. **close()**
   - Programmatically closes the modal
   - Calls onExit callback with "programmatic_close"
   - Tracks analytics event

4. **Memory Management**
   - `releaseWebViewMemory()`: Releases WebView instances while preserving cookies/storage
   - `clearWebViewData()`: Completely clears all WebView data including localStorage
   - `clearAllCookies()`: Clears cookies only, preserves localStorage

### Data Structures

```swift
public struct PassageConfig {
    let uiUrl: String            // Default: "https://ui.runpassage.ai"
    let apiUrl: String           // Default: "https://api.runpassage.ai"
    let socketUrl: String        // Default: "https://api.runpassage.ai"
    let socketNamespace: String  // Default: "/ws"
    let debug: Bool
    let agentName: String        // Default: "passage-swift"

    // Deprecated: use uiUrl instead
    @available(*, deprecated, renamed: "uiUrl")
    var baseUrl: String { return uiUrl }
}

public struct PassageSuccessData {
    let history: [PassageHistoryItem]
    let connectionId: String
}

public struct PassageHistoryItem {
    let structuredData: Any?
    let additionalData: [String: Any]
}

public struct PassageOpenOptions {
    let intentToken: String?
    let prompts: [PassagePrompt]?
    let onConnectionComplete: ((PassageSuccessData) -> Void)?
    let onConnectionError: ((PassageErrorData) -> Void)?
    let onDataComplete: ((PassageDataResult) -> Void)?
    let onPromptComplete: ((PassagePromptResponse) -> Void)?
    let onExit: ((String?) -> Void)?
    let onWebviewChange: ((String) -> Void)?
    let presentationStyle: PassagePresentationStyle?
}
```

## Configuration and Initialization

### URL Configuration

The SDK uses separate URLs for different purposes:

1. **`uiUrl`**: Passage UI interface (`https://ui.runpassage.ai`)
   - Used for `/connect` endpoint
   - UI WebView navigation

2. **`apiUrl`**: Backend API (`https://api.runpassage.ai`)
   - Used for `/automation/configuration`
   - Used for `/automation/command-result`

3. **`socketUrl`**: WebSocket connection (`https://api.runpassage.ai`)
   - Socket.IO connection endpoint

**Backward Compatibility**: The deprecated `baseUrl` parameter maps to `uiUrl` for non-breaking changes.

```swift
// New configuration (recommended)
let config = PassageConfig(
    uiUrl: "https://ui.runpassage.ai",
    apiUrl: "https://api.runpassage.ai",
    socketUrl: "https://api.runpassage.ai",
    debug: true
)

// Legacy configuration (still supported)
let config = PassageConfig(
    baseUrl: "https://ui.runpassage.ai",  // Maps to uiUrl
    socketUrl: "https://api.runpassage.ai",
    debug: true
)
```

### SDK Initialization Flow

1. **Auto-configuration**: If `open()` is called without prior configuration, SDK auto-configures with defaults
2. **WebView User Agent Detection**: Creates temporary WebView to detect real user agent
3. **Configuration Fetch**: GET request to `{apiUrl}/automation/configuration` with intent token
4. **Socket Connection**: Establishes Socket.IO connection after config fetch
5. **Screenshot Timer**: Starts interval-based capture if JWT flags enable it

### Configuration Endpoint

**Request:**
```
GET {apiUrl}/automation/configuration
Headers:
  x-intent-token: {intentToken}
  x-webview-user-agent: {detectedWebViewUserAgent} // If available
```

**Response:**
```json
{
  "integration": {
    "url": "https://example.com",  // CRITICAL: Automation WebView URL
    "name": "Example",
    "slug": "example"
  },
  "cookieDomains": ["example.com"],
  "globalJavascript": "// Injected into automation WebView on every navigation",
  "automationUserAgent": "Custom User Agent",
  "imageOptimization": {
    "quality": 0.8,
    "maxWidth": 1920
  },
  "clearAllCookies": false  // Optional: Clear all cookies on initialization
}
```

## WebView Management

### Dual WebView Architecture - CRITICAL IMPLEMENTATION

⚠️ **CRITICAL**: The SDK MUST maintain **TWO WebView instances simultaneously** at all times. This is NOT a single WebView that switches content - both WebViews exist in memory concurrently.

#### WebView Instance Requirements

1. **UI WebView** (`webViewTypes.ui`, tag = 1)
   - **Purpose**: Displays Passage UI interface (`{uiUrl}/connect`)
   - **URL**: Always loads `{uiUrl}/connect?intentToken={token}`
   - **Visibility**: Visible when `userActionRequired = false` (background automation)
   - **Commands**: NEVER receives automation commands
   - **User Interaction**: Always accepts user input (scroll, tap, etc.)

2. **Automation WebView** (`webViewTypes.automation`, tag = 2)
   - **Purpose**: Executes automation commands on target website
   - **URL**: Loads `integration.url` from configuration endpoint
   - **Visibility**: Visible when `userActionRequired = true` (user action needed)
   - **Commands**: ALL automation commands execute here ONLY
   - **JavaScript**: Global JS injected on every navigation
   - **Back Navigation**: Supports back button and swipe gesture

#### Visibility Control Mechanism

**Method**: Alpha transparency control (NOT removing from view hierarchy)
- **Visible WebView**: `alpha = 1.0`
- **Hidden WebView**: `alpha = 0.0`
- **Both WebViews**: Always remain in view hierarchy and memory

```swift
func switchToUIWebView() {
    uiWebView.alpha = 1.0        // Show UI WebView
    automationWebView.alpha = 0.0 // Hide Automation WebView
}

func switchToAutomationWebView() {
    uiWebView.alpha = 0.0        // Hide UI WebView
    automationWebView.alpha = 1.0 // Show Automation WebView
}
```

## Navigation Controls

### Back Button Navigation

The automation WebView includes a back button for navigation history management:

**Visual Design:**
- Left arrow symbol (←)
- 26pt font size (20% smaller than close button's 32pt)
- Positioned on left side of header, mirroring close button
- Fade in/out animation (0.2s duration)

**Visibility Rules:**
Back button is visible only when ALL conditions are met:
1. Automation WebView is currently visible (not UI WebView)
2. Automation WebView has navigation history (`canGoBack`)
3. Back navigation is enabled (not disabled by programmatic navigate)

**Navigation Tracking:**
- Back button navigations do NOT send browser state to backend
- Uses `isNavigatingFromBackButton` flag to skip backend tracking
- Flag resets when navigation completes

**History Management:**
- Programmatic `navigate` commands clear navigation history
- Back navigation disabled until next user-initiated navigation
- History cleared via `loadHTMLString("", baseURL: nil)`

**Implementation:**
```swift
// Back button tap handler
@objc private func backButtonTapped() {
    guard !isBackNavigationDisabled else { return }
    guard automationWebView?.canGoBack else { return }

    isNavigatingFromBackButton = true
    automationWebView.goBack()

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        self.updateBackButtonVisibility()
    }
}

// Visibility update
private func updateBackButtonVisibility() {
    let isAutomationVisible = !isShowingUIWebView
    let hasHistory = automationWebView?.canGoBack ?? false
    let isEnabled = !isBackNavigationDisabled
    let shouldShow = isAutomationVisible && hasHistory && isEnabled

    UIView.animate(withDuration: 0.2) {
        backButton.alpha = shouldShow ? 1.0 : 0.0
    }

    // Enable/disable native swipe gesture
    automationWebView?.allowsBackForwardNavigationGestures = shouldShow
}

// Navigate command clears history
@objc private func navigateInAutomationNotification(_ notification: Notification) {
    // Clear history and disable back
    clearAutomationNavigationHistory()
    isBackNavigationDisabled = true

    navigateInAutomationWebView(url)
}

// Re-enable after navigation completes
func handleNavigationStateChange() {
    if !loading && isBackNavigationDisabled {
        isBackNavigationDisabled = false
        updateBackButtonVisibility()
    }
}
```

### Native Swipe Gesture

iOS native back gesture is enabled for automation WebView:

**Configuration:**
- Uses WKWebView's built-in `allowsBackForwardNavigationGestures` property
- Enabled/disabled based on same conditions as back button visibility
- Provides Apple's native swipe-from-left-edge animation
- No custom gesture recognizer needed

**Implementation:**
```swift
// Enable during WebView creation
if webViewType == PassageConstants.WebViewTypes.automation {
    webView.allowsBackForwardNavigationGestures = true
}

// Control via visibility updates
func updateBackButtonVisibility() {
    let shouldShow = isAutomationVisible && hasHistory && isEnabled
    automationWebView?.allowsBackForwardNavigationGestures = shouldShow
}
```

## Socket Communication

### Socket.IO Connection

```swift
// Connection setup
let socketUrl = config.socketUrl + config.socketNamespace
let manager = SocketManager(socketURL: URL(string: socketUrl)!,
                           config: [.compress, .forceWebsockets(true)])
let socket = manager.defaultSocket
```

### Socket Events

#### Outbound Events

1. **`join`**: Initial connection with intent token
   ```json
   {
     "intentToken": "jwt_token_here",
     "agentName": "passage-swift"
   }
   ```

2. **`commandResult`**: Command execution results
   ```json
   {
     "id": "command_123",
     "status": "success|error",
     "data": {},
     "pageData": {
       "url": "https://example.com",
       "html": "...",
       "cookies": [],
       "localStorage": [],
       "sessionStorage": [],
       "screenshot": "base64_image"
     }
   }
   ```

3. **`appStateUpdate`**: App lifecycle changes
4. **`modalExit`**: Modal closing event

#### Inbound Events

1. **`connected`**: Acknowledgment of join
2. **`connection`**: Connection success with data
3. **`command`**: Automation command
4. **`error`**: Connection or command errors
5. **`disconnect`**: Server-initiated disconnect

## Command Processing

Commands are received via Socket.IO and executed exclusively in the automation WebView.

### Command Types

1. **Navigate Command**: Navigate automation WebView to target URL
2. **Click Command**: Click element using JavaScript selector
3. **Input Command**: Input text into form field
4. **Wait Command**: Wait for element or condition
5. **InjectScript Command**: Execute custom JavaScript
6. **Done Command**: Complete automation session

### Command Result Reporting

Results are sent via both Socket.IO and HTTP (backup transport) to `{apiUrl}/automation/command-result`.

## Recording and Screenshots

### JWT Token Flags

The SDK extracts flags from the intent token JWT payload:

1. **`record`**: Full recording mode (captures entire screen)
2. **`captureScreenshot`**: WebView screenshot capture
3. **`captureScreenshotInterval`**: Interval in seconds (default: 5)
4. **`clearAllCookies`**: Clear all cookies on SDK initialization (added in latest version)

### Screenshot Capture

Timer-based capture using WKWebView.takeSnapshot() when enabled.

### Browser State Endpoint

Screenshots and page data sent to `{apiUrl}/automation/browser-state`.

## Analytics and Logging

### Analytics Events

All events include device info, session ID, timestamps, and metadata.

**Event Types:**
- Lifecycle: `sdkModalOpened`, `sdkModalClosed`
- Remote Control: `sdkRemoteControlConnectStart/Success/Error`
- Navigation: `sdkNavigationStart/Success/Error`
- Commands: `sdkCommandReceived/Success/Error`
- Results: `sdkOnSuccess`, `sdkOnError`
- WebView: `sdkWebViewSwitch`

### Logging

Multi-level logging (debug, info, warn, error) with HTTP transport to `{uiUrl}/api/logger`.

## Cookie and Storage Management

### Cookie Operations

```swift
func getCookies(for url: String) -> [HTTPCookie]
func setCookie(_ cookie: HTTPCookie)
func clearCookies(for url: String)
func clearAllCookies()
```

### Storage Management

```swift
func clearWebViewState()     // Clear navigation state only
func clearWebViewData()       // Clear everything
func resetWebViewURLs()       // Reset URLs to empty
```

## Constants and Types

### URL Configuration

```swift
public enum Defaults {
    public static let uiUrl = "https://ui.runpassage.ai"
    public static let apiUrl = "https://api.runpassage.ai"
    public static let socketUrl = "https://api.runpassage.ai"
    public static let socketNamespace = "/ws"
    public static let loggerEndpoint = "https://ui.runpassage.ai/api/logger"
    public static let agentName = "passage-swift"

    // Deprecated: use uiUrl instead
    @available(*, deprecated, message: "Use uiUrl instead")
    public static let baseUrl = "https://ui.runpassage.ai"
}
```

### Message Types

```swift
enum MessageTypes {
    static let connectionSuccess = "CONNECTION_SUCCESS"
    static let connectionError = "CONNECTION_ERROR"
    static let message = "message"
    static let navigate = "navigate"
    static let close = "close"
    static let backPressed = "backPressed"
    static let pageLoaded = "page_loaded"
    static let switchWebview = "switchWebview"
    static let showBottomSheet = "showBottomSheet"
}
```

### WebView Types

```swift
enum WebViewTypes {
    static let ui = "ui"
    static let automation = "automation"
}
```

### URL Paths

```swift
enum Paths {
    static let connect = "/connect"
    static let automationConfig = "/automation/configuration"
    static let automationCommandResult = "/automation/command-result"
}
```

## JavaScript Bridge API (window.passage)

The SDK injects a `window.passage` object into both UI and Automation webviews, providing a JavaScript API for communication with native Swift code.

### Available Methods

#### Navigation and Control

**`window.passage.navigate(url: string)`**
- Navigate the current webview to a URL
- Available in: UI and Automation webviews

**`window.passage.close()`**
- Close the modal
- Triggers onExit callback
- Available in: UI and Automation webviews

**`window.passage.setTitle(title: string)`**
- Update the modal title
- Available in: UI and Automation webviews

**`window.passage.switchWebview()`**
- Toggle between UI and Automation webviews
- Switches from currently visible webview to the other
- Available in: UI and Automation webviews
- Example:
  ```javascript
  // If UI webview is visible, switches to Automation
  // If Automation webview is visible, switches to UI
  window.passage.switchWebview();
  ```

#### Data and Communication

**`window.passage.postMessage(data: any)`**
- Send arbitrary data to native code
- Triggers onMessage callback
- Available in: UI and Automation webviews

- Send HTTP POST request to backend API
- Uses SDK's configured API URL
- Automatically includes intent token header
- Available in: UI and Automation webviews

**`window.passage.captureScreenshot()`**
- Trigger manual screenshot capture
- Only works if screenshot flags enabled in JWT
- Available in: UI and Automation webviews

#### UI Components

**`window.passage.showBottomSheetModal(params: object)`**
- Display native iOS bottom sheet modal
- Available in: UI and Automation webviews
- Parameters:
  - `title` (required): Main title text
  - `description` (optional): Descriptive text below title
  - `points` (optional): Array of bullet point strings
  - `closeButtonText` (optional): Text for close button (if provided, button is shown)
- Features:
  - Adaptive height (fits content, max 70% screen height)
  - **Swipe down to dismiss** (fully dismissible by pull gesture)
  - Grabber indicator at top
  - Rounded corners with iOS native styling
  - **Cannot dismiss by tapping outside overlay** (blocks tap-to-dismiss only)
  - Optional close button (only shown if `closeButtonText` provided)
  - **Updates content if called again while visible** (no duplicate modals)
- Example:
  ```javascript
  // With close button
  window.passage.showBottomSheetModal({
    title: "Connection Successful",
    description: "Your account has been linked successfully.",
    points: [
      "Access your data anytime",
      "Secure end-to-end encryption",
      "Automatic syncing enabled"
    ],
    closeButtonText: "Done"
  });

  // Minimal usage (only title, no button)
  window.passage.showBottomSheetModal({
    title: "Task Complete"
  });

  // With description only
  window.passage.showBottomSheetModal({
    title: "Welcome",
    description: "Thanks for connecting your account!"
  });

  // With custom close button text
  window.passage.showBottomSheetModal({
    title: "Success",
    closeButtonText: "Got it"
  });
  ```

#### WebView Type Detection

**`window.passage.getWebViewType(): string`**
- Returns: "ui" or "automation"
- Identifies which webview is running the script

**`window.passage.isUIWebView(): boolean`**
- Returns: true if running in UI webview

**`window.passage.isAutomationWebView(): boolean`**
- Returns: true if running in Automation webview

### Bottom Sheet Modal Implementation

The bottom sheet modal is implemented as a native iOS `UISheetPresentationController` (iOS 15+) with the following features:

#### Design Specifications

**Typography:**
- Title: SF Pro Display Bold, 25pt, center-aligned, black (`UIColor.label`)
- Description: SF Pro Text Regular, 16pt, left-aligned, black (`UIColor.label`) - optional
- Bullet points: System font 15pt with bullet character (•), left-aligned - optional

**Close Button (optional):**
- Background: Black (#000000)
- Text color: White
- Font: 17pt semibold
- Height: 50pt
- Corner radius: 12pt
- Full width with 16pt margins

**Layout & Spacing:**
- Top padding: 12pt
- Bottom padding: 12pt (consistent for all cases)
- Left/right margins: 16pt
- Title-to-description spacing: 8pt
- Description bottom padding: +16pt additional spacing
- Button top margin: 24pt above button (increased from 16pt)
- Button bottom margin: 12pt below button (increased from 0pt)
- Safe area aware for all edges

#### Behavior

**Presentation:**
- Adaptive height based on content (dynamically calculated)
- Maximum 70% of screen height
- **Swipe down to dismiss** (grabber enabled, fully dismissible)
- **Cannot dismiss by tapping overlay** (tap-outside blocked)
- Rounded corners with 16pt radius
- Smooth slide-up animation

**Content Updates:**
- **If called while already visible**: Updates content in place (no duplicate modal)
- Dynamic height recalculation on update
- Smooth content transitions
- Button visibility toggled based on `closeButtonText` parameter

**Height Calculation:**
- iOS 16+: Custom detent with exact content height
- iOS 15: Medium detent (approximate fit)
- Formula: `topPadding + contentHeight + bottomPadding + buttonHeight + buttonSpacing + safeAreaBottom`
- Content measured using `systemLayoutSizeFitting` before presentation
- Recalculated on content updates

#### Implementation Details

**BottomSheetViewController Class:**
```swift
class BottomSheetViewController: UIViewController {
    private var titleText: String           // Mutable for updates
    private var descriptionText: String?    // Optional
    private var bulletPoints: [String]?     // Optional
    private var closeButtonText: String?    // Optional - shows button if present

    // Public API
    func updateContent(title:description:points:closeButtonText:)  // Updates existing sheet
}
```

**Key Methods:**
- `init(title:description:points:closeButtonText:)` - Initialize with content
- `updateContent(title:description:points:closeButtonText:)` - Update content dynamically
- `configureSheet()` - Set up sheet presentation with adaptive height
- `createBulletLabel(text:)` - Create bullet point view with proper spacing

**Presentation Logic (WebViewModalViewController+UI.swift):**
```swift
func presentBottomSheet(title:description:points:closeButtonText:) {
    // Check if bottom sheet already presented
    if let existingBottomSheet = presentedViewController as? BottomSheetViewController {
        // Update content instead of presenting new modal
        existingBottomSheet.updateContent(...)
        return
    }

    // Create and present new bottom sheet
    let bottomSheetVC = BottomSheetViewController(...)
    present(bottomSheetVC, animated: true)
}
```

## Critical Implementation Notes

### 1. URL Configuration

**NEW**: Separate `uiUrl` and `apiUrl` for clarity:
- `uiUrl`: UI interface and logger endpoints
- `apiUrl`: Automation configuration and command results
- `socketUrl`: WebSocket connection
- `baseUrl`: Deprecated, maps to `uiUrl` for backward compatibility

### 2. Back Navigation

**NEW**: Back button and native swipe gesture:
- Back button hidden when UI WebView visible
- Navigation history cleared on programmatic navigate commands
- Back navigation disabled until next user-initiated navigation
- Native iOS swipe gesture via `allowsBackForwardNavigationGestures`
- Back button navigations skip backend browser state tracking

### 3. WebView Memory Management

- WebViews consume ~512MB due to JavaScriptCore
- Must release WebViews after modal close
- Cookies/localStorage persist in WKWebsiteDataStore
- WebViews recreated on next open()

### 4. Concurrent Presentation Prevention

```swift
if isPresentingModal {
    return // Ignore concurrent open() calls
}
isPresentingModal = true
```

### 5. Integration URL Critical

- **MUST** be provided in configuration response
- Without it, automation WebView never loads
- Logged as CRITICAL ERROR if missing

### 6. Global JavaScript Injection

- Injected on EVERY navigation in automation WebView
- If changed, WebView is recreated
- Can contain libraries like Sentry

### 7. Success URL Patterns

- Checked on both navigationStart and navigationEnd
- Automatically switches to UI WebView when matched
- Supports wildcard matching with *

### 8. Screenshot Capture

- Based on JWT flags, not configuration
- Interval defaults to 5 seconds
- Uses WKWebView.takeSnapshot() for proper capture

---

## Recent Enhancements

### Version 0.0.50 - OAuth and Popup Support

**Major Enhancement**: Full OAuth authentication support with popup window handling, enabling Google, Facebook, Microsoft, and other OAuth providers to work seamlessly in the SDK webviews.

#### OAuth Popup Support

**WKUIDelegate Implementation:**
- Added full `WKUIDelegate` protocol implementation for popup window handling
- Handles `window.open()` calls from JavaScript, including empty URL popups
- Supports JavaScript-controlled popup navigation (common OAuth pattern)
- Implements JavaScript alert, confirm, and prompt dialogs

**Popup Window Management:**
- Creates actual popup webviews for OAuth flows
- Visual popup display with semi-transparent overlay
- User-dismissible with close button (✕)
- Handles `window.close()` from JavaScript
- Supports multiple concurrent popups
- Proper memory management and cleanup

**Empty URL Popup Pattern:**
```javascript
// Common OAuth pattern now supported
const popup = window.open('', 'oauth_popup');
popup.location = 'https://accounts.google.com/oauth/...';
```

**OAuth Provider Detection:**
- Automatic detection of OAuth URLs from major providers:
  - Google (accounts.google.com, oauth2.googleapis.com)
  - Facebook (facebook.com, m.facebook.com)
  - Apple (appleid.apple.com)
  - Microsoft (login.microsoftonline.com)
  - GitHub, Twitter/X, LinkedIn
  - Generic OAuth paths (/oauth, /auth, /signin, /authorize)

**User Agent Configuration:**
- Custom user agent applied consistently to all webviews
- Popups inherit parent webview's user agent configuration
- User agent preserved across OAuth redirects
- Falls back to automation user agent or Safari default

**JavaScript Configuration:**
- `javaScriptCanOpenWindowsAutomatically = true` enabled for popup support
- Custom JavaScript injection maintained for all URLs (including OAuth)
- Console error tracking preserved in popups

**Target="_blank" Handling:**
- Links with `target="_blank"` load in current frame instead of being blocked
- Prevents popup blockers from interfering with OAuth flows

**External URL Scheme Support:**
- App-to-app OAuth support (googlechrome://, fb://, etc.)
- Universal Links handling
- Fallback to web-based OAuth when apps not installed

**ASWebAuthenticationSession Support:**
- Optional fallback using native iOS authentication session (iOS 12+)
- Shared cookies support
- Presentation context provider implementation

#### New Files Added

**WebViewModalViewController+OAuth.swift** (~295 lines):
- OAuth URL detection and provider identification
- User agent management for OAuth flows
- External URL scheme handling
- Popup window management
- OAuth callback parameter extraction
- ASWebAuthenticationSession integration

#### Modified Components

**WebViewModalViewController.swift:**
- Added `WKUIDelegate` protocol conformance
- Added popup tracking: `popupWebViews: [PassageWKWebView]`
- Added popup container view management

**WebViewModalViewController+Navigation.swift:**
- Implemented `createWebViewWith` for popup creation
- Implemented JavaScript dialog handlers (alert/confirm/prompt)
- Implemented `webViewDidClose` for popup cleanup
- Added `closePopup`, `closeAllPopups`, `closeTopPopup` methods
- OAuth-aware navigation policy updates
- Target="_blank" link handling

**WebViewModalViewController+WebViewSetup.swift:**
- Set `uiDelegate` on webview creation
- Enabled `javaScriptCanOpenWindowsAutomatically`
- User agent configuration updated for OAuth compatibility

#### OAuth Flow Support

**Supported OAuth Patterns:**
1. Direct OAuth URL navigation
2. Popup with immediate URL (`window.open('https://oauth...')`)
3. Empty popup + JavaScript navigation (`window.open('') + popup.location = '...'`)
4. Multiple redirects during OAuth flow
5. Post-OAuth callback handling
6. App-to-app authentication (when apps installed)

**What Works Now:**
- ✅ Google OAuth (all methods)
- ✅ Facebook OAuth
- ✅ Microsoft OAuth
- ✅ Apple Sign In (web)
- ✅ GitHub OAuth
- ✅ Twitter/X OAuth
- ✅ LinkedIn OAuth
- ✅ Custom OAuth providers

**Key Features:**
- Popups display as centered overlays (90% width, 80% height)
- Semi-transparent black background (50% opacity)
- Close button in top-right corner
- Proper cookie persistence across OAuth flow
- User agent consistency maintained
- JavaScript functionality preserved
- Memory efficient cleanup

**Breaking Changes:** None - fully backward compatible

---

### Version 3.1.0 - WebView Switching and Bottom Sheet

### WebView Switching API

Added `window.passage.switchWebview()` method to toggle between UI and Automation webviews programmatically from JavaScript.

**Features:**
- Works from either webview
- Smooth alpha-based transition (0.2s)
- Automatic back button visibility updates
- Bidirectional switching (UI ↔ Automation)

**Use Cases:**
- Manual control over webview visibility
- Custom navigation flows
- Progressive disclosure patterns

### Bottom Sheet Modal Component

Added `window.passage.showBottomSheetModal(params)` for native iOS bottom sheet presentation.

**Key Features:**
- Native iOS `UISheetPresentationController` (iOS 15+)
- Adaptive height with content fitting
- Optional close button with custom text
- Content updates in place (no duplicate modals)
- Swipe down to dismiss (tap-outside disabled)
- 28pt title (25% larger for prominence)
- Black close button styling

**Parameters:**
- `title` (required): Main heading
- `description` (optional): Body text
- `points` (optional): Bullet list array
- `closeButtonText` (optional): Button text (shows button if provided)

**Design Highlights:**
- Black button background (#000000), white text
- 50pt button height, 12pt corner radius
- 17pt semibold font
- 28pt title for visual hierarchy
- Left-aligned description text
- Generous padding (50% increase) for breathing room

**Smart Behavior:**
- Detects existing bottom sheet and updates content
- Prevents duplicate modal presentations
- Recalculates height on content changes
- iOS 16+: Exact height custom detent
- iOS 15: Medium detent fallback

### Message Type Additions

Added to `PassageConstants.MessageTypes`:
- `switchWebview` - Toggle webview visibility
- `showBottomSheet` - Present bottom sheet modal

---

**Document Version**: 0.0.50
**Last Updated**: 2025-09-29
**Status**: Current Implementation
**Platform**: iOS/macOS Swift SDK
**Recent Changes**:
- Added full OAuth authentication support
- Implemented WKUIDelegate for popup handling
- Added popup window management system
- Support for empty URL popups + JS navigation
- Custom user agent consistency across OAuth flows
- JavaScript injection maintained for OAuth
- Target="_blank" and external URL scheme handling
- OAuth provider auto-detection
- ASWebAuthenticationSession integration