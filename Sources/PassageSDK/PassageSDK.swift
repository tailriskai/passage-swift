import Foundation
#if canImport(UIKit)
import UIKit
import WebKit
#endif

// MARK: - Public Types

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
    ) {
        self.baseUrl = baseUrl ?? PassageConstants.Defaults.baseUrl
        self.socketUrl = socketUrl ?? PassageConstants.Defaults.socketUrl
        self.socketNamespace = socketNamespace ?? PassageConstants.Defaults.socketNamespace
        self.debug = debug
    }
}

public struct PassageHistoryItem {
    public let structuredData: Any?
    public let additionalData: [String: Any]
}

public struct PassageSuccessData {
    public let history: [PassageHistoryItem]
    public let connectionId: String
}

public struct PassageErrorData {
    public let error: String
    public let data: Any?
}

public struct PassageDataResult {
    public let data: Any?
    public let prompts: [[String: Any]]?
}

public struct PassagePromptResponse {
    public let key: String
    public let value: String
    public let response: Any?
}

public struct PassagePrompt {
    public let identifier: String
    public let prompt: String
    public let integrationId: String
    public let forceRefresh: Bool
    
    public init(identifier: String, prompt: String, integrationId: String, forceRefresh: Bool = false) {
        self.identifier = identifier
        self.prompt = prompt
        self.integrationId = integrationId
        self.forceRefresh = forceRefresh
    }
}

public struct PassageInitializeOptions {
    public let publishableKey: String
    public let prompts: [PassagePrompt]?
    public let onConnectionComplete: ((PassageSuccessData) -> Void)?
    public let onError: ((PassageErrorData) -> Void)?
    public let onDataComplete: ((PassageDataResult) -> Void)?
    public let onPromptComplete: ((PassagePromptResponse) -> Void)?
    public let onExit: ((String?) -> Void)?
    
    public init(
        publishableKey: String,
        prompts: [PassagePrompt]? = nil,
        onConnectionComplete: ((PassageSuccessData) -> Void)? = nil,
        onError: ((PassageErrorData) -> Void)? = nil,
        onDataComplete: ((PassageDataResult) -> Void)? = nil,
        onPromptComplete: ((PassagePromptResponse) -> Void)? = nil,
        onExit: ((String?) -> Void)? = nil
    ) {
        self.publishableKey = publishableKey
        self.prompts = prompts
        self.onConnectionComplete = onConnectionComplete
        self.onError = onError
        self.onDataComplete = onDataComplete
        self.onPromptComplete = onPromptComplete
        self.onExit = onExit
    }
}

#if canImport(UIKit)
public struct PassageOpenOptions {
    public let intentToken: String?
    public let prompts: [PassagePrompt]?
    public let onConnectionComplete: ((PassageSuccessData) -> Void)?
    public let onConnectionError: ((PassageErrorData) -> Void)?
    public let onDataComplete: ((PassageDataResult) -> Void)?
    public let onPromptComplete: ((PassagePromptResponse) -> Void)?
    public let onExit: ((String?) -> Void)?
    public let onWebviewChange: ((String) -> Void)?
    public let presentationStyle: PassagePresentationStyle?
    
    public init(
        intentToken: String? = nil,
        prompts: [PassagePrompt]? = nil,
        onConnectionComplete: ((PassageSuccessData) -> Void)? = nil,
        onConnectionError: ((PassageErrorData) -> Void)? = nil,
        onDataComplete: ((PassageDataResult) -> Void)? = nil,
        onPromptComplete: ((PassagePromptResponse) -> Void)? = nil,
        onExit: ((String?) -> Void)? = nil,
        onWebviewChange: ((String) -> Void)? = nil,
        presentationStyle: PassagePresentationStyle? = nil
    ) {
        self.intentToken = intentToken
        self.prompts = prompts
        self.onConnectionComplete = onConnectionComplete
        self.onConnectionError = onConnectionError
        self.onDataComplete = onDataComplete
        self.onPromptComplete = onPromptComplete
        self.onExit = onExit
        self.onWebviewChange = onWebviewChange
        self.presentationStyle = presentationStyle
    }
}
#endif

