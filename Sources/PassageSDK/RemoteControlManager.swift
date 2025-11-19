#if canImport(UIKit)
import Foundation
import WebKit
import SocketIO

// MARK: - Remote Control Types

public struct RemoteCommand {
    let id: String
    let type: CommandType
    let args: [String: Any]?
    let injectScript: String?
    let cookieDomains: [String]?
    let userActionRequired: Bool?

    enum CommandType: String {
        case navigate = "navigate"
        case click = "click"
        case input = "input"
        case wait = "wait"
        case injectScript = "injectScript"
        case done = "done"
    }
}

struct CommandResult: Codable {
    let id: String
    let status: String
    let data: AnyCodable?
    let pageData: PageData?
    let error: String?
}

struct PageData: Codable {
    let cookies: [CookieData]?
    let localStorage: [StorageItem]?
    let sessionStorage: [StorageItem]?
    let html: String?
    let url: String?
    let screenshot: String?
}

struct CookieData: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String?
    let expires: Double?
    let secure: Bool?
    let httpOnly: Bool?
    let sameSite: String
}

struct StorageItem: Codable {
    let name: String
    let value: String
}

struct SuccessUrl: Codable {
    let urlPattern: String
    let navigationType: String

    enum NavigationType: String {
        case navigationStart = "navigationStart"
        case navigationEnd = "navigationEnd"
    }
}

struct SessionCommandResponseBody: Codable {
  let commandResponse: SessionCommandResponse
}

struct SessionCommandResponse: Codable {
    let at: String
    let data: CommandResult
}

// AnyCodable is defined in PassageAnalytics.swift

// MARK: - RemoteControlManager

class RemoteControlManager {
    private let config: PassageConfig
    private var manager: SocketManager?
    private var socket: SocketIOClient?
    private var isConnected: Bool = false
    private var intentToken: String?
    private var onSuccess: ((PassageSuccessData) -> Void)?
    private var onError: ((PassageErrorData) -> Void)?
    private var onDataComplete: ((PassageDataResult) -> Void)?
    private var onPromptComplete: ((PassagePromptResponse) -> Void)?
    private var cookieDomains: [String] = []
    private var connectionData: [[String: Any]]? = nil
    private var connectionId: String? = nil
    private var globalJavascript: String = ""
    private var automationUserAgent: String = ""
    private var integrationUrl: String?
    private var configImageOptimization: [String: Any]? = nil
    private var currentWebViewType: String = PassageConstants.WebViewTypes.ui
    private var lastUserActionCommand: RemoteCommand?
    private var currentCommand: RemoteCommand?
    private var lastWaitCommand: RemoteCommand? // Track wait commands for reinjection
    private var onConfigurationUpdated: ((_ userAgent: String, _ integrationUrl: String?) -> Void)?

    // Weak reference to view controller for record mode UI locking
    weak var viewController: WebViewModalViewController?

    // Record mode script reinjection support (matching React Native SDK)
    private var lastInjectScript: String?
    private var lastInjectScriptCommandId: String?
    private var lastInjectScriptCommand: RemoteCommand?

    // Success URLs for navigation commands
    private var currentSuccessUrls: [SuccessUrl] = []

    // Screenshot and record mode support
    private var screenshotAccessors: ScreenshotAccessors?
    private var captureImageFunction: CaptureImageFunction?

    // Screenshot interval capture support
    private var screenshotTimer: Timer?
    private var screenshotInterval: TimeInterval?

    // WebView user agent detection
    private var detectedWebViewUserAgent: String?

    // Redirect control for done command (can be disabled via JavaScript)
    private var redirectOnDoneCommand: Bool = true

    // Screenshot accessor protocols (matching React Native)
    typealias ScreenshotAccessors = (
        getCurrentScreenshot: () -> String?,
        getPreviousScreenshot: () -> String?
    )

    typealias CaptureImageFunction = () async -> String?

