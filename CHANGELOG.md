# Changelog

All notable changes to the PassageSDK will be documented in this file.

## [Unreleased]

### Added
- **Enhanced Popup Support in WebViews** - Improved JavaScript popup handling:
  - Set `javaScriptCanOpenWindowsAutomatically` to `true` in WebView configuration
  - Implemented `WKUIDelegate` protocol for handling window.open() requests
  - Added support for JavaScript alert(), confirm(), and prompt() dialogs
  - **NEW**: Support for deferred popup navigation (e.g., `var popup = window.open(); popup.location = url;`)
  - **NEW**: Creates temporary popup WebView for empty window.open() calls
  - **NEW**: Automatically transfers popup navigation to main WebView when URL is assigned
  - **NEW**: Proper cleanup and tracking of popup WebViews

- **Clear All Cookies Support** - Added automatic cookie clearing based on configuration:
  - Extracts `clearAllCookies` flag from JWT token payload
  - Checks `clearAllCookies` flag in configuration response from backend
  - Automatically clears all cookies when flag is detected on initialization
  - Uses notification system for cross-component communication

### Fixed
- **Navigation Command Results** - Fixed regression where navigate commands wouldn't receive results when WebView was already on target URL
  - Now properly calls `handleNavigationComplete()` to collect page data and send results
  - Ensures consistent command result behavior across all navigation scenarios
  - Added comprehensive logging throughout navigation flow for debugging
  - Added JavaScript navigation state tracking to detect URL changes
  - Enhanced logging in RemoteControlManager for command handling visibility

- **OAuth Callback Page Stuck Issue** - Fixed issue where users get stuck on OAuth callback pages after successful authentication
  - Added OAuth completion detection for callback URLs
  - Intercepts `window.opener` access to detect OAuth popup scenarios
  - Intercepts `window.close()` to detect and handle failed close attempts
  - Automatically navigates back to original target URL on successful OAuth (success: true)
  - Stores original navigation URL from first command in SDK (native side)
  - Injects original URL into JavaScript context for OAuth recovery
  - Clears `socialLoginResponse` from localStorage after handling to prevent re-triggering
  - Checks localStorage for `socialLoginResponse` to validate OAuth completion
  - Added comprehensive JavaScript logging for OAuth flow debugging

## [0.0.50] - 2024-12-29

### New Features

#### JavaScript Bridge Methods
- **`window.passage.switchWebview()`** - Toggle between UI and Automation webviews programmatically
- **`window.passage.showBottomSheetModal(params)`** - Display native iOS bottom sheet with customizable content:
  - `title` (required): Sheet title
  - `description` (optional): Descriptive text
  - `points` (optional): Array of bullet points
  - `closeButtonText` (optional): Button text, if provided shows dismissal button

#### Native Bottom Sheet
- Adaptive height based on content
- Swipe-to-dismiss enabled
- Tap-outside dismissal disabled
- Dynamic content updates if called while already visible
- Custom detent sizing for iOS 16+

### Architecture Improvements
- Split WebView logic into multiple extension files for better maintainability:
  - WebViewSetup, Navigation, JavaScript handling, UI management, and Network operations
- Added new `BottomSheetViewController` component for native modal presentation

### Constants
- Added new message types: `switchWebview`, `showBottomSheet`
- Extended JavaScript bridge communication protocol