#if canImport(UIKit)
public enum PassagePresentationStyle {
    case modal
    case fullScreen
    
    var modalPresentationStyle: UIModalPresentationStyle {
        switch self {
        case .modal:
            return .pageSheet
        case .fullScreen:
            return .fullScreen
        }
    }
}
#endif

// MARK: - PassageSDK

#if canImport(UIKit)
public class Passage: NSObject {
    // Singleton instance
    public static let shared = Passage()
    
    // Configuration
    private var config: PassageConfig
    
    // WebView components - reusable instance
    private var webViewController: WebViewModalViewController?
    private var navigationController: UINavigationController?
    private var navigationCompletionHandler: ((Result<String, Error>) -> Void)?
    
    // Remote control
    private var remoteControl: RemoteControlManager?
    
    // Callbacks - matching React Native SDK structure
    private var onConnectionComplete: ((PassageSuccessData) -> Void)?
    private var onConnectionError: ((PassageErrorData) -> Void)?
    private var onDataComplete: ((PassageDataResult) -> Void)?
    private var onPromptComplete: ((PassagePromptResponse) -> Void)?
    private var onExit: ((String?) -> Void)?
    private var onWebviewChange: ((String) -> Void)?
    
    // MARK: - Initialization
    
    private override init() {
        self.config = PassageConfig()
        super.init()
        passageLogger.debug("PassageSDK initialized")
    }
    
    // MARK: - Public Methods
    
    public func initialize(_ options: PassageInitializeOptions) async throws {
        passageLogger.debugMethod("initialize", params: [
            "publishableKey": passageLogger.truncateData(options.publishableKey, maxLength: 20),
            "prompts": options.prompts?.count ?? 0
        ])
        
        // Store callbacks from initialization
        self.onConnectionComplete = options.onConnectionComplete
        self.onConnectionError = options.onError
        self.onDataComplete = options.onDataComplete
        self.onPromptComplete = options.onPromptComplete
        self.onExit = options.onExit
        
        // TODO: Implement publishable key handling and prompt setup
        // For now, this method exists for API compatibility
        
        passageLogger.info("[SDK] Initialized with \(options.prompts?.count ?? 0) prompts")
    }
    
    public func configure(_ config: PassageConfig) {
        self.config = config
        
        // Get SDK version automatically from bundle
        let sdkVersion = getSDKVersion()
        
        // Configure logger with unified debug flag and auto-detected SDK version
        passageLogger.configure(debug: config.debug, sdkVersion: sdkVersion)
        passageLogger.debugMethod("configure", params: [
            "baseUrl": config.baseUrl,
            "socketUrl": config.socketUrl,
            "socketNamespace": config.socketNamespace,
            "debug": config.debug,
            "sdkVersion": sdkVersion
        ])
        
        // Initialize remote control if needed
        if remoteControl == nil {
            remoteControl = RemoteControlManager(config: config)
        } else {
            remoteControl?.updateConfig(config)
        }
    }
    
    private func getSDKVersion() -> String {
        // Try to get version from the SDK bundle first
        let bundle = Bundle(identifier: "com.passage.PassageSDK") ?? Bundle.main
        if let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
            return version
        }
        