    init(config: PassageConfig) {
        self.config = config
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        // Observe navigation completion for sending command results
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNavigationCompleted(_:)),
            name: .navigationCompleted,
            object: nil
        )

        // Observe script execution results
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScriptExecutionResult(_:)),
            name: .scriptExecutionResult,
            object: nil
        )

        // Observe browser state updates
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSendBrowserState(_:)),
            name: .sendBrowserState,
            object: nil
        )

        // Observe app state changes for websocket events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleNavigationCompleted(_ notification: Notification) {
        passageLogger.info("[REMOTE CONTROL] handleNavigationCompleted called")

        guard let url = notification.userInfo?["url"] as? String,
              let webViewType = notification.userInfo?["webViewType"] as? String,
              webViewType == PassageConstants.WebViewTypes.automation,
              let command = currentCommand,
              command.type == .navigate else {
            passageLogger.warn("[REMOTE CONTROL] Navigation completed but missing required data or not navigation command")
            passageLogger.debug("[REMOTE CONTROL] URL: \(notification.userInfo?["url"] as? String ?? "nil")")
            passageLogger.debug("[REMOTE CONTROL] WebViewType: \(notification.userInfo?["webViewType"] as? String ?? "nil")")
            passageLogger.debug("[REMOTE CONTROL] Current command: \(currentCommand?.id ?? "nil") type: \(currentCommand?.type.rawValue ?? "nil")")
            return
        }

        passageLogger.info("[REMOTE CONTROL] Navigation completed for command: \(command.id) Final URL: \(url)")

        sendSuccess(commandId: command.id, data: ["url": url])

        // Clear the current command
        currentCommand = nil
    }

    // Add method to handle navigation completion from WebView (matches React Native)
    func handleNavigationComplete(_ url: String) {
        passageLogger.debug("[REMOTE CONTROL] Navigation complete called for URL: \(passageLogger.truncateUrl(url, maxLength: 100))")

        // Handle navigation command completion
        if let command = currentCommand, command.type == .navigate {
            passageLogger.info("[REMOTE CONTROL] Completing navigation command: \(command.id) Final URL: \(url)")
            sendSuccess(commandId: command.id, data: ["url": url])
            currentCommand = nil
        }

        // 🔑 RECORD MODE: Reinject injectScript commands after navigation
        let isRecordMode = getRecordFlag()
        passageLogger.debug("[REMOTE CONTROL] Record mode: \(isRecordMode), has injectScriptCommand: \(lastInjectScriptCommand != nil)")

        if isRecordMode, let injectScriptCommand = lastInjectScriptCommand, injectScriptCommand.type == .injectScript {
            passageLogger.debug("[REMOTE CONTROL] Re-injecting injectScript command after navigation (record mode): \(injectScriptCommand.id)")

            // Add a delay to ensure page is fully loaded before reinjecting
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.handleScriptExecution(injectScriptCommand)
            }
        } else {
            // Fallback to wait command reinjection for backward compatibility
            if let waitCommand = lastWaitCommand {
                passageLogger.debug("[REMOTE CONTROL] Re-injecting wait command after navigation: \(waitCommand.id)")

                // Add a delay to ensure page is fully loaded before reinjecting
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.handleScriptExecution(waitCommand)
                }
            }
        }
    }

    // MARK: - Record Mode Script Reinjection

    /// Determine if scripts should be reinjected after navigation (matches React Native SDK)
    private func shouldReinjectScript() -> Bool {
        let isRecordMode = getRecordFlag()
        let hasUserActionCommand = lastUserActionCommand != nil

        // 🔑 In record mode, reinject on all navigation changes
        if isRecordMode {
            passageLogger.debug("[REMOTE CONTROL] shouldReinjectScript: true (record mode)")
            return true
        }

        // In non-record mode, only reinject for user action commands
        if hasUserActionCommand && currentCommand != nil {
            passageLogger.debug("[REMOTE CONTROL] shouldReinjectScript: true (user action command)")
            return true
        }

        passageLogger.debug("[REMOTE CONTROL] shouldReinjectScript: false")
        return false
    }

    @objc private func handleScriptExecutionResult(_ notification: Notification) {
        guard let commandId = notification.userInfo?["commandId"] as? String,
              let success = notification.userInfo?["success"] as? Bool else {
            passageLogger.error("[REMOTE CONTROL] Script execution result missing required data")
            return
        }

        passageLogger.info("[REMOTE CONTROL] Script execution result for command: \(commandId), success: \(success)")

        // Clear wait command if it completed (successfully or not)
        if let waitCommand = lastWaitCommand, waitCommand.id == commandId {
            passageLogger.debug("[REMOTE CONTROL] Clearing completed wait command: \(commandId)")
            lastWaitCommand = nil
        }

        if success {
            let result = notification.userInfo?["result"]
            sendSuccess(commandId: commandId, data: result)
        } else {
            let error = notification.userInfo?["error"] as? String ?? "Script execution failed"
            sendError(commandId: commandId, error: error)
        }
    }

    @objc private func handleSendBrowserState(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? String else {
            passageLogger.error("[SEND BROWSER STATE] ❌ Browser state notification missing required URL")
            passageLogger.error("[SEND BROWSER STATE] Available userInfo keys: \(notification.userInfo?.keys.sorted { "\($0)" < "\($1)" } ?? [])")
            return
        }

        // Extract additional browser state data (matching React Native WebView pattern)
        // Convert from [AnyHashable: Any] to [String: Any]
        var browserStateData: [String: Any] = [:]
        if let userInfo = notification.userInfo {
            for (key, value) in userInfo {
                if let stringKey = key as? String {
                    browserStateData[stringKey] = value
                }
            }
        }

        // Log screenshot information
        if let screenshot = browserStateData["screenshot"] as? String {
            passageLogger.debug("[SEND BROWSER STATE] ✅ Screenshot included: \(screenshot.count) chars")
        } else if browserStateData["screenshot"] != nil {
            passageLogger.warn("[SEND BROWSER STATE] ⚠️ Screenshot field present but not String: \(type(of: browserStateData["screenshot"]!))")
        } else {
            passageLogger.warn("[SEND BROWSER STATE] ⚠️ No screenshot in browser state data")
        }

        // Log other fields
        if let trigger = browserStateData["trigger"] as? String {
            passageLogger.debug("[SEND BROWSER STATE] Trigger: \(trigger)")
        }

        if let interval = browserStateData["interval"] as? TimeInterval {
            passageLogger.debug("[SEND BROWSER STATE] Interval: \(interval)")
        }

        if let imageOpt = browserStateData["imageOptimization"] as? [String: Any] {
            passageLogger.debug("[SEND BROWSER STATE] Image optimization: \(imageOpt)")
        }

        // Send browser state to backend
        Task {
            await sendBrowserStateToBackend(browserStateData: browserStateData)
        }
    }

    // MARK: - App State Handling

    @objc private func appDidBecomeActive() {
        emitAppStateUpdate("active")
    }

    @objc private func appWillResignActive() {
        emitAppStateUpdate("inactive")
    }

    @objc private func appDidEnterBackground() {
        emitAppStateUpdate("background")
    }

    @objc private func appWillEnterForeground() {
        // When coming from background to foreground, we'll transition through inactive first
        // The appDidBecomeActive will fire shortly after and set it to active
        emitAppStateUpdate("inactive")
    }

    private func emitAppStateUpdate(_ state: String) {
        // Only emit if socket is connected
        guard let socket = socket, socket.status == .connected else {
            passageLogger.debug("[REMOTE CONTROL] App state changed to '\(state)' but socket not connected")
            return
        }

        passageLogger.debug("[REMOTE CONTROL] Emitting appStateUpdate event - state: \(state)")

        let appStateData: [String: Any] = [
            "state": state,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "intentToken": intentToken ?? ""
        ]

        socket.emit("appStateUpdate", appStateData)
    }

    // MARK: - Browser State Management

    private func sendBrowserStateToBackend(browserStateData: [String: Any]) async {
        guard let intentToken = intentToken else {
            passageLogger.error("[BROWSER STATE] ❌ No intent token available for sending browser state")
            return
        }

        guard let url = browserStateData["url"] as? String else {
            passageLogger.error("[BROWSER STATE] ❌ Browser state data missing required URL field")
            passageLogger.error("[BROWSER STATE] Available fields: \(browserStateData.keys.sorted())")
            return
        }

        passageLogger.info("[BROWSER STATE] URL: \(url)")

        let urlString = "\(config.socketUrl)/automation/browser-state"

        guard let apiUrl = URL(string: urlString) else {
            passageLogger.error("[BROWSER STATE] ❌ Invalid URL: \(urlString)")
            return
        }

        var request = URLRequest(url: apiUrl)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(intentToken, forHTTPHeaderField: "x-intent-token")

        // Create browser state payload - only include fields defined in BrowserStateRequestDto
        var browserState: [String: Any] = [
            "url": url
            // Optional fields that can be added when available:
            // - html: document.documentElement.outerHTML
            // - localStorage: collected from webview
            // - sessionStorage: collected from webview
            // - cookies: collected from WKWebsiteDataStore
            // - screenshot: captured from webview
        ]

        // Add screenshot if provided
        if let screenshot = browserStateData["screenshot"] as? String, !screenshot.isEmpty {
            browserState["screenshot"] = screenshot
        } else {
            passageLogger.warn("[BROWSER STATE] ⚠️ No screenshot included in browser state")
            if let screenshot = browserStateData["screenshot"] {
                passageLogger.debug("[BROWSER STATE] Screenshot field present but: \(type(of: screenshot)) = \(screenshot)")
            } else {
                passageLogger.debug("[BROWSER STATE] No screenshot field in browserStateData")
            }
        }

        // Log metadata for debugging but don't include in request
        // (These fields are not defined in BrowserStateRequestDto)
        if let imageOptimization = browserStateData["imageOptimization"] as? [String: Any] {
            passageLogger.debug("[BROWSER STATE] Image optimization parameters available: \(imageOptimization) (not sent to server)")
        }

        if let trigger = browserStateData["trigger"] as? String {
            passageLogger.debug("[BROWSER STATE] Trigger: \(trigger) (not sent to server)")
        }

        if let interval = browserStateData["interval"] as? TimeInterval {
            passageLogger.debug("[BROWSER STATE] Capture interval: \(interval) (not sent to server)")
        }

        // Log final payload summary
        let hasScreenshot = browserState["screenshot"] != nil

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: browserState)
            request.httpBody = jsonData

            passageLogger.debug("[BROWSER STATE] 🚀 Sending browser state POST request...")
            passageLogger.debug("[BROWSER STATE] Request size: \(jsonData.count) bytes")

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                    passageLogger.info("[BROWSER STATE] ✅ Browser state sent successfully - Status: \(httpResponse.statusCode)")
                    if let responseData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        passageLogger.debug("[BROWSER STATE] Response: \(responseData)")
                    }
                } else {
                    passageLogger.error("[BROWSER STATE] ❌ Browser state request failed - Status: \(httpResponse.statusCode)")
                    if let responseString = String(data: data, encoding: .utf8) {
                        passageLogger.error("[BROWSER STATE] Response: \(responseString)")
                    }
                }
            }
        } catch {
            passageLogger.error("[BROWSER STATE] ❌ Failed to send browser state: \(error)")
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func updateConfig(_ config: PassageConfig) {
        // Update config if needed
    }

    // MARK: - Record Mode and Screenshot Support

    func getRecordFlag() -> Bool {
        guard let intentToken = intentToken else { return false }
        return extractRecordFlag(from: intentToken)
    }

    func setScreenshotAccessors(_ accessors: ScreenshotAccessors?) {
        self.screenshotAccessors = accessors
    }

    func setCaptureImageFunction(_ captureImageFn: CaptureImageFunction?) {
        self.captureImageFunction = captureImageFn
    }

    private func extractRecordFlag(from token: String) -> Bool {
        // Extract record flag from JWT token (matching React Native implementation)
        passageLogger.debug("[JWT DECODE] Extracting record flag from token")
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else {
            passageLogger.error("[JWT DECODE] Invalid JWT format - expected 3 components, got \(components.count)")
            return false
        }

        let payload = components[1]
        passageLogger.debug("[JWT DECODE] JWT payload (raw): \(payload)")
        let paddedPayload = addPadding(to: payload)
        passageLogger.debug("[JWT DECODE] JWT payload (padded): \(paddedPayload)")

        guard let data = Data(base64Encoded: paddedPayload) else {
            passageLogger.error("[JWT DECODE] Failed to decode base64 payload")
            return false
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                passageLogger.debug("[JWT DECODE] ✅ Successfully decoded JWT payload: \(json)")
                if let record = json["record"] as? Bool {
                    passageLogger.info("[JWT DECODE] Found record flag: \(record)")
                    return record
                } else {
                    passageLogger.warn("[JWT DECODE] No 'record' field found in JWT payload")
                }
            }
        } catch {
            passageLogger.error("[JWT DECODE] Failed to decode record flag from intent token: \(error)")
        }

        return false
    }

    func getCaptureScreenshotFlag() -> Bool {
        guard let intentToken = intentToken else { return false }
        return extractCaptureScreenshotFlag(from: intentToken)
    }

    func getCaptureScreenshotInterval() -> TimeInterval? {
        guard let intentToken = intentToken else { return nil }
        let extractedInterval = extractCaptureScreenshotInterval(from: intentToken)
        if extractedInterval == nil {
            passageLogger.debug("[JWT DECODE] Using default captureScreenshotInterval: 5.0 seconds")
        }
        return extractedInterval ?? 5.0 // Default to 5 seconds
    }

    func getImageOptimizationParameters() -> [String: Any]? {
        // Use configuration parameters instead of JWT parameters
        return configImageOptimization
    }

    func getIntentToken() -> String? {
        return intentToken
    }

    func getBaseUrl() -> String {
        return config.uiUrl
    }

    func getApiUrl() -> String {
        return config.apiUrl
    }

    func getSessionUrl() -> String {
        return config.sessionUrl
    }

    /// Set whether to redirect on done command (can be called from JavaScript via window.passage.setRedirectOnDoneCommand)
    func setRedirectOnDoneCommand(_ enabled: Bool) {
        passageLogger.debug("[REMOTE CONTROL] setRedirectOnDoneCommand called: \(enabled)")
        redirectOnDoneCommand = enabled
    }

    /// Get current redirect on done command setting
    func getRedirectOnDoneCommand() -> Bool {
        return redirectOnDoneCommand
    }

    private func extractCaptureScreenshotFlag(from token: String) -> Bool {
        passageLogger.debug("[JWT DECODE] Extracting captureScreenshot flag from token")
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else {
            passageLogger.error("[JWT DECODE] Invalid JWT format for captureScreenshot - expected 3 components, got \(components.count)")
            return false
        }

        let payload = components[1]
        guard let data = Data(base64Encoded: addPadding(to: payload)) else {
            passageLogger.error("[JWT DECODE] Failed to decode base64 payload for captureScreenshot")
            return false
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let captureScreenshot = json["captureScreenshot"] as? Bool {
                    passageLogger.debug("[JWT DECODE] ✅ Found captureScreenshot flag: \(captureScreenshot)")
                    return captureScreenshot
                } else {
                    passageLogger.warn("[JWT DECODE] No 'captureScreenshot' field found in JWT payload")
                    passageLogger.debug("[JWT DECODE] Available fields: \(json.keys.sorted())")
                }
            }
        } catch {
            passageLogger.error("[JWT DECODE] Failed to decode captureScreenshot flag from intent token: \(error)")
        }

        return false
    }

    private func extractCaptureScreenshotInterval(from token: String) -> TimeInterval? {
        passageLogger.debug("[JWT DECODE] Extracting captureScreenshotInterval from token")
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else {
            passageLogger.error("[JWT DECODE] Invalid JWT format for interval - expected 3 components, got \(components.count)")
            return nil
        }

        let payload = components[1]
        guard let data = Data(base64Encoded: addPadding(to: payload)) else {
            passageLogger.error("[JWT DECODE] Failed to decode base64 payload for interval")
            return nil
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Support both number (seconds) and string formats
                if let intervalSeconds = json["captureScreenshotInterval"] as? Double {
                    passageLogger.debug("[JWT DECODE] ✅ Found captureScreenshotInterval (Double): \(intervalSeconds)")
                    return intervalSeconds
                } else if let intervalInt = json["captureScreenshotInterval"] as? Int {
                    passageLogger.debug("[JWT DECODE] ✅ Found captureScreenshotInterval (Int): \(intervalInt)")
                    return Double(intervalInt)
                } else if let intervalString = json["captureScreenshotInterval"] as? String,
                          let intervalSeconds = Double(intervalString) {
                    passageLogger.debug("[JWT DECODE] ✅ Found captureScreenshotInterval (String): \(intervalString) -> \(intervalSeconds)")
                    return intervalSeconds
                } else {
                    passageLogger.warn("[JWT DECODE] No 'captureScreenshotInterval' field found in JWT payload - will use default 5s interval")
                    if let intervalValue = json["captureScreenshotInterval"] {
                        passageLogger.warn("[JWT DECODE] captureScreenshotInterval has unexpected type: \(type(of: intervalValue)) = \(intervalValue) - will use default 5s interval")
                    }
                }
            }
        } catch {
            passageLogger.error("[JWT DECODE] Failed to decode captureScreenshotInterval from intent token: \(error)")
        }

        return nil
    }

    // Note: extractImageOptimizationParameters removed - now using configuration instead of JWT

    func extractClearAllCookiesFlag(from token: String) -> Bool {
        passageLogger.debug("[JWT DECODE] Extracting clearAllCookies flag from token")
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else {
            passageLogger.error("[JWT DECODE] Invalid JWT format for clearAllCookies - expected 3 components, got \(components.count)")
            return false
        }

        let payload = components[1]
        guard let data = Data(base64Encoded: addPadding(to: payload)) else {
            passageLogger.error("[JWT DECODE] Failed to decode base64 payload for clearAllCookies")
            return false
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let clearAllCookies = json["clearAllCookies"] as? Bool {
                    passageLogger.debug("[JWT DECODE] ✅ Found clearAllCookies flag: \(clearAllCookies)")
                    return clearAllCookies
                } else {
                    passageLogger.debug("[JWT DECODE] No 'clearAllCookies' field found in JWT payload")
                }
            }
        } catch {
            passageLogger.error("[JWT DECODE] Failed to decode clearAllCookies flag from intent token: \(error)")
        }

        return false
    }

    func extractCookieDomains(from token: String) -> [String]? {
        passageLogger.debug("[JWT DECODE] Extracting cookieDomains from token")
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else {
            passageLogger.error("[JWT DECODE] Invalid JWT format for cookieDomains - expected 3 components, got \(components.count)")
            return nil
        }

        let payload = components[1]
        guard let data = Data(base64Encoded: addPadding(to: payload)) else {
            passageLogger.error("[JWT DECODE] Failed to decode base64 payload for cookieDomains")
            return nil
        }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let domains = json["cookieDomains"] as? [String] {
                    passageLogger.debug("[JWT DECODE] ✅ Found cookieDomains in JWT: \(domains)")
                    return domains
                } else {
                    passageLogger.debug("[JWT DECODE] No 'cookieDomains' field found in JWT payload")
                }
            }
        } catch {
            passageLogger.error("[JWT DECODE] Failed to decode cookieDomains from intent token: \(error)")
        }

        return nil
    }

    private func extractSessionId(from token: String) -> String? {
        let components = token.components(separatedBy: ".")
        guard components.count == 3 else { return nil }

        let payload = components[1]
        let paddedPayload = addPadding(to: payload)

        guard let data = Data(base64Encoded: paddedPayload) else { return nil }

        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sessionId = json["sessionId"] as? String {
                return sessionId
            }
        } catch {
            return nil
        }
        return nil
    }

    func getClearAllCookiesFlag() -> Bool {
        guard let intentToken = intentToken else { return false }
        return extractClearAllCookiesFlag(from: intentToken)
    }

    func getCookieDomains(from token: String) -> [String]? {
        // First check JWT
        if let jwtDomains = extractCookieDomains(from: token), !jwtDomains.isEmpty {
            passageLogger.debug("[REMOTE CONTROL] Using cookieDomains from JWT: \(jwtDomains)")
            return jwtDomains
        }

        // Then check configuration
        if !cookieDomains.isEmpty {
            passageLogger.debug("[REMOTE CONTROL] Using cookieDomains from configuration: \(cookieDomains)")
            return cookieDomains
        }

        passageLogger.debug("[REMOTE CONTROL] No cookieDomains found in JWT or configuration")
        return nil
    }

    // MARK: - Screenshot Capture Methods

    /// Start interval-based screenshot capture if JWT flags are enabled
    private func startScreenshotCapture() {
        passageLogger.debug("[SCREENSHOT TIMER] ========== STARTING SCREENSHOT CAPTURE ==========")

        // Stop any existing timer
        stopScreenshotCapture()

        // Check if capture is enabled and get interval
        let captureFlag = getCaptureScreenshotFlag()
        passageLogger.debug("[SCREENSHOT TIMER] Capture screenshot flag: \(captureFlag)")

        guard captureFlag else {
            passageLogger.warn("[SCREENSHOT TIMER] ❌ Screenshot capture disabled by JWT flag - no timer will be created")
            return
        }

        let interval = getCaptureScreenshotInterval()
        passageLogger.debug("[SCREENSHOT TIMER] Screenshot interval (JWT or default): \(interval?.description ?? "nil")")

        guard let interval = interval, interval > 0 else {
            passageLogger.error("[SCREENSHOT TIMER] ❌ No valid screenshot interval available - no timer will be created")
            return
        }

        screenshotInterval = interval
        passageLogger.debug("[SCREENSHOT TIMER] ✅ Starting screenshot capture with \(interval)s interval")

        // Ensure we're on the main thread for timer creation
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                passageLogger.error("[SCREENSHOT TIMER] ❌ Self is nil when creating timer")
                return
            }

            // Create timer for periodic screenshots
            self.screenshotTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
                passageLogger.debug("[SCREENSHOT TIMER] 📸 Timer fired - capturing screenshot at \(Date())")
                Task {
                    await self?.captureScreenshotAndSendToBrowserState()
                }
            }

            // Add timer to run loop to ensure it fires
            if let timer = self.screenshotTimer {
                RunLoop.main.add(timer, forMode: .common)
                passageLogger.debug("[SCREENSHOT TIMER] ✅ Screenshot timer created and added to run loop")

                // Fire immediately to test
                passageLogger.debug("[SCREENSHOT TIMER] 🔥 Firing timer immediately for testing")
                Task {
                    await self.captureScreenshotAndSendToBrowserState()
                }
            } else {
                passageLogger.error("[SCREENSHOT TIMER] ❌ Failed to create screenshot timer")
            }
        }
    }

    /// Stop interval-based screenshot capture
    private func stopScreenshotCapture() {
        if screenshotTimer != nil {
            passageLogger.debug("[SCREENSHOT TIMER] 🛑 Stopping screenshot capture timer")
            passageLogger.debug("[SCREENSHOT TIMER] Call stack: \(Thread.callStackSymbols.prefix(5).joined(separator: "\n"))")
            screenshotTimer?.invalidate()
            screenshotTimer = nil
        } else {
            passageLogger.debug("[SCREENSHOT TIMER] No screenshot timer to stop")
        }
        screenshotInterval = nil
        passageLogger.debug("[SCREENSHOT TIMER] Screenshot capture timer stopped")
    }

    /// Manually capture screenshot and send to browser state endpoint
    func captureScreenshotManually() async {
        await captureScreenshotAndSendToBrowserState()
    }

    /// Capture screenshot and send to browser state endpoint
    /// Uses WKWebView.takeSnapshot for proper WebView content capture
    private func captureScreenshotAndSendToBrowserState() async {
        passageLogger.debug("[SCREENSHOT CAPTURE] ========== CAPTURING SCREENSHOT FOR BROWSER STATE ==========")

        guard let intentToken = intentToken else {
            passageLogger.error("[SCREENSHOT CAPTURE] ❌ No intent token available for screenshot capture")
            return
        }

        passageLogger.debug("[SCREENSHOT CAPTURE] Intent token available, proceeding with capture")

        // Always capture a fresh screenshot for periodic updates (don't use cached)
        var screenshotData: String?
        passageLogger.debug("[SCREENSHOT CAPTURE] Capturing fresh screenshot for periodic update...")

        if let captureImageFunction = captureImageFunction {
            // Always capture new screenshot for timer-based captures
            screenshotData = await captureImageFunction()
            if let screenshot = screenshotData {
            } else {
                passageLogger.error("[SCREENSHOT CAPTURE] ❌ WKWebView.takeSnapshot failed to capture screenshot")
            }
        } else {
            // Fallback to cached screenshot if capture function not available
            passageLogger.warn("[SCREENSHOT CAPTURE] ⚠️ No capture function available, trying cached screenshot...")
            if let currentScreenshot = screenshotAccessors?.getCurrentScreenshot() {
                screenshotData = currentScreenshot
                passageLogger.debug("[SCREENSHOT CAPTURE] ✅ Using cached screenshot as fallback (\(currentScreenshot.count) chars)")
            } else {
                passageLogger.error("[SCREENSHOT CAPTURE] ❌ No screenshot capture method available")
                passageLogger.error("[SCREENSHOT CAPTURE] screenshotAccessors: \(screenshotAccessors != nil)")
                passageLogger.error("[SCREENSHOT CAPTURE] captureImageFunction: \(captureImageFunction != nil)")
            }
        }

        // Get image optimization parameters
        let imageOptParams = getImageOptimizationParameters()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // First try to get current URL from automation webview
            DispatchQueue.main.async {
                passageLogger.debug("[SCREENSHOT CAPTURE] Posting getCurrentUrlForBrowserState notification")
                NotificationCenter.default.post(
                    name: .getCurrentUrlForBrowserState,
                    object: nil,
                    userInfo: [
                        "screenshot": screenshotData as Any,
                        "trigger": "screenshot_capture",
                        "interval": self.screenshotInterval as Any,
                        "imageOptimization": imageOptParams as Any,
                        "continuation": continuation as Any
                    ]
                )
            }
        }

    }

    // Helper method to add padding to base64 string
    private func addPadding(to base64: String) -> String {
        let remainder = base64.count % 4
        if remainder > 0 {
            return base64 + String(repeating: "=", count: 4 - remainder)
        }
        return base64
    }

    // MARK: - Success URL Matching

    /// Check if the given URL matches any success URL for the specified navigation type
    private func checkSuccessUrlMatch(_ url: String, navigationType: SuccessUrl.NavigationType) -> Bool {
        guard !currentSuccessUrls.isEmpty else { return false }

        for successUrl in currentSuccessUrls {
            guard successUrl.navigationType == navigationType.rawValue else { continue }

            if urlMatches(url, pattern: successUrl.urlPattern) {
                passageLogger.info("[SUCCESS URL] 🎯 Match found for \(navigationType.rawValue): \(passageLogger.truncateUrl(url, maxLength: 100)) matches \(passageLogger.truncateUrl(successUrl.urlPattern, maxLength: 100))")
                return true
            }
        }

        return false
    }

    /// Check if a URL matches a pattern (supports exact match and basic wildcard matching)
    private func urlMatches(_ url: String, pattern: String) -> Bool {
        // Exact match
        if url == pattern {
            return true
        }

        // Basic wildcard support - if pattern contains *, treat it as a prefix match
        if pattern.contains("*") {
            let prefixPattern = pattern.replacingOccurrences(of: "*", with: "")
            return url.hasPrefix(prefixPattern)
        }

        // Check if URL starts with the pattern (for domain-level matching)
        if url.hasPrefix(pattern) {
            return true
        }

        // Extract domain from both URLs for domain matching
        guard let urlComponents = URLComponents(string: url),
              let patternComponents = URLComponents(string: pattern),
              let urlHost = urlComponents.host,
              let patternHost = patternComponents.host else {
            return false
        }

        // Domain match
        return urlHost == patternHost
    }

    /// Trigger webview switch to UI when success URL is matched
    private func handleSuccessUrlMatch(_ url: String, navigationType: SuccessUrl.NavigationType) {
        passageLogger.debug("[SUCCESS URL] ✅ Switching to UI webview due to success URL match")
        passageLogger.debug("[SUCCESS URL] Matched URL: \(passageLogger.truncateUrl(url, maxLength: 100)) (\(navigationType.rawValue))")

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .showUIWebView, object: nil)
        }
        currentWebViewType = PassageConstants.WebViewTypes.ui
    }

    // MARK: - Public Success URL Methods

    /// Check for success URL match on navigation start (called from WebViewModalViewController)
    func checkNavigationStart(_ url: String) {
        if checkSuccessUrlMatch(url, navigationType: .navigationStart) {
            handleSuccessUrlMatch(url, navigationType: .navigationStart)
        }
    }

    /// Check for success URL match on navigation end (called from WebViewModalViewController)
    func checkNavigationEnd(_ url: String) {
        if checkSuccessUrlMatch(url, navigationType: .navigationEnd) {
            handleSuccessUrlMatch(url, navigationType: .navigationEnd)
        }
    }

    func setConfigurationCallback(_ callback: ((_ userAgent: String, _ integrationUrl: String?) -> Void)?) {
        self.onConfigurationUpdated = callback
    }

    /// Detect and store the actual WebView user agent
    /// This should be called when WebViews are created to capture the real WebKit user agent
    func detectWebViewUserAgent(from webView: WKWebView) {
        webView.evaluateJavaScript("navigator.userAgent") { [weak self] result, error in
            if let userAgent = result as? String, !userAgent.isEmpty {
                passageLogger.debug("[REMOTE CONTROL] Detected WebView user agent: \(userAgent)")
                let previousUserAgent = self?.detectedWebViewUserAgent
                self?.detectedWebViewUserAgent = userAgent

                // If this is the first time we detected a user agent and we haven't fetched config yet,
                // or if the user agent changed significantly, refetch configuration
                if previousUserAgent == nil || (previousUserAgent != userAgent && !userAgent.contains("CFNetwork")) {
                    passageLogger.debug("[REMOTE CONTROL] User agent detected/updated, will use for future requests")
                }
            } else if let error = error {
                passageLogger.error("[REMOTE CONTROL] Failed to detect WebView user agent: \(error)")
            } else {
                passageLogger.warn("[REMOTE CONTROL] WebView user agent detection returned empty result")
            }
        }
    }

    /// Try to detect WebView user agent before making configuration request
    /// This creates a temporary WebView if needed to get the user agent
    private func detectWebViewUserAgentIfNeeded(completion: @escaping () -> Void) {
        // If we already have a detected user agent, proceed immediately
        if detectedWebViewUserAgent != nil {
            passageLogger.debug("[REMOTE CONTROL] WebView user agent already detected, proceeding")
            completion()
            return
        }

        passageLogger.debug("[REMOTE CONTROL] Creating temporary WebView to detect user agent")

        DispatchQueue.main.async { [weak self] in
            // Create a temporary WebView to detect the user agent
            let config = WKWebViewConfiguration()
            let tempWebView = WKWebView(frame: .zero, configuration: config)

            // Add the webview to a temporary container to ensure it's properly initialized
            let tempContainer = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            tempContainer.addSubview(tempWebView)
            tempWebView.frame = tempContainer.bounds

            // Detect user agent with timeout
            var completed = false

            // Give the WebView a moment to initialize before running JavaScript
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                tempWebView.evaluateJavaScript("navigator.userAgent") { result, error in
                    guard !completed else { return }
                    completed = true

                    // Clean up temporary container
                    tempWebView.removeFromSuperview()

                    if let userAgent = result as? String, !userAgent.isEmpty {
                        passageLogger.debug("[REMOTE CONTROL] Detected WebView user agent from temp WebView: \(userAgent)")
                        self?.detectedWebViewUserAgent = userAgent
                    } else if let error = error {
                        passageLogger.error("[REMOTE CONTROL] Failed to detect WebView user agent from temp WebView: \(error)")
                    } else {
                        passageLogger.warn("[REMOTE CONTROL] Temp WebView user agent detection returned empty result")
                    }

                    completion()
                }
            }

            // Fallback timeout in case the JavaScript doesn't execute
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                guard !completed else { return }
                completed = true
                passageLogger.warn("[REMOTE CONTROL] WebView user agent detection timed out, proceeding without it")

                // Clean up temporary container if still needed
                tempWebView.removeFromSuperview()

                completion()
            }
        }
    }

    // MARK: - Global JavaScript Access

    /// Get the global JavaScript that should be injected into automation webview on every navigation
    /// Returns empty string if no global JavaScript is configured
    func getGlobalJavascript() -> String {
        passageLogger.debug("[REMOTE CONTROL] getGlobalJavascript called - returning \(globalJavascript.isEmpty ? "EMPTY" : "\(globalJavascript.count) chars")")
        if !globalJavascript.isEmpty {
            let preview = String(globalJavascript.prefix(100))
            passageLogger.debug("[REMOTE CONTROL] Global JS preview: \(preview)...")
        }
        return globalJavascript
    }

    func connect(
        intentToken: String,
        onSuccess: ((PassageSuccessData) -> Void)? = nil,
        onError: ((PassageErrorData) -> Void)? = nil,
        onDataComplete: ((PassageDataResult) -> Void)? = nil,
        onPromptComplete: ((PassagePromptResponse) -> Void)? = nil
    ) {
        self.intentToken = intentToken
        
        if let sessionId = extractSessionId(from: intentToken) {
            passageLogger.info("[REMOTE CONTROL] Connecting with Session ID: \(sessionId)")
            passageLogger.debug("[REMOTE CONTROL] Full Intent Token: \(intentToken)")
        } else {
            passageLogger.warn("[REMOTE CONTROL] Could not extract Session ID from intent token")
            passageLogger.debug("[REMOTE CONTROL] Full Intent Token: \(intentToken)")
        }

        self.onSuccess = onSuccess
        self.onError = onError
        self.onDataComplete = onDataComplete
        self.onPromptComplete = onPromptComplete

        // Reset success URLs for new session
        currentSuccessUrls = []
        passageLogger.info("[REMOTE CONTROL] Connect")
        passageLogger.debug("[REMOTE CONTROL] ========== STARTING CONNECTION ==========")
        passageLogger.debug("[REMOTE CONTROL] Intent token preview: \(passageLogger.truncateData(intentToken, maxLength: 50))")
        passageLogger.debug("[REMOTE CONTROL] Socket URL: \(config.socketUrl)")
        passageLogger.debug("[REMOTE CONTROL] Socket Namespace: \(config.socketNamespace)")

        // Debug JWT token parsing
        passageLogger.debug("[REMOTE CONTROL] ========== JWT TOKEN ANALYSIS ==========")
        passageLogger.debug("[REMOTE CONTROL] Record mode: \(getRecordFlag() ? "ENABLED (full recording mode)" : "DISABLED (no full recording)")")
        passageLogger.debug("[REMOTE CONTROL] Capture screenshot flag: \(getCaptureScreenshotFlag() ? "ENABLED (screenshots will be captured)" : "DISABLED (no screenshots)")")
        if let interval = getCaptureScreenshotInterval() {
            passageLogger.debug("[REMOTE CONTROL] Screenshot interval: \(interval) seconds")
        } else {
            passageLogger.debug("[REMOTE CONTROL] Screenshot interval: NOT SET")
        }
        passageLogger.debug("[REMOTE CONTROL] Image optimization: Will be loaded from configuration (not JWT)")
        passageLogger.debug("[REMOTE CONTROL] Page data collection: ENABLED (HTML, localStorage, sessionStorage, cookies)")

        // Fetch configuration first
        passageLogger.debug("[REMOTE CONTROL] Fetching configuration from server...")
        passageAnalytics.trackConfigurationRequest(url: "\(config.socketUrl)\(PassageConstants.Paths.automationConfig)")

        // Try to detect WebView user agent first, but don't block if it fails
        detectWebViewUserAgentIfNeeded { [weak self] in
            self?.fetchConfiguration { [weak self] in
                passageLogger.debug("[REMOTE CONTROL] Configuration fetch completed, proceeding to socket connection")
                self?.connectSocket()

                // Start screenshot capture if enabled
                self?.startScreenshotCapture()
            }
        }
    }

    private func fetchConfiguration(completion: @escaping () -> Void) {
        guard let intentToken = intentToken else {
            passageLogger.error("[REMOTE CONTROL] No intent token available for configuration fetch")
            completion()
            return
        }

        let urlString = "\(config.socketUrl)\(PassageConstants.Paths.automationConfig)"

        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.addValue(intentToken, forHTTPHeaderField: "x-intent-token")

        // Add the detected WebView user agent as a custom header if available
        // This allows the backend to distinguish between URLSession user agent and WebView user agent
        if let webViewUserAgent = detectedWebViewUserAgent {
            request.setValue(webViewUserAgent, forHTTPHeaderField: "x-webview-user-agent")
            passageLogger.debug("[REMOTE CONTROL] Sending detected WebView user agent in custom header")
        } else {
            passageLogger.warn("[REMOTE CONTROL] No WebView user agent detected, backend will use default")
        }

        passageLogger.debug("[REMOTE CONTROL] Request headers: \(request.allHTTPHeaderFields ?? [:])")

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                passageLogger.error("[REMOTE CONTROL] Configuration fetch error: \(error.localizedDescription)")
                passageLogger.error("[REMOTE CONTROL] Error details: \(error)")
                passageAnalytics.trackConfigurationError(error: error.localizedDescription, url: urlString)
            }

            if let httpResponse = response as? HTTPURLResponse {
                passageLogger.debug("[REMOTE CONTROL] Configuration response status: \(httpResponse.statusCode)")
                if httpResponse.statusCode != 200 {
                    passageLogger.warn("[REMOTE CONTROL] Non-200 status code received")
                    passageAnalytics.trackConfigurationError(error: "Status code: \(httpResponse.statusCode)", url: urlString)
                }
            }

            if let data = data {
                passageLogger.debug("[REMOTE CONTROL] Configuration data received: \(data.count) bytes")
                if let jsonString = String(data: data, encoding: .utf8) {
                    passageLogger.debug("[REMOTE CONTROL] Raw response: \(passageLogger.truncateData(jsonString, maxLength: 500))")
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        // ADD COMPREHENSIVE CONFIGURATION LOGGING
                        passageLogger.debug("[REMOTE CONTROL] ========== FULL CONFIGURATION RESPONSE ==========")
                        passageLogger.debug("[REMOTE CONTROL] Configuration keys: \(json.keys.sorted())")

                        // Log integration data specifically
                        if let integration = json["integration"] as? [String: Any] {
                            passageLogger.debug("[REMOTE CONTROL] ✅ Integration data found: \(integration)")
                            let integrationUrl = integration["url"] as? String
                            let integrationName = integration["name"] as? String
                            let integrationSlug = integration["slug"] as? String
                            passageLogger.debug("[REMOTE CONTROL] Integration details:")
                            passageLogger.debug("[REMOTE CONTROL]   - Name: \(integrationName ?? "nil")")
                            passageLogger.debug("[REMOTE CONTROL]   - Slug: \(integrationSlug ?? "nil")")
                            passageLogger.debug("[REMOTE CONTROL]   - URL: \(integrationUrl ?? "NIL - THIS IS THE PROBLEM!")")
                        } else {
                            passageLogger.error("[REMOTE CONTROL] ❌ NO INTEGRATION FIELD IN CONFIGURATION!")
                            passageLogger.error("[REMOTE CONTROL] This means the backend is not returning integration data")
                        }

                        // Log other important fields
                        passageLogger.debug("[REMOTE CONTROL] Cookie domains: \(json["cookieDomains"] as? [String] ?? [])")
                        passageLogger.debug("[REMOTE CONTROL] Global JS length: \((json["globalJavascript"] as? String ?? "").count) chars")
                        passageLogger.debug("[REMOTE CONTROL] Automation user agent: \(json["automationUserAgent"] as? String ?? "empty")")

                        self?.cookieDomains = json["cookieDomains"] as? [String] ?? []
                        let newGlobalJavascript = json["globalJavascript"] as? String ?? ""

                        // Log global JavaScript configuration changes
                        if let self = self {
                            let oldLength = self.globalJavascript.count
                            let newLength = newGlobalJavascript.count

                            self.globalJavascript = newGlobalJavascript

                            passageLogger.debug("[REMOTE CONTROL] 📝 Global JavaScript updated: \(oldLength) chars -> \(newLength) chars")

                            if !newGlobalJavascript.isEmpty {
                                let preview = String(newGlobalJavascript.prefix(150))
                                passageLogger.debug("[REMOTE CONTROL] Global JS preview: \(preview)...")

                                // Check if it contains common libraries
                                if newGlobalJavascript.contains("Sentry") {
                                    passageLogger.debug("[REMOTE CONTROL] 🔍 Detected Sentry in global JavaScript")
                                }
                                if newGlobalJavascript.contains("WeakMap") {
                                    passageLogger.warn("[REMOTE CONTROL] ⚠️ WeakMap detected in global JavaScript - potential compatibility issue")
                                }
                                if newGlobalJavascript.contains("NetworkInterceptor") {
                                    passageLogger.debug("[REMOTE CONTROL] 🌐 Detected NetworkInterceptor in global JavaScript")
                                }
                            } else {
                                passageLogger.debug("[REMOTE CONTROL] ℹ️ Global JavaScript is empty")
                            }
                        }

                        // Extract automationUserAgent - undefined/null becomes empty string
                        self?.automationUserAgent = json["automationUserAgent"] as? String ?? ""

                        // Extract integration URL with detailed logging
                        let extractedIntegrationUrl = (json["integration"] as? [String: Any])?["url"] as? String
                        self?.integrationUrl = extractedIntegrationUrl

                        passageLogger.debug("[REMOTE CONTROL] ========== INTEGRATION URL EXTRACTION ==========")
                        passageLogger.debug("[REMOTE CONTROL] Extracted integration URL: \(extractedIntegrationUrl ?? "NIL")")
                        passageLogger.debug("[REMOTE CONTROL] Stored in self.integrationUrl: \(self?.integrationUrl ?? "NIL")")

                        if extractedIntegrationUrl == nil {
                            passageLogger.error("[REMOTE CONTROL] ❌ CRITICAL: No integration URL found!")
                            passageLogger.error("[REMOTE CONTROL] This means automation webview will never load")
                            passageLogger.error("[REMOTE CONTROL] Backend must provide integration.url in configuration")
                        } else {
                            passageLogger.debug("[REMOTE CONTROL] ✅ Integration URL successfully extracted")
                        }

                        // Extract imageOptimization parameters from configuration
                        self?.configImageOptimization = json["imageOptimization"] as? [String: Any]

                        passageLogger.debug("[REMOTE CONTROL] Configuration loaded. Domains: \(self?.cookieDomains.count ?? 0), JS: \(self?.globalJavascript.count ?? 0) chars")
                        passageLogger.debug("[REMOTE CONTROL] Cookie domains: \(self?.cookieDomains ?? [])")
                        passageLogger.debug("[REMOTE CONTROL] Global JS length: \(self?.globalJavascript.count ?? 0)")
                        let userAgentInfo: String
                        if let self = self, !self.automationUserAgent.isEmpty {
                            let agent = self.automationUserAgent
                            userAgentInfo = "provided (\(agent.count) chars)"
                        } else {
                            userAgentInfo = "empty (will use webview default)"
                        }
                        passageLogger.debug("[REMOTE CONTROL] Automation user agent: \(userAgentInfo)")
                        passageLogger.debug("[REMOTE CONTROL] Integration URL: \(self?.integrationUrl ?? "none")")
                        passageLogger.debug("[REMOTE CONTROL] Cookie domains configured: \(self?.cookieDomains.count ?? 0) domains")
                        passageLogger.debug("[REMOTE CONTROL] Image optimization from config: \(self?.configImageOptimization != nil ? "✅ SET" : "❌ NOT SET")")
                        if let imageOpt = self?.configImageOptimization {
                            passageLogger.debug("[REMOTE CONTROL] Config image optimization: \(imageOpt)")
                        }

                        // Notify about configuration update (matches React Native implementation)
                        if let self = self, let callback = self.onConfigurationUpdated {
                            passageLogger.debug("[REMOTE CONTROL] ========== CALLING CONFIGURATION CALLBACK ==========")
                            passageLogger.debug("[REMOTE CONTROL] 📞 Calling onConfigurationUpdated callback")
                            passageLogger.debug("[REMOTE CONTROL] Callback exists: true")
                            passageLogger.debug("[REMOTE CONTROL] Will pass userAgent: '\(self.automationUserAgent)'")
                            passageLogger.debug("[REMOTE CONTROL] Will pass integrationUrl: '\(self.integrationUrl ?? "NIL")'")

                            callback(self.automationUserAgent, self.integrationUrl)

                            passageLogger.debug("[REMOTE CONTROL] ✅ Configuration callback completed")
                        } else {
                            passageLogger.error("[REMOTE CONTROL] ❌ Configuration callback NOT called!")
                            passageLogger.error("[REMOTE CONTROL] self: \(self != nil)")
                            passageLogger.error("[REMOTE CONTROL] callback: \(self?.onConfigurationUpdated != nil)")
                        }
                        if let self = self {
                            passageAnalytics.trackConfigurationSuccess(userAgent: self.automationUserAgent, integrationUrl: self.integrationUrl)
                        }
                    }
                } catch {
                    passageLogger.error("[REMOTE CONTROL] JSON parsing error: \(error)")
                    passageAnalytics.trackConfigurationError(error: "JSON parsing error", url: urlString)
                }
            } else {
                passageLogger.warn("[REMOTE CONTROL] No data received in configuration response")
                passageAnalytics.trackConfigurationError(error: "No data", url: urlString)
            }

            completion()
        }.resume()
    }

    private func connectSocket() {
        let socketURL = URL(string: config.socketUrl)!

        passageLogger.info("[REMOTE CONTROL] CONNECTION STARTING Socket URL: \(socketURL.absoluteString), namespace: \(config.socketNamespace), intent token: \(intentToken)")
        passageAnalytics.trackRemoteControlConnectStart(socketUrl: socketURL.absoluteString, namespace: config.socketNamespace)

        // Determine if we should use secure connection based on URL scheme
        let isSecure = socketURL.scheme?.lowercased() == "https"
        passageLogger.debug("[REMOTE CONTROL] Using secure connection: \(isSecure) (scheme: \(socketURL.scheme ?? "nil"))")

        let socketConfig: SocketIOClientConfiguration = [
            .log(config.debug),  // Use unified debug flag from PassageConfig
            .compress,
            .path("/socket.io/"),  // Standard Socket.IO path
            .connectParams([
                "intentToken": intentToken ?? "",
                "agentName": config.agentName
            ]),
            .forceWebsockets(true),
            .forceNew(true),
            .reconnects(true),
            .reconnectAttempts(5),
            .reconnectWait(2),
            .reconnectWaitMax(10),
            .randomizationFactor(0),
            .secure(isSecure),  // Use secure connection only for HTTPS URLs
            .selfSigned(false)
            // Remove version specification to let it auto-negotiate
        ]

        passageLogger.debug("[REMOTE CONTROL] Socket configuration: \(socketConfig)")

        manager = SocketManager(
            socketURL: socketURL,
            config: socketConfig
        )

        // Use 'ws' namespace as expected by the server
        socket = manager?.socket(forNamespace: "/ws")

        if socket == nil {
            passageLogger.error("[REMOTE CONTROL] ❌ CRITICAL: Failed to create socket instance")
            let error = PassageErrorData(error: "Failed to create socket instance", data: nil)
            onError?(error)
            return
        }

        passageLogger.debug("[REMOTE CONTROL] Setting up socket event handlers...")
        setupSocketHandlers()

        passageLogger.debug("[REMOTE CONTROL] Initiating socket connection...")
        passageLogger.debug("[REMOTE CONTROL] Token for connection: \(passageLogger.truncateData(intentToken ?? "nil", maxLength: 50))")

        // Log initial socket state
        if let status = socket?.status {
            passageLogger.debug("[REMOTE CONTROL] Initial socket status: \(status)")
        }

        socket?.connect()

        // Check socket status at multiple intervals
        let checkIntervals: [Double] = [0.5, 1.0, 2.0, 3.0, 5.0]
        for interval in checkIntervals {
            DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                if let status = self?.socket?.status {
                    passageLogger.info("[REMOTE CONTROL] Socket status after \(interval)s: \(status)")
                    if let manager = self?.manager {
                        passageLogger.debug("[REMOTE CONTROL] Manager status: \(manager.status)")
                    }
                }
            }
        }
    }

    private func setupSocketHandlers() {
        passageLogger.debug("[SOCKET HANDLERS] Setting up all socket event handlers")

        socket?.on(clientEvent: .connect) { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] ✅ CONNECTED to server")
            passageLogger.info("[SOCKET EVENT] Connection Data: \(data)")
            self?.isConnected = true

            // Log socket details after connection
            if let socket = self?.socket {
                passageLogger.info("[SOCKET INFO] Socket ID: \(socket.sid ?? "no-sid")")
                passageLogger.debug("[SOCKET INFO] Status: \(socket.status)")
                passageLogger.debug("[SOCKET INFO] Manager status: \(socket.manager?.status ?? .notConnected)")
                passageAnalytics.trackRemoteControlConnectSuccess(socketId: socket.sid)
            }
        }

        socket?.on(clientEvent: .error) { [weak self] data, ack in
            passageLogger.error("[SOCKET EVENT] ❌ SOCKET ERROR: \(data)")
            passageAnalytics.trackRemoteControlConnectError(error: String(describing: data), attempt: 1)

            // Try to parse error details
            if let errorArray = data.first as? [Any], !errorArray.isEmpty {
                for (index, item) in errorArray.enumerated() {
                    passageLogger.error("[SOCKET EVENT] Error item \(index): \(item)")
                }
            }

            // Send error callback
            let errorMessage = "Socket error: \(data)"
            let error = PassageErrorData(error: errorMessage, data: data)
            self?.onError?(error)
        }

        socket?.on(clientEvent: .disconnect) { [weak self] data, ack in
            passageLogger.warn("[SOCKET EVENT] 🔌 DISCONNECTED from server")
            passageLogger.warn("[SOCKET EVENT] Disconnect Reason/Data: \(data)")
            self?.isConnected = false
            passageAnalytics.trackRemoteControlDisconnect(reason: "\(data)")

            // Log final socket state
            if let socket = self?.socket {
                passageLogger.debug("[SOCKET INFO] Final status: \(socket.status)")
            }
        }

        socket?.on(clientEvent: .reconnect) { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] 🔄 RECONNECTED successfully")
            passageLogger.debug("[SOCKET EVENT] Reconnected after \(data) attempts")
            self?.isConnected = true
        }

        socket?.on(clientEvent: .reconnectAttempt) { data, ack in
            passageLogger.debug("[SOCKET EVENT] 🔄 RECONNECT ATTEMPT #\(data)")
        }

        socket?.on(clientEvent: .statusChange) { data, ack in
            passageLogger.info("[SOCKET EVENT] 📊 STATUS CHANGED: \(data)")
        }

        socket?.on(clientEvent: .ping) { data, ack in
            passageLogger.debug("[SOCKET EVENT] 🏓 PING received")
        }

        socket?.on(clientEvent: .pong) { data, ack in
            passageLogger.debug("[SOCKET EVENT] 🏓 PONG received")
        }

        // Add websocket specific error handlers
        socket?.on(clientEvent: .websocketUpgrade) { data, ack in
            passageLogger.debug("[SOCKET EVENT] 🔄 WebSocket upgrade: \(data)")
        }

        socket?.onAny { event in
            passageLogger.debug("[SOCKET EVENT] Any event received: \(event.event) with items: \(event.items ?? [])")
        }

        // Custom events
        socket?.on("command") { [weak self] data, ack in
            guard let commandData = data.first as? [String: Any] else {
                passageLogger.error("[SOCKET EVENT] ❌ Invalid command data format")
                return
            }

            // Log command type immediately to track what we're receiving
            let commandType = commandData["type"] as? String ?? "unknown"
            let commandId = commandData["id"] as? String ?? "no-id"

            passageLogger.info("[SOCKET EVENT] Command received - Type: \(commandType), ID: \(commandId)")

            if commandType == "navigate" {
                if let args = commandData["args"] as? [String: Any],
                   let url = args["url"] as? String {
                    passageLogger.debug("[SOCKET EVENT] Navigate URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
                } else {
                    passageLogger.error("[SOCKET EVENT] ❌ Navigate command missing URL in args")
                }
            } else if commandType == "wait" {
                passageLogger.debug("[SOCKET EVENT] ⏳ WAIT COMMAND DETECTED")
            }

            passageLogger.debug("[SOCKET EVENT] Processing command...")
            self?.handleCommand(commandData)
        }

        socket?.on("welcome") { data, ack in
            passageLogger.info("[SOCKET EVENT] 👋 WELCOME message received, data: \(data)")
            passageLogger.debug("[SOCKET EVENT] Welcome data: \(data)")
        }

        socket?.on("error") { data, ack in
            passageLogger.error("[SOCKET EVENT] Server error event received: \(data)")
        }

        // Handle DATA_COMPLETE events (like React Native SDK)
        socket?.on("DATA_COMPLETE") { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] 📊 DATA_COMPLETE event received")
            passageLogger.debug("[SOCKET EVENT] Data complete data: \(data)")

            if let eventData = data.first as? [String: Any] {
                // Check if data state allows onDataComplete to be called
                let status = eventData["status"] as? String
                passageLogger.debug("[SOCKET EVENT] Data complete status: \(status ?? "nil")")

                // Only call onDataComplete when data is available or partially available
                if status == "data_available" || status == "data_partially_available" {
                    passageLogger.debug("[SOCKET EVENT] Status allows onDataComplete - calling callback")
                    let dataResult = PassageDataResult(
                        data: eventData["data"],
                        prompts: eventData["prompts"] as? [[String: Any]]
                    )
                    self?.onDataComplete?(dataResult)
                } else {
                    passageLogger.debug("[SOCKET EVENT] Status '\(status ?? "nil")' does not allow onDataComplete - skipping callback")
                }
            }
        }

        // Handle PROMPT_COMPLETE events (like React Native SDK)
        socket?.on("PROMPT_COMPLETE") { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] 🎯 PROMPT_COMPLETE event received")
            passageLogger.debug("[SOCKET EVENT] Prompt complete data: \(data)")

            if let eventData = data.first as? [String: Any],
               let key = eventData["key"] as? String,
               let value = eventData["value"] as? String {
                let promptResponse = PassagePromptResponse(
                    key: key,
                    value: value,
                    response: eventData["response"]
                )
                self?.onPromptComplete?(promptResponse)
            }
        }

        // Handle CONNECTION_SUCCESS events from socket
        socket?.on("CONNECTION_SUCCESS") { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] 🎉 CONNECTION_SUCCESS event received")
            passageLogger.debug("[SOCKET EVENT] Connection success data: \(data)")

            if let eventData = data.first as? [String: Any] {
                let connections = eventData["connections"] as? [[String: Any]] ?? []
                let connectionId = eventData["connectionId"] as? String

                let successData = PassageSuccessData(
                    history: connections,
                    connectionId: connectionId ?? "",
                    data: eventData  // Pass the entire event data
                )
                self?.onSuccess?(successData)
            }
        }

        // Handle CONNECTION_ERROR events from socket
        socket?.on("CONNECTION_ERROR") { [weak self] data, ack in
            passageLogger.error("[SOCKET EVENT] ❌ CONNECTION_ERROR event received: \(data)")

            if let eventData = data.first as? [String: Any] {
                let error = eventData["error"] as? String ?? "Unknown error"
                let errorData = PassageErrorData(error: error, data: eventData)
                self?.onError?(errorData)
            }
        }

        // Handle connection events for webview switching
        socket?.on("connection") { [weak self] data, ack in
            passageLogger.info("[SOCKET EVENT] 🔗 CONNECTION event received")
            passageLogger.debug("[SOCKET EVENT] Connection data: \(data)")

            guard let connectionData = data.first as? [String: Any] else {
                passageLogger.error("[SOCKET EVENT] Invalid connection data format")
                return
            }

            // Check for userActionRequired flag
            if let userActionRequired = connectionData["userActionRequired"] as? Bool {
                passageLogger.debug("[SOCKET EVENT] Connection userActionRequired: \(userActionRequired)")
                self?.handleUserActionRequiredChange(userActionRequired)
            }

            // Log other connection info
            if let status = connectionData["status"] as? String {
                passageLogger.debug("[SOCKET EVENT] Connection status: \(status)")
            }
            if let statusMessage = connectionData["statusMessage"] as? String {
                passageLogger.debug("[SOCKET EVENT] Status message: \(statusMessage)")
            }
            if let progress = connectionData["progress"] as? Int {
                passageLogger.debug("[SOCKET EVENT] Progress: \(progress)%")
            }

            // Store data when status is "connected" and progress is 100, and data is present
            passageLogger.debug("[SOCKET EVENT] Checking data storage conditions:")
            passageLogger.debug("[SOCKET EVENT]   - Status: \(connectionData["status"] as? String ?? "nil")")
            passageLogger.debug("[SOCKET EVENT]   - Progress: \(connectionData["progress"] as? Int ?? -1)")
            passageLogger.debug("[SOCKET EVENT]   - Data type: \(type(of: connectionData["data"]))")
            passageLogger.debug("[SOCKET EVENT]   - Data count: \((connectionData["data"] as? [[String: Any]])?.count ?? 0)")

            if let status = connectionData["status"] as? String,
               let progress = connectionData["progress"] as? Int,
               (status == "data_available" || status == "data_partially_available") && progress == 100,
               let actualData = connectionData["data"] as? [[String: Any]],
               !actualData.isEmpty {

                passageLogger.debug("[SOCKET EVENT] ✅ Data collection complete - storing data for success callback")
                passageLogger.debug("[SOCKET EVENT] Found data array with \(actualData.count) items")

                // Store the data and connection ID for when the success callback is triggered
                self?.connectionData = actualData
                self?.connectionId = connectionData["id"] as? String

                passageLogger.debug("[SOCKET EVENT] Data stored successfully:")
                passageLogger.debug("[SOCKET EVENT]   - Stored \(actualData.count) data items")
                passageLogger.debug("[SOCKET EVENT]   - Connection ID: \(connectionData["id"] as? String ?? "nil")")

                // Trigger onDataComplete callback when data is available
                passageLogger.info("[SOCKET EVENT] Triggering onDataComplete callback with available data")
                let dataResult = PassageDataResult(
                    data: actualData, // Pass all data items
                    prompts: connectionData["promptResults"] as? [[String: Any]]
                )
                self?.onDataComplete?(dataResult)
            } else {
                // Data storage conditions not met - data will not be available for success callback
                // This is normal for pending/connecting states
            }
        }

        // Log all handlers that were set up
        passageLogger.debug("[SOCKET HANDLERS] All event handlers configured successfully")
    }

    private func handleUserActionRequiredChange(_ userActionRequired: Bool) {
        passageLogger.info("[WEBVIEW SWITCH] New userActionRequired: \(userActionRequired)")

        // 🔑 RECORD MODE: Check if UI webview is locked by completeRecording
        let isRecordMode = getRecordFlag()
        if isRecordMode {
            // Check if UI webview is locked by completeRecording
            let isUILocked = viewController?.isUIWebViewLockedByRecording ?? false
            if isUILocked {
                passageLogger.debug("[WEBVIEW SWITCH] Record mode: UI webview is locked by completeRecording - skipping automatic switch")
                return
            }

            passageLogger.debug("[WEBVIEW SWITCH] Record mode enabled - showing automation webview")
            if currentWebViewType != PassageConstants.WebViewTypes.automation {
                passageLogger.debug("[WEBVIEW SWITCH] Switching to AUTOMATION webview (record mode)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .showAutomationWebView, object: nil)
                }
                currentWebViewType = PassageConstants.WebViewTypes.automation
            } else {
                passageLogger.debug("[WEBVIEW SWITCH] Already showing automation webview")
            }
            return
        }

        if userActionRequired {
            // User needs to interact - show automation webview
            if currentWebViewType != PassageConstants.WebViewTypes.automation {
                passageLogger.info("[WEBVIEW SWITCH] Switching to AUTOMATION webview (user interaction needed)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .showAutomationWebView, object: nil)
                }
                currentWebViewType = PassageConstants.WebViewTypes.automation
            } else {
                passageLogger.debug("[WEBVIEW SWITCH] Already showing automation webview")
            }
        } else {
            // No user interaction needed - show UI webview, automation runs in background
            if currentWebViewType != PassageConstants.WebViewTypes.ui {
                passageLogger.debug("[WEBVIEW SWITCH] Switching to UI webview (background automation)")
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .showUIWebView, object: nil)
                }
                currentWebViewType = PassageConstants.WebViewTypes.ui
            } else {
                passageLogger.debug("[WEBVIEW SWITCH] Keeping UI webview visible (automation runs in background)")
            }
        }
    }

    private func handleCommand(_ commandData: [String: Any]) {
        passageLogger.debug("[COMMAND HANDLER] ========== PROCESSING COMMAND ==========")
        passageLogger.debug("[COMMAND HANDLER] Raw command data: \(commandData)")

        guard let id = commandData["id"] as? String else {
            passageLogger.error("[COMMAND HANDLER] ❌ Missing command ID")
            return
        }

        guard let typeStr = commandData["type"] as? String else {
            passageLogger.error("[COMMAND HANDLER] ❌ Missing command type")
            return
        }

        guard let type = RemoteCommand.CommandType(rawValue: typeStr) else {
            passageLogger.debug("[COMMAND HANDLER] Unsupported command type: \(typeStr)")
            sendError(
                commandId: id,
                error: "Unsupported command type: \(typeStr)",
                data: ["errorType": "unsupported_command", "commandType": typeStr]
            )
            return
        }

        passageLogger.info("[COMMAND HANDLER] Executing command: \(type.rawValue) (ID: \(id))")

        let command = RemoteCommand(
            id: id,
            type: type,
            args: commandData["args"] as? [String: Any],
            injectScript: commandData["injectScript"] as? String,
            cookieDomains: commandData["cookieDomains"] as? [String],
            userActionRequired: commandData["userActionRequired"] as? Bool
        )

        passageLogger.debug("[COMMAND HANDLER] Command details:")
        passageLogger.debug("[COMMAND HANDLER]   - Args: \(command.args ?? [:])")
        passageLogger.debug("[COMMAND HANDLER]   - InjectScript: \(command.injectScript != nil ? "Yes (\(command.injectScript!.count) chars)" : "No")")
        passageLogger.debug("[COMMAND HANDLER]   - Cookie domains: \(command.cookieDomains ?? [])")
        passageLogger.debug("[COMMAND HANDLER]   - User action required: \(command.userActionRequired ?? false)")

        // Note: Webview switching is now handled by the connection event, not individual commands

        // Store user action commands for potential re-execution
        if command.userActionRequired == true {
            lastUserActionCommand = command
            passageLogger.debug("[REMOTE CONTROL] Stored user action command for re-execution: \(command.id)")
        }

        // 🔑 RECORD MODE: Store inject script for ALL commands that have one (for record mode reinjection)
        if let injectScript = command.injectScript {
            lastInjectScript = injectScript
            lastInjectScriptCommandId = command.id
            passageLogger.debug("[REMOTE CONTROL] Stored inject script for potential re-execution - type: \(command.type.rawValue), id: \(command.id), isRecordMode: \(getRecordFlag())")
        }

        // 🔑 RECORD MODE: Store injectScript commands specifically for record mode reinjection
        if command.type == .injectScript {
            lastInjectScriptCommand = command
            passageLogger.debug("[REMOTE CONTROL] Stored injectScript command for record mode: \(command.id)")
        }

        // Store wait commands for potential reinjection after navigation (backward compatibility)
        if command.type == .wait {
            lastWaitCommand = command
            passageLogger.debug("[REMOTE CONTROL] Stored wait command for potential reinjection: \(command.id)")
        }

        // Store current command (matches React Native implementation)
        currentCommand = command

        // Execute command
        passageLogger.debug("[COMMAND HANDLER] ========== EXECUTING COMMAND ==========")
        passageLogger.debug("[COMMAND HANDLER] Command type: \(command.type.rawValue)")
        passageLogger.debug("[COMMAND HANDLER] Command ID: \(command.id)")

        switch command.type {
        case .navigate:
            passageLogger.debug("[COMMAND HANDLER] 🧭 Executing NAVIGATE command")
            handleNavigate(command)
        case .click, .input, .wait, .injectScript:
            passageLogger.debug("[COMMAND HANDLER] 📝 Executing SCRIPT command (\(command.type.rawValue))")
            handleScriptExecution(command)
        case .done:
            passageLogger.debug("[COMMAND HANDLER] ✅ Executing DONE command")
            handleDone(command)
        }
    }

    private func handleNavigate(_ command: RemoteCommand) {

        guard let url = command.args?["url"] as? String else {
            passageLogger.error("[COMMAND HANDLER] ❌ No URL provided in navigate command!")
            sendError(commandId: command.id, error: "No URL provided")
            return
        }

        passageLogger.info("[COMMAND HANDLER] command: \(command.id) Navigate requested to: \(url)")

        // Parse and store successUrls (override any existing ones)
        if let successUrlsData = command.args?["successUrls"] as? [[String: Any]] {
            currentSuccessUrls = successUrlsData.compactMap { urlData in
                guard let urlPattern = urlData["urlPattern"] as? String,
                      let navigationType = urlData["navigationType"] as? String else {
                    return nil
                }
                return SuccessUrl(urlPattern: urlPattern, navigationType: navigationType)
            }

            passageLogger.debug("[COMMAND HANDLER] Stored \(currentSuccessUrls.count) success URLs:")
            for successUrl in currentSuccessUrls {
                passageLogger.debug("[COMMAND HANDLER]   - \(successUrl.navigationType): \(passageLogger.truncateUrl(successUrl.urlPattern, maxLength: 100))")
            }
        } else {
            // Clear success URLs if not provided in this command
            currentSuccessUrls = []
            passageLogger.debug("[COMMAND HANDLER] No success URLs provided, cleared existing ones")
        }

        passageLogger.debug("[COMMAND HANDLER] 🚀 SENDING NAVIGATE NOTIFICATION")
        passageLogger.debug("[COMMAND HANDLER] This should trigger automation webview navigation")
        passageAnalytics.trackCommandReceived(commandId: command.id, commandType: command.type.rawValue, userActionRequired: command.userActionRequired ?? false)

        DispatchQueue.main.async {
            passageLogger.debug("[COMMAND HANDLER] 📡 Posting navigateInAutomation notification")
            NotificationCenter.default.post(
                name: .navigateInAutomation,
                object: nil,
                userInfo: ["url": url, "commandId": command.id]
            )
            passageLogger.debug("[COMMAND HANDLER] ✅ Navigate notification posted successfully")
        }
    }

    private func handleScriptExecution(_ command: RemoteCommand) {
        guard let script = command.injectScript else {
            sendError(commandId: command.id, error: "No script provided for execution")
            return
        }

        passageLogger.info("[COMMAND HANDLER] Executing script: \(command.type.rawValue) (ID: \(command.id))")
        passageLogger.debug("[COMMAND HANDLER] Script length: \(script.count) characters")
        passageAnalytics.trackCommandReceived(commandId: command.id, commandType: command.type.rawValue, userActionRequired: command.userActionRequired ?? false)

        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .injectScript,
                object: nil,
                userInfo: ["script": script, "commandId": command.id, "commandType": command.type.rawValue]
            )
        }
    }

    private func handleDone(_ command: RemoteCommand) {
        let success = command.args?["success"] as? Bool ?? true
        let data = command.args?["data"]

        passageLogger.info("[COMMAND HANDLER] Done command received - Success: \(success), command ID: \(command.id)")

        // Always switch to UI webview for final result display
        if currentWebViewType != PassageConstants.WebViewTypes.ui {
            passageLogger.debug("[COMMAND HANDLER] Switching to UI webview for final result")
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .showUIWebView, object: nil)
            }
            currentWebViewType = PassageConstants.WebViewTypes.ui
        }

        if success {
            // Use async page data collection for done command like React Native
            getPageData { [weak self] pageData in
                let result = CommandResult(
                    id: command.id,
                    status: "success",
                    data: data != nil ? AnyCodable(data!) : nil,
                    pageData: pageData,
                    error: nil
                )
                self?.sendResult(result)
            }

            // Parse data into PassageSuccessData format
            let history = parseHistoryFromDoneCommand(from: data)
            let connectionId = (data as? [String: Any])?["connectionId"] as? String ?? ""

            passageLogger.debug("[COMMAND HANDLER] Extracted connectionId: \(connectionId)")
            passageLogger.debug("[COMMAND HANDLER] Parsed \(history.count) history items")

            let successData = PassageSuccessData(
                history: history,
                connectionId: connectionId,
                data: data  // Pass all done command data
            )

            passageLogger.debug("[COMMAND HANDLER] About to call onSuccess callback")
            onSuccess?(successData)
            passageLogger.debug("[COMMAND HANDLER] onSuccess callback completed")

            // Navigate to success URL in UI webview (only if redirectOnDoneCommand is true)
            if redirectOnDoneCommand {
                passageLogger.debug("[COMMAND HANDLER] Redirecting to success URL (redirectOnDoneCommand: true)")
                let successUrl = buildConnectUrl(success: true)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .navigate,
                        object: nil,
                        userInfo: ["url": successUrl]
                    )
                }
            } else {
                passageLogger.debug("[COMMAND HANDLER] Skipping redirect to success URL (redirectOnDoneCommand: false)")
            }
        } else {
            let errorMessage = (data as? [String: Any])?["error"] as? String ?? "Done command indicates failure"
            sendError(commandId: command.id, error: errorMessage)

            let errorData = PassageErrorData(error: errorMessage, data: data)
            onError?(errorData)

            // Navigate to error URL in UI webview (only if redirectOnDoneCommand is true)
            if redirectOnDoneCommand {
                passageLogger.debug("[COMMAND HANDLER] Redirecting to error URL (redirectOnDoneCommand: true)")
                let errorUrl = buildConnectUrl(success: false, error: errorMessage)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .navigate,
                        object: nil,
                        userInfo: ["url": errorUrl]
                    )
                }
            } else {
                passageLogger.debug("[COMMAND HANDLER] Skipping redirect to error URL (redirectOnDoneCommand: false)")
            }
        }
    }

    private func parseHistory(from data: Any?) -> [Any] {
        guard let historyData = data as? [String: Any],
              let historyArray = historyData["history"] as? [[String: Any]] else {
            return []
        }

        return historyArray
    }

    private func parseHistoryFromDoneCommand(from data: Any?) -> [Any] {
        guard let commandData = data as? [String: Any] else {
            passageLogger.warn("[COMMAND HANDLER] Failed to parse command data as dictionary")
            return []
        }

        // Check if history is directly an array (Format 1: data.history = [...])
        if let historyArray = commandData["history"] as? [[String: Any]] {
            passageLogger.debug("[COMMAND HANDLER] Format 1: Parsed \(historyArray.count) history items from direct array")
            return historyArray
        }

        // Check if history is a nested structure (Format 2: data.history.history = [...])
        if let historyWrapper = commandData["history"] as? [String: Any],
           let historyArray = historyWrapper["history"] as? [[String: Any]] {
            passageLogger.debug("[COMMAND HANDLER] Format 2: Parsed \(historyArray.count) history items from nested structure")
            return historyArray
        }

        passageLogger.warn("[COMMAND HANDLER] Failed to parse history from done command - neither format matched")
        passageLogger.debug("[COMMAND HANDLER] Command data keys: \(commandData.keys.sorted())")
        if let history = commandData["history"] {
            passageLogger.debug("[COMMAND HANDLER] History type: \(type(of: history))")
        }
        return []
    }

    private func buildConnectUrl(success: Bool, error: String? = nil) -> String {
        var components = URLComponents(string: "\(config.uiUrl)\(PassageConstants.Paths.connect)")!
        var queryItems = [
            URLQueryItem(name: "intentToken", value: intentToken ?? ""),
            URLQueryItem(name: "success", value: success.description),
            URLQueryItem(name: "appAgentName", value: config.agentName)
        ]

        if let error = error {
            queryItems.append(URLQueryItem(name: "error", value: error))
        }

        components.queryItems = queryItems
        return components.url!.absoluteString
    }

    private func sendSuccess(commandId: String, data: Any?) {
        passageLogger.info("[REMOTE CONTROL] sendSuccess called for command: \(commandId)")

        // Collect page data like React Native SDK
        getPageData { [weak self] pageData in
            let result = CommandResult(
                id: commandId,
                status: "success",
                data: data != nil ? AnyCodable(data!) : nil,
                pageData: pageData,
                error: nil
            )

            self?.sendResult(result)
            passageAnalytics.trackCommandSuccess(commandId: commandId, commandType: self?.currentCommand?.type.rawValue ?? "", duration: nil)
        }
    }

    private func sendError(commandId: String, error: String, data: Any? = nil) {
        // Error results don't typically include page data in React Native either
        passageLogger.info("[REMOTE CONTROL] sendError called for command: \(commandId)")

        let result = CommandResult(
            id: commandId,
            status: "error",
            data: data != nil ? AnyCodable(data!) : nil,
            pageData: nil,
            error: error
        )
        sendResult(result)
        passageAnalytics.trackCommandError(commandId: commandId, commandType: currentCommand?.type.rawValue ?? "", error: error)
    }

    func sendCommandResult(commandId: String, data: Any?, pageData: [String: Any]?) {
        // Convert pageData to proper structure
        var structuredPageData: PageData?
        if let pageData = pageData {
            structuredPageData = PageData(
                cookies: parseCookies(pageData["cookies"] as? [[String: Any]]),
                localStorage: parseStorage(pageData["localStorage"] as? [[String: Any]]),
                sessionStorage: parseStorage(pageData["sessionStorage"] as? [[String: Any]]),
                html: pageData["html"] as? String,
                url: pageData["url"] as? String,
                screenshot: nil
            )
        }

        let result = CommandResult(
            id: commandId,
            status: "success",
            data: data != nil ? AnyCodable(data!) : nil,
            pageData: structuredPageData,
            error: nil
        )
        passageLogger.debug("[REMOTE CONTROL] Sending command result for command: \(commandId))")
        sendResult(result)
    }

    private func parseCookies(_ cookiesData: [[String: Any]]?) -> [CookieData]? {
        guard let cookiesData = cookiesData else { return nil }

        return cookiesData.map { cookie in
            CookieData(
                name: cookie["name"] as? String ?? "",
                value: cookie["value"] as? String ?? "",
                domain: cookie["domain"] as? String ?? "",
                path: cookie["path"] as? String,
                expires: cookie["expires"] as? Double,
                secure: cookie["secure"] as? Bool,
                httpOnly: cookie["httpOnly"] as? Bool,
                sameSite: cookie["sameSite"] as? String ?? "None"
            )
        }
    }

    private func parseStorage(_ storageData: [[String: Any]]?) -> [StorageItem]? {
        guard let storageData = storageData else { return nil }

        return storageData.map { item in
            StorageItem(
                name: item["name"] as? String ?? "",
                value: item["value"] as? String ?? ""
            )
        }
    }

    private func getPageData(completion: @escaping (PageData?) -> Void) {
        passageLogger.debug("[REMOTE CONTROL] Collecting page data from automation webview...")

        // JavaScript to collect page data (matching React Native implementation)
        let pageDataScript = """
        (function() {
            try {
                const localStorageItems = [];
                for (let i = 0; i < localStorage.length; i++) {
                    const key = localStorage.key(i);
                    localStorageItems.push({ name: key, value: localStorage.getItem(key) });
                }

                const sessionStorageItems = [];
                for (let i = 0; i < sessionStorage.length; i++) {
                    const key = sessionStorage.key(i);
                    sessionStorageItems.push({ name: key, value: sessionStorage.getItem(key) });
                }

                const result = {
                    url: window.location.href,
                    html: document.documentElement.outerHTML,
                    localStorage: localStorageItems,
                    sessionStorage: sessionStorageItems
                };

                // Send via webkit message handler
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                    window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'pageData',
                        data: result,
                        webViewType: 'automation',
                        timestamp: Date.now()
                    });
                } else {
                    console.error('[PageData] Message handlers not available');
                }
            } catch (error) {
                console.error('[PageData] Error collecting page data:', error);
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                    window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'pageData',
                        error: error.toString(),
                        webViewType: 'automation',
                        timestamp: Date.now()
                    });
                }
            }
        })();
        """

        // Set up completion timeout (5 seconds like React Native)
        var hasCompleted = false
        let timeoutTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { _ in
            if !hasCompleted {
                hasCompleted = true
                passageLogger.warn("[REMOTE CONTROL] Page data collection timeout - returning minimal data")
                // Return minimal page data on timeout
                completion(PageData(
                    cookies: [],
                    localStorage: [],
                    sessionStorage: [],
                    html: nil,
                    url: nil,
                    screenshot: nil
                ))
            }
        }

        // Store completion handler for message processing
        pageDataCompletionHandler = { [weak self] pageData in
            if !hasCompleted {
                hasCompleted = true
                timeoutTimer.invalidate()

                // Extract URL from page data for cookie collection
                let pageUrl = pageData["url"] as? String

                // Collect cookies from WKWebsiteDataStore
                self?.collectCookies(pageUrl: pageUrl) { cookies in
                    // Convert localStorage and sessionStorage to proper format
                    let localStorage = self?.convertStorageItems(pageData["localStorage"] as? [[String: Any]]) ?? []
                    let sessionStorage = self?.convertStorageItems(pageData["sessionStorage"] as? [[String: Any]]) ?? []

                    // Collect screenshot based on record flag (whole UI) or captureScreenshot flag (webview only)
                    self?.collectScreenshot { screenshot in
                        let fullPageData = PageData(
                            cookies: cookies,
                            localStorage: localStorage,
                            sessionStorage: sessionStorage,
                            html: pageData["html"] as? String,
                            url: pageData["url"] as? String,
                            screenshot: screenshot
                        )

                        let screenshotInfo = screenshot != nil ? "\(screenshot!.count) chars" : "nil"
                        passageLogger.debug("[REMOTE CONTROL] Page data collected: html=\(passageLogger.truncateHtml(fullPageData.html)), localStorage=\(localStorage.count) items, sessionStorage=\(sessionStorage.count) items, cookies=\(cookies.count) items, screenshot=\(screenshotInfo), url=\(fullPageData.url ?? "nil")")

                        completion(fullPageData)
                    }
                }
            }
        }

        // Inject script into automation webview
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .collectPageData,
                object: nil,
                userInfo: ["script": pageDataScript]
            )
        }
    }

    private func collectCookies(pageUrl: String?, completion: @escaping ([CookieData]) -> Void) {
        // Determine domains to collect cookies from
        var domainsToCollect: [String] = []

        // First try configured cookieDomains
        if !cookieDomains.isEmpty {
            domainsToCollect = cookieDomains
            passageLogger.debug("[REMOTE CONTROL] Using configured cookie domains: \(cookieDomains)")
        }
        // Fallback to extracting domain from current page URL
        else if let urlString = pageUrl, let url = URL(string: urlString), let host = url.host {
            // Add both the full domain and .domain format (for subdomain cookies)
            domainsToCollect = [host]
            if !host.starts(with: ".") {
                domainsToCollect.append(".\(host)")
            }

            // Also add root domain (e.g., kroger.com if host is www.kroger.com)
            let components = host.components(separatedBy: ".")
            if components.count > 2 {
                // Extract root domain (last two components)
                let rootDomain = components.suffix(2).joined(separator: ".")
                if rootDomain != host {
                    domainsToCollect.append(rootDomain)
                    domainsToCollect.append(".\(rootDomain)")
                }
            }

            passageLogger.debug("[REMOTE CONTROL] Extracted cookie domains from current URL: \(domainsToCollect)")
        }

        guard !domainsToCollect.isEmpty else {
            passageLogger.warn("[REMOTE CONTROL] No cookie domains available (neither configured nor from URL), returning empty array")
            completion([])
            return
        }

        passageLogger.debug("[REMOTE CONTROL] Collecting cookies for domains: \(domainsToCollect)")

        let cookieStore = WKWebsiteDataStore.default().httpCookieStore
        var allCookies: [CookieData] = []
        let group = DispatchGroup()

        for domain in domainsToCollect {
            group.enter()

            // Get all cookies and filter by domain
            cookieStore.getAllCookies { cookies in
                defer { group.leave() }

                let domainCookies = cookies.filter { cookie in
                    self.cookieMatchesDomain(cookie: cookie, domain: domain)
                }

                let convertedCookies = domainCookies.map { cookie in
                    CookieData(
                        name: cookie.name,
                        value: cookie.value,
                        domain: cookie.domain,
                        path: cookie.path,
                        expires: cookie.expiresDate?.timeIntervalSince1970,
                        secure: cookie.isSecure,
                        httpOnly: cookie.isHTTPOnly,
                        sameSite: self.convertSameSitePolicy(cookie.sameSitePolicy)
                    )
                }

                allCookies.append(contentsOf: convertedCookies)
                passageLogger.debug("[REMOTE CONTROL] Found \(domainCookies.count) cookies for domain: \(domain)")
            }
        }

        group.notify(queue: .main) {
            passageLogger.debug("[REMOTE CONTROL] Cookie collection complete: \(allCookies.count) total cookies")
            completion(allCookies)
        }
    }

    private func cookieMatchesDomain(cookie: HTTPCookie, domain: String) -> Bool {
        // Check if cookie domain matches the configured domain
        let cookieDomain = cookie.domain.hasPrefix(".") ? cookie.domain : "."+cookie.domain
        let targetDomain = domain.hasPrefix(".") ? domain : "."+domain

        return cookieDomain == targetDomain || cookieDomain.hasSuffix(targetDomain)
    }

    private func convertSameSitePolicy(_ policy: HTTPCookieStringPolicy?) -> String {
        guard let policy = policy else { return "None" }

        switch policy {
        case .sameSiteStrict:
            return "Strict"
        case .sameSiteLax:
            return "Lax"
        default:
            return "None"
        }
    }

    // Store completion handler for page data collection
    private var pageDataCompletionHandler: (([String: Any]) -> Void)?

    func handlePageDataResult(_ data: [String: Any]) {
        passageLogger.debug("[REMOTE CONTROL] Received page data result from webview")
        pageDataCompletionHandler?(data)
    }

    private func convertStorageItems(_ items: [[String: Any]]?) -> [StorageItem] {
        guard let items = items else { return [] }

        return items.compactMap { item in
            guard let name = item["name"] as? String,
                  let value = item["value"] as? String else {
                return nil
            }
            return StorageItem(name: name, value: value)
        }
    }

    private func collectScreenshot(completion: @escaping (String?) -> Void) {
        // Check both record flag (whole UI) and captureScreenshot flag (webview only)
        let recordFlag = getRecordFlag()
        let captureScreenshotFlag = getCaptureScreenshotFlag()

        guard recordFlag || captureScreenshotFlag else {
            passageLogger.debug("[REMOTE CONTROL] Screenshot collection skipped - both record and captureScreenshot flags are false")
            completion(nil)
            return
        }

        if recordFlag {
            passageLogger.debug("[REMOTE CONTROL] Collecting screenshot for record mode - whole UI capture")
        } else {
            passageLogger.debug("[REMOTE CONTROL] Collecting screenshot for captureScreenshot mode - webview only")
        }

        // Try to get current screenshot from accessors first
        if let currentScreenshot = screenshotAccessors?.getCurrentScreenshot() {
            passageLogger.debug("[REMOTE CONTROL] Using current screenshot from accessors (WKWebView.takeSnapshot)")
            completion(currentScreenshot)
            return
        }

        // If no current screenshot available, try to capture a new one using WKWebView.takeSnapshot
        if let captureImageFunction = captureImageFunction {
            Task {
                let screenshot = await captureImageFunction()
                if let screenshot = screenshot {
                    passageLogger.debug("[REMOTE CONTROL] WKWebView.takeSnapshot captured new screenshot: \(screenshot.count) chars")
                } else {
                    passageLogger.debug("[REMOTE CONTROL] WKWebView.takeSnapshot failed to capture screenshot")
                }
                completion(screenshot)
            }
        } else {
            passageLogger.debug("[REMOTE CONTROL] No WKWebView.takeSnapshot capture function available")
            completion(nil)
        }
    }

    private func sendResult(_ result: CommandResult) {
        guard let intentToken = intentToken else {
            passageLogger.error("[REMOTE CONTROL] No intent token available for sending result")
            return
        }

        let urlString = "\(config.socketUrl)\(PassageConstants.Paths.automationCommandResult)"
        passageLogger.info("[REMOTE CONTROL] Sending command result - ID: \(result.id), Status: \(result.status)")
        passageLogger.debug("[REMOTE CONTROL] Sending result to: \(urlString)")

        // Log page data status (matching React Native's truncated logging approach)
        if let pageData = result.pageData {
            let recordFlag = getRecordFlag()
            let captureScreenshotFlag = getCaptureScreenshotFlag()
            let screenshotInfo: String
            if recordFlag {
                screenshotInfo = " (record mode - whole UI screenshot)"
            } else if captureScreenshotFlag {
                screenshotInfo = " (captureScreenshot mode - webview only)"
            } else {
                screenshotInfo = " (no screenshot capture)"
            }
            passageLogger.debug("[REMOTE CONTROL] ✅ Sending result WITH page data\(screenshotInfo): {")
            passageLogger.debug("[REMOTE CONTROL]   cookies: \(pageData.cookies?.count ?? 0) items")
            passageLogger.debug("[REMOTE CONTROL]   localStorage: \(pageData.localStorage?.count ?? 0) items")
            passageLogger.debug("[REMOTE CONTROL]   sessionStorage: \(pageData.sessionStorage?.count ?? 0) items")
            passageLogger.debug("[REMOTE CONTROL]   html: \(passageLogger.truncateHtml(pageData.html))")
            passageLogger.debug("[REMOTE CONTROL]   screenshot: \(pageData.screenshot != nil ? "\(pageData.screenshot!.count) chars (redacted)" : "nil")")
            passageLogger.debug("[REMOTE CONTROL]   url: \(pageData.url ?? "nil")")
            passageLogger.debug("[REMOTE CONTROL] } (matches React Native SDK functionality)")
        } else {
            passageLogger.warn("[REMOTE CONTROL] ⚠️ Sending result WITHOUT page data (pageData: nil)")
            passageLogger.debug("[REMOTE CONTROL] React Native SDK would include: HTML, localStorage, sessionStorage, cookies, URL, screenshot")
        }

        guard let url = URL(string: urlString) else {
            passageLogger.error("[REMOTE CONTROL] Invalid URL: \(urlString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(intentToken, forHTTPHeaderField: "x-intent-token")

        do {
            let jsonData = try JSONEncoder().encode(result)
            request.httpBody = jsonData

            passageLogger.debug("[REMOTE CONTROL] Sending HTTP POST request...")

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    passageLogger.error("[REMOTE CONTROL] Error sending result: \(error)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    passageLogger.info("[REMOTE CONTROL] Result sent successfully commandId: \(result.id) - Status: \(httpResponse.statusCode)")
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        passageLogger.debug("[REMOTE CONTROL] Response: \(responseString)")
                    }
                } else {
                    passageLogger.info("[REMOTE CONTROL] Result sent successfully commandId: \(result.id) - Status: \(httpResponse.statusCode)")
                }
            }.resume()

            // Also send to session bus
            sendResultToSessionBus(result)
        } catch {
            passageLogger.error("[REMOTE CONTROL] Error encoding result: \(error)")
        }
    }

    private func sendResultToSessionBus(_ result: CommandResult) {
        guard let intentToken = intentToken else {
            passageLogger.error("[REMOTE CONTROL] No intent token available for sending result to session bus")
            return
        }

        let sessionBaseUrl = config.sessionUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let path = "/command/response/record"
        let fullUrlString = sessionBaseUrl + path

        passageLogger.debug("[REMOTE CONTROL] Sending result to session bus: \(fullUrlString)")
        passageLogger.debug("[REMOTE CONTROL] Command ID: \(result.id), Status: \(result.status)")

        guard let url = URL(string: fullUrlString) else {
            passageLogger.error("[REMOTE CONTROL] Invalid session bus URL: \(fullUrlString)")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(intentToken, forHTTPHeaderField: "x-intent-token")
        request.timeoutInterval = 30.0

        do {
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = iso8601Formatter.string(from: Date())

            let jsonData = try JSONEncoder().encode(SessionCommandResponseBody(
              commandResponse: SessionCommandResponse(
                at: timestamp,
                data: result
              )
            ))
            request.httpBody = jsonData

            passageLogger.debug("[REMOTE CONTROL] Sending HTTP POST request to session bus...")

            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    passageLogger.error("[REMOTE CONTROL] Error sending result to session bus: \(error)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    passageLogger.debug("[REMOTE CONTROL] Result sent to session bus successfully - Status: \(httpResponse.statusCode)")
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        passageLogger.debug("[REMOTE CONTROL] Session bus response: \(responseString)")
                    }
                } else {
                    passageLogger.debug("[REMOTE CONTROL] Result sent to session bus successfully")
                }
            }.resume()
        } catch {
            passageLogger.error("[REMOTE CONTROL] Error encoding result for session bus: \(error)")
        }
    }

    func handleWebViewMessage(_ message: [String: Any]) {
        // Handle messages from webview (matches React Native implementation)
        passageLogger.debug("[REMOTE CONTROL] Handling WebView message: \(message["type"] as? String ?? "unknown")")

        if let messageType = message["type"] as? String {
            switch messageType {
            case "commandResult":
                // Handle command results from automation webview
                if let commandId = message["commandId"] as? String,
                   let status = message["status"] as? String {

                    passageLogger.info("[REMOTE CONTROL] Command result from webview: \(commandId), status: \(status)")

                    if status == "success" {
                        let result = message["data"]
                        sendSuccess(commandId: commandId, data: result)
                    } else {
                        let error = message["error"] as? String ?? "Command failed"
                        sendError(commandId: commandId, error: error)
                    }
                }

            case "waitForInteraction":
                // Handle user interaction events (click, scroll, blur/input)
                if let commandId = message["commandId"] as? String {
                    passageLogger.info("[REMOTE CONTROL] waitForInteraction event received for command: \(commandId)")

                    if let interactionType = message["interactionType"] as? String {
                        passageLogger.debug("[REMOTE CONTROL] Interaction type: \(interactionType)")

                        // Extract interaction value
                        let interactionValue = message["value"] as? [String: Any] ?? [:]

                        // Build interaction data structure
                        var interactionData: [String: Any] = [
                            "type": interactionType,
                            "timestamp": Date().timeIntervalSince1970 * 1000 // milliseconds
                        ]

                        // Add type-specific data
                        switch interactionType {
                        case "click":
                            if let elementInfo = interactionValue["elementInfo"] as? [String: Any] {
                                interactionData["elementInfo"] = elementInfo
                            }
                            if let clickPosition = interactionValue["clickPosition"] as? [String: Any] {
                                interactionData["clickPosition"] = clickPosition
                            }

                        case "scroll":
                            if let deltaY = interactionValue["deltaY"] {
                                interactionData["deltaY"] = deltaY
                            }

                        case "blur":
                            if let elementInfo = interactionValue["elementInfo"] as? [String: Any] {
                                interactionData["elementInfo"] = elementInfo
                            }
                            if let inputValue = interactionValue["inputValue"] {
                                interactionData["inputValue"] = inputValue
                            }
                            if let focusPosition = interactionValue["focusPosition"] as? [String: Any] {
                                interactionData["focusPosition"] = focusPosition
                            }

                        default:
                            passageLogger.warn("[REMOTE CONTROL] Unknown interaction type: \(interactionType)")
                        }

                        passageLogger.debug("[REMOTE CONTROL] Interaction data: \(interactionData)")

                        // Get page data with screenshot and HTML
                        Task {
                            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                                getPageData { pageData in
                                    // Send the interaction as a success result with pageData
                                    let result = CommandResult(
                                        id: commandId,
                                        status: "success",
                                        data: AnyCodable(interactionData),
                                        pageData: pageData,
                                        error: nil
                                    )

                                    self.sendResult(result)
                                    passageLogger.debug("[REMOTE CONTROL] Interaction data sent successfully")
                                    continuation.resume()
                                }
                            }
                        }
                    } else {
                        passageLogger.error("[REMOTE CONTROL] waitForInteraction message missing interactionType")
                    }
                } else {
                    passageLogger.error("[REMOTE CONTROL] waitForInteraction message missing commandId")
                }

            case "currentUrl":
                // Handle current URL responses
                passageLogger.debug("[REMOTE CONTROL] Current URL: \(message["url"] as? String ?? "unknown")")

            case "pageData":
                // Handle page data responses
                passageLogger.debug("[REMOTE CONTROL] Received page data")
                // TODO: Handle page data promise resolution

            case "SWITCH_WEBVIEW":
                // Handle manual webview switching from window.passage methods
                if let targetWebView = message["targetWebView"] as? String {
                    passageLogger.debug("[REMOTE CONTROL] Manual webview switch requested to \(targetWebView)")

                    if targetWebView == "ui" {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .showUIWebView, object: nil)
                        }
                    } else if targetWebView == "automation" {
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .showAutomationWebView, object: nil)
                        }
                    }
                }

            case "passage_message":
                // Handle window.passage.postMessage calls
                if let passageData = message["data"] {
                    passageLogger.debug("[REMOTE CONTROL] Received passage message")

                    var parsedData: [String: Any]?
                    if let dataString = passageData as? String,
                       let jsonData = dataString.data(using: .utf8) {
                        parsedData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
                    } else if let dataDict = passageData as? [String: Any] {
                        parsedData = dataDict
                    }

                    if let parsedData = parsedData,
                       let commandId = parsedData["commandId"] as? String,
                       let commandType = parsedData["type"] as? String {

                        passageLogger.info("[REMOTE CONTROL] Processing \(commandType) result for command: \(commandId)")

                        // Handle different command types
                        switch commandType {
                        case "injectScript", "wait":
                            let success = parsedData["error"] == nil
                            if success {
                                sendSuccess(commandId: commandId, data: parsedData["value"])
                            } else {
                                let error = parsedData["error"] as? String ?? "Script execution failed"
                                sendError(commandId: commandId, error: error)
                            }

                        case "waitForInteraction":
                            // Handle user interaction events (click, scroll, blur/input)
                            passageLogger.debug("[REMOTE CONTROL] waitForInteraction event received")

                            // Use the entire value object which contains all the interaction data
                            let interactionData = parsedData["value"] as? [String: Any] ?? [:]

                            // Log the interaction type if available
                            if let interactionType = interactionData["interactionType"] as? String {
                                passageLogger.debug("[REMOTE CONTROL] Interaction type: \(interactionType)")
                            }

                            passageLogger.debug("[REMOTE CONTROL] Full interaction data: \(interactionData)")

                            // Get page data with screenshot and HTML
                            Task {
                                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                                    getPageData { pageData in
                                        // Send the entire interaction data as received from the browser
                                        let result = CommandResult(
                                            id: commandId,
                                            status: "success",
                                            data: AnyCodable(interactionData),
                                            pageData: pageData,
                                            error: nil
                                        )

                                        self.sendResult(result)
                                        passageLogger.debug("[REMOTE CONTROL] Interaction data sent successfully")
                                        continuation.resume()
                                    }
                                }
                            }

                            if interactionData.isEmpty {
                                passageLogger.warn("[REMOTE CONTROL] waitForInteraction message has empty value")
                            }

                        default:
                            passageLogger.debug("[REMOTE CONTROL] Unhandled passage message type: \(commandType)")
                        }
                    }
                }

            default:
                passageLogger.debug("[REMOTE CONTROL] Unhandled message type: \(messageType)")
            }
        }
    }

    func getStoredConnectionData() -> (data: [[String: Any]]?, connectionId: String?) {
        passageLogger.debug("[REMOTE CONTROL] getStoredConnectionData called")
        passageLogger.debug("[REMOTE CONTROL]   - Returning data count: \(connectionData?.count ?? 0)")
        passageLogger.debug("[REMOTE CONTROL]   - Returning connection ID: \(connectionId ?? "nil")")
        return (connectionData, connectionId)
    }

    // MARK: - Recording Methods (matching React Native SDK)

    /// Complete recording session with optional data
    /// Matches React Native SDK completeRecording method
    func completeRecording(data: [String: Any]) async {
        passageLogger.debug("[REMOTE CONTROL] completeRecording called with data: \(data)")

        guard let currentCommand = currentCommand else {
            passageLogger.error("[REMOTE CONTROL] No current command available to complete")
            return
        }

        passageLogger.debug("[REMOTE CONTROL] Completing recording for command: \(currentCommand.id)")

        // Switch to UI webview before completing (only in record mode)
        let isRecordMode = getRecordFlag()
        if isRecordMode && currentWebViewType != PassageConstants.WebViewTypes.ui {
            passageLogger.debug("[REMOTE CONTROL] Record mode: Switching to UI webview for recording completion and locking it")
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .showUIWebView,
                    object: nil,
                    userInfo: ["lockUIWebView": true]
                )
            }
            currentWebViewType = PassageConstants.WebViewTypes.ui

            // Small delay to allow webview transition
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        } else if !isRecordMode {
            passageLogger.debug("[REMOTE CONTROL] Not in record mode - skipping UI webview switch")
        }

        // Collect page data with screenshot based on record flag (whole UI) or captureScreenshot flag (webview only)
        await withCheckedContinuation { continuation in
            getPageData { pageData in
                // Send done result (matches React Native SDK behavior)
                let result = CommandResult(
                    id: currentCommand.id,
                    status: "done",
                    data: AnyCodable(data),
                    pageData: pageData,
                    error: nil
                )

                Task {
                    self.sendResult(result)

                    // Call success callback if available
                    if let onSuccess = self.onSuccess,
                       let connectionData = self.connectionData,
                       let connectionId = self.connectionId {
                        let successData = PassageSuccessData(
                            history: connectionData,
                            connectionId: connectionId,
                            data: connectionData  // Pass the raw connection data
                        )
                        onSuccess(successData)
                    }

                    passageLogger.debug("[REMOTE CONTROL] Recording completed successfully")
                    continuation.resume()
                }
            }
        }
    }

    /// Capture recording data without completing the session
    /// Matches React Native SDK captureRecordingData method
    func captureRecordingData(data: [String: Any]) async {
        passageLogger.debug("[REMOTE CONTROL] captureRecordingData called with data: \(data)")

        guard let currentCommand = currentCommand else {
            passageLogger.error("[REMOTE CONTROL] No current command available to capture")
            return
        }

        passageLogger.debug("[REMOTE CONTROL] Capturing recording data for command: \(currentCommand.id)")

        // Collect page data with screenshot based on record flag (whole UI) or captureScreenshot flag (webview only)
        await withCheckedContinuation { continuation in
            getPageData { pageData in
                // Send success result (not done, so session continues)
                let result = CommandResult(
                    id: currentCommand.id,
                    status: "success",
                    data: AnyCodable(data),
                    pageData: pageData,
                    error: nil
                )

                Task {
                    self.sendResult(result)
                    passageLogger.debug("[REMOTE CONTROL] Recording data captured successfully")
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Modal Exit Event (matching React Native SDK)

    /// Emit modalExit event to server before disconnecting
    /// Matches React Native SDK emitModalExit method
    func emitModalExit() async {
        await withCheckedContinuation { continuation in
            if let socket = socket, socket.status == .connected {
                passageLogger.debug("[REMOTE CONTROL] Emitting modalExit event")

                let modalExitData: [String: Any] = [
                    "timestamp": ISO8601DateFormatter().string(from: Date()),
                    "intentToken": intentToken ?? ""
                ]

                // Use an atomic flag to ensure continuation is only resumed once
                let resumeState = NSMutableDictionary()
                resumeState["hasResumed"] = false
                let resumeLock = NSLock()

                // Set up one-time listener for acknowledgment
                let onAck: () -> Void = {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    if !(resumeState["hasResumed"] as? Bool ?? true) {
                        resumeState["hasResumed"] = true
                        passageLogger.debug("[REMOTE CONTROL] Received modalExit acknowledgment")
                        continuation.resume()
                    }
                }

                // Emit with callback for acknowledgment
                socket.emit("modalExit", modalExitData, completion: onAck)

                // Fallback timeout in case server doesn't respond
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    resumeLock.lock()
                    defer { resumeLock.unlock() }

                    if !(resumeState["hasResumed"] as? Bool ?? true) {
                        resumeState["hasResumed"] = true
                        passageLogger.debug("[REMOTE CONTROL] modalExit timeout, proceeding anyway")
                        continuation.resume()
                    }
                }
            } else {
                // If not connected, resolve immediately
                passageLogger.debug("[REMOTE CONTROL] Socket not connected, skipping modalExit")
                continuation.resume()
            }
        }
    }

    func disconnect() {
        passageLogger.info("[REMOTE CONTROL] DISCONNECTING: Current connection state: \(isConnected)")

        if let socket = socket {
            socket.removeAllHandlers()
            passageLogger.info("[REMOTE CONTROL] Socket event handlers removed")
            socket.disconnect()
            passageLogger.info("[REMOTE CONTROL] Socket disconnect called")
        } else {
            passageLogger.warn("[REMOTE CONTROL] Socket was already nil")
        }

        if let manager = manager {
            passageLogger.info("[REMOTE CONTROL] Manager status before cleanup: \(manager.status)")
        }

        socket = nil
        manager = nil

        // Stop screenshot capture
        stopScreenshotCapture()

        isConnected = false
        intentToken = nil
        lastUserActionCommand = nil
        currentCommand = nil
        currentWebViewType = PassageConstants.WebViewTypes.ui
        connectionData = nil
        connectionId = nil
        detectedWebViewUserAgent = nil
        configImageOptimization = nil

        // Reset success URLs on disconnect
        currentSuccessUrls = []
        passageLogger.debug("[REMOTE CONTROL] Reset success URLs on disconnect")

        onSuccess = nil
        onError = nil
        onDataComplete = nil
        onPromptComplete = nil

        passageLogger.info("[REMOTE CONTROL] Cleanup completed")
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let navigate = Notification.Name("PassageNavigate")
    static let navigateInAutomation = Notification.Name("PassageNavigateInAutomation")
    static let navigationCompleted = Notification.Name("PassageNavigationCompleted")
    static let injectScript = Notification.Name("PassageInjectScript")
    static let scriptExecutionResult = Notification.Name("PassageScriptExecutionResult")
    static let getPageData = Notification.Name("PassageGetPageData")
    static let collectPageData = Notification.Name("PassageCollectPageData")
    static let sendBrowserState = Notification.Name("PassageSendBrowserState")
    static let getCurrentUrlForBrowserState = Notification.Name("PassageGetCurrentUrlForBrowserState")
    static let showUIWebView = Notification.Name("PassageShowUIWebView")
    static let showAutomationWebView = Notification.Name("PassageShowAutomationWebView")
}
#endif