        // Fallback to a default version or try to detect from package info
        return "1.0.0"
    }
    
    public func open(_ options: PassageOpenOptions = PassageOpenOptions(), from viewController: UIViewController? = nil) {
        let token = options.intentToken ?? ""
        let presentationStyle = options.presentationStyle ?? .modal
        
        open(
            token: token,
            presentationStyle: presentationStyle,
            from: viewController,
            onConnectionComplete: options.onConnectionComplete,
            onConnectionError: options.onConnectionError,
            onDataComplete: options.onDataComplete,
            onPromptComplete: options.onPromptComplete,
            onExit: options.onExit,
            onWebviewChange: options.onWebviewChange
        )
    }
    
    public func open(
        token: String,
        presentationStyle: PassagePresentationStyle = .modal,
        from viewController: UIViewController? = nil,
        onConnectionComplete: ((PassageSuccessData) -> Void)? = nil,
        onConnectionError: ((PassageErrorData) -> Void)? = nil,
        onDataComplete: ((PassageDataResult) -> Void)? = nil,
        onPromptComplete: ((PassagePromptResponse) -> Void)? = nil,
        onExit: ((String?) -> Void)? = nil,
        onWebviewChange: ((String) -> Void)? = nil
    ) {
        passageLogger.info("[SDK] Opening Passage")
        passageLogger.debug("[SDK] Token length: \(token.count), Style: \(presentationStyle)")
        
        // Store callbacks
        self.onConnectionComplete = onConnectionComplete
        self.onConnectionError = onConnectionError
        self.onDataComplete = onDataComplete
        self.onPromptComplete = onPromptComplete
        self.onExit = onExit
        self.onWebviewChange = onWebviewChange
        
        // Build URL from token
        let url = buildUrlFromToken(token)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                passageLogger.error("[SDK] Self is nil in open closure")
                return
            }
            
            // Get presenting view controller
            let presentingVC = viewController ?? self.topMostViewController()
            
            guard let presentingVC = presentingVC else {
                let error = PassageErrorData(error: "No view controller available", data: nil)
                passageLogger.error("[SDK] ❌ No view controller available for presentation")
                self.onConnectionError?(error)
                return
            }
            
            // Create web view controller only once (lazy initialization)
            if self.webViewController == nil {
                passageLogger.info("[SDK] Creating new WebViewController (first time)")
                let webVC = WebViewModalViewController()
                
                // Configure the web view controller
                webVC.delegate = self
                webVC.remoteControl = self.remoteControl
                
                // Set webview change callback
                webVC.onWebviewChange = { [weak self] webviewType in
                    self?.handleWebviewChange(webviewType)
                }
                
                // Set up message handling (matches React Native Provider implementation)
                webVC.onMessage = { [weak self] message in
                    self?.handleMessage(message)
                }
                
                webVC.onClose = { [weak self] in
                    self?.handleClose()
                }
                
                self.webViewController = webVC
            } else {
                passageLogger.info("[SDK] Reusing existing WebViewController")
            }
            
            guard let webVC = self.webViewController else {
                passageLogger.error("[SDK] Failed to create or get WebViewController")
                return
            }
            
            // Update configuration for this open
            webVC.url = url
            webVC.showGrabber = (presentationStyle == .modal)
            webVC.titleText = PassageConstants.Defaults.modalTitle
            
            passageLogger.debug("[SDK] WebView configured with URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
            
            // Create navigation controller if needed
            if self.navigationController == nil || self.navigationController?.viewControllers.first !== webVC {
                let navController = UINavigationController(rootViewController: webVC)
                navController.modalPresentationStyle = presentationStyle.modalPresentationStyle
                
                // Enable pull-down dismissal
                navController.isModalInPresentation = false
                
                if #available(iOS 15.0, *) {
                    if let sheet = navController.sheetPresentationController {
                        sheet.detents = [.large()]
                        sheet.prefersGrabberVisible = true // Always show grabber for pull-down
                        sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                    }
                }
                
                // Set delegate to handle dismissal
                navController.presentationController?.delegate = webVC
                
                self.navigationController = navController
            }
            
            // Load the new URL
            webVC.loadURL(url)
            
            // Present the modal
            presentingVC.present(self.navigationController!, animated: true) {
                // Initialize remote control if needed
                self.initializeRemoteControl(with: token)
            }
        }
    }
    
    public func close() {
        passageLogger.debugMethod("close")
        
        DispatchQueue.main.async { [weak self] in
            self?.navigationController?.dismiss(animated: true) {
                // Don't cleanup webviews - keep them alive for reuse
                self?.cleanupAfterClose()
            }
        }
    }
    
    // MARK: - Navigation Methods
    
    public func navigate(to url: String) {
        webViewController?.navigateTo(url)
    }
    
    public func goBack() {
        webViewController?.goBack()
    }
    
    public func goForward() {
        webViewController?.goForward()
    }
    
    // MARK: - Cookie Management
    
    public func getCookies(for url: String, completion: @escaping ([HTTPCookie]) -> Void) {
        guard let urlObj = URL(string: url) else {
            completion([])
            return
        }
        
        DispatchQueue.main.async {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let filteredCookies = cookies.filter { cookie in
                    return self.cookieMatchesURL(cookie: cookie, url: urlObj)
                }
                completion(filteredCookies)
            }
        }
    }
    
    public func setCookie(_ cookie: HTTPCookie) {
        DispatchQueue.main.async {
            WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
        }
    }
    
    public func clearCookies(for url: String) {
        guard let urlObj = URL(string: url) else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let filteredCookies = cookies.filter { cookie in
                    return self.cookieMatchesURL(cookie: cookie, url: urlObj)
                }
                
                for cookie in filteredCookies {
                    WKWebsiteDataStore.default().httpCookieStore.delete(cookie)
                }
            }
        }
    }
    
    // MARK: - Resource Management
    
    /// Force a full cleanup of all resources including webviews
    /// This destroys all webviews and they will be recreated on next open()
    public func releaseResources() {
        passageLogger.info("[SDK] Force releasing all resources")
        cleanup()
    }
    
    // MARK: - JavaScript Injection
    
    public func injectJavaScript(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
        webViewController?.injectJavaScript(script, completion: completion)
    }
    
    // MARK: - Private Methods
    
    private func buildUrlFromToken(_ token: String) -> String {
        let baseUrl = config.baseUrl
        let urlString = "\(baseUrl)\(PassageConstants.Paths.connect)"
        
        guard let url = URL(string: urlString) else {
            passageLogger.error("[SDK] Failed to create URL from: \(urlString)")
            return urlString
        }
        
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            passageLogger.error("[SDK] Failed to create URLComponents from: \(url)")
            return url.absoluteString
        }
        
        // Generate SDK session like React Native does
        let sdkSession = "sdk-session-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(9))"
        
        components.queryItems = [
            URLQueryItem(name: "intentToken", value: token),
            URLQueryItem(name: "sdkSession", value: sdkSession)
        ]
        
        guard let finalUrl = components.url else {
            passageLogger.error("[SDK] Failed to create final URL with query items")
            return url.absoluteString
        }
        
        let result = finalUrl.absoluteString
        passageLogger.debug("[SDK] Built URL: \(passageLogger.truncateUrl(result, maxLength: 100))")
        passageLogger.debug("[SDK] Built URL with sdkSession: \(sdkSession)")
        return result
    }
    
    private func initializeRemoteControl(with token: String) {
        guard let remoteControl = remoteControl else { return }
        
        // Extract session ID from token
        passageLogger.updateIntentToken(token)
        
        // Set configuration callback to handle user agent and integration URL (matches React Native)
        remoteControl.setConfigurationCallback { [weak self] userAgent, integrationUrl in
            passageLogger.debug("[SDK] Configuration updated - userAgent: \(userAgent.isEmpty ? "none" : "provided"), integrationUrl: \(integrationUrl ?? "none")")
            
            DispatchQueue.main.async {
                // Update automation webview user agent if provided
                if !userAgent.isEmpty {
                    self?.webViewController?.setAutomationUserAgent(userAgent)
                }
                
                // Update automation webview URL if provided
                if let integrationUrl = integrationUrl {
                    self?.webViewController?.setAutomationUrl(integrationUrl)
                }
            }
        }
        
        // Connect remote control
        remoteControl.connect(
            intentToken: token,
            onSuccess: { [weak self] data in
                self?.onConnectionComplete?(data)
            },
            onError: { [weak self] error in
                self?.onConnectionError?(error)
            },
            onDataComplete: { [weak self] data in
                self?.onDataComplete?(data)
            },
            onPromptComplete: { [weak self] prompt in
                self?.onPromptComplete?(prompt)
            }
        )
    }
    
    private func handleMessage(_ message: Any) {
        if let data = message as? [String: Any],
           let type = data["type"] as? String {
            
            switch type {
            case "CONNECTION_SUCCESS":
                passageLogger.info("[SDK] 🎉 CONNECTION SUCCESS")
                handleConnectionSuccess(data)
                
            case "CONNECTION_ERROR":
                passageLogger.error("[SDK] ❌ CONNECTION ERROR")
                handleConnectionError(data)
                
            case "CLOSE_MODAL":
                passageLogger.info("[SDK] 🚪 CLOSE MODAL")
                close()
                
            case "page_loaded":
                // Handle page loaded events (less verbose)
                if let webViewType = data["webViewType"] as? String {
                    passageLogger.debug("[SDK] 📄 Page loaded in \(webViewType)")
                }
                
            case "navigation_finished":
                // Handle navigation finished events
                if let webViewType = data["webViewType"] as? String {
                    passageLogger.debug("[SDK] 🏁 Navigation finished in \(webViewType)")
                }
                
            default:
                // Forward other messages to remote control (matches React Native implementation)
                remoteControl?.handleWebViewMessage(data)
            }
        } else {
            passageLogger.debug("[SDK] Non-dictionary message received")
        }
    }
    
    private func handleConnectionSuccess(_ data: [String: Any]) {
        passageLogger.info("[SDK] handleConnectionSuccess called")
        passageLogger.debug("[SDK] WebView success data: \(data)")
        
        // Get the stored connection data from remote control
        let storedData = remoteControl?.getStoredConnectionData()
        
        passageLogger.debug("[SDK] Stored data from remote control:")
        passageLogger.debug("[SDK]   - Data array count: \(storedData?.data?.count ?? 0)")
        passageLogger.debug("[SDK]   - Connection ID: \(storedData?.connectionId ?? "nil")")
        
        var history: [PassageHistoryItem] = []
        var connectionId = ""
        
        if let actualData = storedData?.data, !actualData.isEmpty {
            // Use the actual Netflix data from connection event
            passageLogger.info("[SDK] ✅ Using stored connection data with \(actualData.count) items")
            
            history = actualData.map { item in
                PassageHistoryItem(
                    structuredData: item,
                    additionalData: [:]
                )
            }
            
            connectionId = storedData?.connectionId ?? ""
            passageLogger.info("[SDK] Using stored connection ID: \(connectionId)")
        } else {
            // Fallback to parsing history from WebView message (original behavior)
            passageLogger.warn("[SDK] ❌ No stored connection data found, using WebView message data")
            passageLogger.debug("[SDK] WebView message keys: \(data.keys)")
            
            history = parseHistory(from: data["history"])
            connectionId = data["connectionId"] as? String ?? ""
            passageLogger.warn("[SDK] WebView fallback - history count: \(history.count), connectionId: \(connectionId)")
        }
        
        let successData = PassageSuccessData(
            history: history,
            connectionId: connectionId
        )
        
        passageLogger.info("[SDK] Final success data - history: \(history.count) items, connectionId: \(connectionId)")
        onConnectionComplete?(successData)
        
        // Also trigger onDataComplete if we have data
        if !history.isEmpty {
            let dataResult = PassageDataResult(
                data: history.first?.structuredData,
                prompts: nil // TODO: Add prompt support when implemented
            )
            onDataComplete?(dataResult)
        }
        
        navigationController?.dismiss(animated: true) {
            self.cleanupAfterClose()
        }
    }
    
    private func handleConnectionError(_ data: [String: Any]) {
        let error = data["error"] as? String ?? "Unknown error"
        let errorData = PassageErrorData(error: error, data: data)
        
        onConnectionError?(errorData)
        navigationController?.dismiss(animated: true) {
            self.cleanupAfterClose()
        }
    }
    
    private func handleClose() {
        onExit?("user_action")
        cleanupAfterClose()
    }
    
    private func handleWebviewChange(_ webviewType: String) {
        passageLogger.debug("[SDK] Webview changed to: \(webviewType)")
        onWebviewChange?(webviewType)
    }
    
    private func parseHistory(from data: Any?) -> [PassageHistoryItem] {
        guard let historyArray = data as? [[String: Any]] else { return [] }
        
        return historyArray.map { item in
            let structuredData = item["structuredData"]
            var additionalData = item
            additionalData.removeValue(forKey: "structuredData")
            
            return PassageHistoryItem(
                structuredData: structuredData,
                additionalData: additionalData
            )
        }
    }
    
    private func cleanupAfterClose() {
        // Only cleanup transient state, keep webviews alive
        remoteControl?.disconnect()
        navigationCompletionHandler = nil
        // Don't nil out webViewController - keep it for reuse
        passageLogger.debug("[SDK] Cleanup after close completed, webviews kept alive")
    }
    
    private func cleanup() {
        // Full cleanup - only called when SDK is being deallocated
        webViewController = nil
        navigationController = nil
        remoteControl?.disconnect()
        navigationCompletionHandler = nil
        passageLogger.debug("[SDK] Full cleanup completed, all resources released")
    }
    
    private func topMostViewController() -> UIViewController? {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
              var topController = window.rootViewController else {
            return nil
        }
        
        while let presentedViewController = topController.presentedViewController {
            topController = presentedViewController
        }
        
        return topController
    }
    
    private func cookieMatchesURL(cookie: HTTPCookie, url: URL) -> Bool {
        guard let host = url.host else { return false }
        
        // Check domain
        let cookieDomain = cookie.domain.hasPrefix(".") ? cookie.domain : ".\(cookie.domain)"
        let hostWithDot = ".\(host)"
        
        if !hostWithDot.hasSuffix(cookieDomain) && host != cookie.domain {
            return false
        }
        
        // Check path
        let path = url.path.isEmpty ? "/" : url.path
        if !path.hasPrefix(cookie.path) {
            return false
        }
        
        // Check secure
        if cookie.isSecure && url.scheme != "https" {
            return false
        }
        
        return true
    }
    
    deinit {
        // Ensure full cleanup when SDK is deallocated
        cleanup()
        passageLogger.debug("[SDK] PassageSDK deallocated")
    }
}

// MARK: - WebViewModalDelegate
extension Passage: WebViewModalDelegate {
    func webViewModalDidClose() {
        passageLogger.debug("WebViewModalDelegate: webViewModalDidClose called")
        handleClose()
    }
    
    func webViewModal(didNavigateTo url: URL) {
        passageLogger.debug("WebViewModalDelegate: didNavigateTo called with URL: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
        
        // Call the navigation completion handler if it exists
        if let handler = navigationCompletionHandler {
            passageLogger.debug("WebViewModalDelegate: calling navigation completion handler")
            navigationCompletionHandler = nil
            handler(.success(url.absoluteString))
        }
    }
}
#endif

// MARK: - Cross-Platform Core

/// Core Passage functionality available on all platforms
public class PassageCore {
    // Singleton instance
    public static let shared = PassageCore()
    
    // Configuration
    private var config: PassageConfig
    
    // Analytics and logging are available on all platforms
    public let analytics = PassageAnalytics.shared
    public let logger = PassageLogger.shared
    
    private init() {
        self.config = PassageConfig()
        
        // Configure analytics with SDK version
        analytics.configure(.default, sdkVersion: sdkVersion)
        
        passageLogger.info("[SDK] PassageCore initialized (cross-platform)")
    }
    
    public func configure(_ config: PassageConfig) {
        self.config = config
        
        // Configure logger
        logger.configure(debug: config.debug)
        
        // Update analytics configuration
        analytics.configure(.default, sdkVersion: sdkVersion)
        
        passageLogger.info("[SDK] PassageCore configured - baseUrl: \(config.baseUrl)")
    }
    
    public var sdkVersion: String {
        return "0.0.1"
    }
    
    public func cleanup() {
        analytics.cleanup()
        passageLogger.info("[SDK] PassageCore cleanup completed")
    }
}

#if canImport(UIKit)
// Convenience alias for iOS - maintains backward compatibility
public typealias PassageClient = Passage
#else
// On non-iOS platforms, use the core functionality
public typealias PassageClient = PassageCore
#endif
