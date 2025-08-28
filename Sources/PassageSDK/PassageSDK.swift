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
    public let agentName: String
    
    public init(
        baseUrl: String? = nil,
        socketUrl: String? = nil,
        socketNamespace: String? = nil,
        debug: Bool = false,
        agentName: String? = nil
    ) {
        self.baseUrl = baseUrl ?? PassageConstants.Defaults.baseUrl
        self.socketUrl = socketUrl ?? PassageConstants.Defaults.socketUrl
        self.socketNamespace = socketNamespace ?? PassageConstants.Defaults.socketNamespace
        self.debug = debug
        self.agentName = agentName ?? PassageConstants.Defaults.agentName
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
    
    // Debug: Track instance lifecycle
    private let instanceId = UUID().uuidString
    
    // WebView components - reusable instance
    private var webViewController: WebViewModalViewController?
    private var navigationController: UINavigationController?
    private var navigationCompletionHandler: ((Result<String, Error>) -> Void)?
    
    // Remote control
    private var remoteControl: RemoteControlManager?
    
    // State management
    private var isClosing: Bool = false
    private var isPresentingModal: Bool = false
    private var modalPresentationTimer: Timer?
    
    // Callbacks - matching React Native SDK structure
    private var onConnectionComplete: ((PassageSuccessData) -> Void)?
    private var onConnectionError: ((PassageErrorData) -> Void)?
    private var onDataComplete: ((PassageDataResult) -> Void)?
    private var onPromptComplete: ((PassagePromptResponse) -> Void)?
    private var onExit: ((String?) -> Void)?
    private var onWebviewChange: ((String) -> Void)?
    private var lastWebviewType: String = PassageConstants.WebViewTypes.ui
    
    // MARK: - Initialization
    
    private override init() {
        self.config = PassageConfig()
        super.init()
        passageLogger.info("[SDK] PassageSDK initialized - Instance ID: \(instanceId.prefix(8))")
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
        // Configure analytics and track configure lifecycle
        passageAnalytics.configure(.default, sdkVersion: sdkVersion)
        passageAnalytics.trackConfigureStart()
        passageLogger.debugMethod("configure", params: [
            "baseUrl": config.baseUrl,
            "socketUrl": config.socketUrl,
            "socketNamespace": config.socketNamespace,
            "debug": config.debug,
            "sdkVersion": sdkVersion
        ])
        passageAnalytics.trackConfigureSuccess(config: [
            "baseUrl": config.baseUrl,
            "socketUrl": config.socketUrl,
            "socketNamespace": config.socketNamespace,
            "debug": config.debug
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
        passageLogger.info("[SDK:\(instanceId.prefix(8))] ========== OPEN() CALLED ==========")
        passageLogger.debug("[SDK:\(instanceId.prefix(8))] Token length: \(token.count), Style: \(presentationStyle)")
        passageLogger.debug("[SDK:\(instanceId.prefix(8))] Current isClosing state: \(isClosing)")
        passageLogger.debug("[SDK:\(instanceId.prefix(8))] Current onExit callback: \(self.onExit != nil ? "exists" : "nil")")
        passageAnalytics.trackOpenRequest(token: token)
        
        // Reset closing flag for new session - must be done synchronously before storing callbacks
        passageLogger.info("[SDK] Resetting isClosing flag from \(isClosing) to false")
        isClosing = false
        
        // Store callbacks
        passageLogger.info("[SDK] Storing new callbacks...")
        passageLogger.debug("[SDK] Previous onExit: \(self.onExit != nil ? "existed" : "nil")")
        passageLogger.info("[SDK] Thread info - isMainThread: \(Thread.isMainThread)")
        
        // Debug callback identity
        if let existingExit = self.onExit {
            passageLogger.warn("[SDK] ⚠️ onExit callback already exists! This shouldn't happen after cleanup")
            passageLogger.debug("[SDK] Existing callback identity: \(String(describing: existingExit))")
        }
        
        self.onConnectionComplete = onConnectionComplete
        self.onConnectionError = onConnectionError
        self.onDataComplete = onDataComplete
        self.onPromptComplete = onPromptComplete
        self.onExit = onExit
        self.onWebviewChange = onWebviewChange
        
        passageLogger.info("[SDK] Callbacks stored - onExit: \(onExit != nil ? "SET" : "NIL")")
        passageLogger.debug("[SDK] New onExit callback: \(self.onExit != nil ? "exists" : "nil")")
        
        // Double-check the callback was stored
        if self.onExit == nil && onExit != nil {
            passageLogger.error("[SDK] ❌ CRITICAL: onExit callback was not stored properly!")
        }
        
        // Build URL from token
        let url = buildUrlFromToken(token)
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                passageLogger.error("[SDK] Self is nil in open closure")
                return
            }
            
            // Prevent concurrent presentations which can cause UIKit crashes
            if self.isPresentingModal {
                passageLogger.warn("[SDK] open() called while a presentation is in progress. Ignoring this call to prevent double-present.")
                return
            }

            // Get presenting view controller
            let presentingVC = viewController ?? self.topMostViewController()
            
            guard let presentingVC = presentingVC else {
                let error = PassageErrorData(error: "No view controller available", data: nil)
                passageLogger.error("[SDK] ❌ No view controller available for presentation")
                self.onConnectionError?(error)
                passageAnalytics.trackOpenError(error: "No view controller available", context: "presentation")
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
                
                // Note: onClose is not set here to avoid duplicate calls
                // The delegate method webViewModalDidClose will handle closing
                
                self.webViewController = webVC
            } else {
                passageLogger.info("[SDK] Reusing existing WebViewController")
            }
            
            guard let webVC = self.webViewController else {
                passageLogger.error("[SDK] Failed to create or get WebViewController")
                return
            }
            
            // Ensure delegate is set (important for callbacks)
            webVC.delegate = self
            passageLogger.info("[SDK] WebViewController delegate set to self")
            
            // Update configuration for this open
            webVC.url = url
            webVC.showGrabber = (presentationStyle == .modal)
            webVC.titleText = PassageConstants.Defaults.modalTitle
            
            passageLogger.debug("[SDK] WebView configured with URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
            let styleString = (presentationStyle == .modal) ? PassageConstants.PresentationStyles.pageSheet : PassageConstants.PresentationStyles.fullScreen
            passageAnalytics.trackModalOpened(presentationStyle: styleString, url: url)
            
            // Create navigation controller if needed
            if self.navigationController == nil || self.navigationController?.viewControllers.first !== webVC {
                passageLogger.info("[SDK] Creating new navigation controller")
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
            } else {
                passageLogger.info("[SDK] Reusing existing navigation controller")
                // Ensure delegate is still set when reusing
                self.navigationController?.presentationController?.delegate = webVC
            }
            
            // Load the new URL
            webVC.loadURL(url)

            // If already presented, do not attempt to present again. Just update URL and (re)initialize session.
            if let navController = self.navigationController,
               navController.presentingViewController != nil {
                passageLogger.warn("[SDK] Navigation controller is already presented. Updating URL and initializing remote control without re-presenting.")
                self.initializeRemoteControl(with: token)
                passageAnalytics.trackOpenSuccess(url: url)
                return
            }

            // Present the modal (single-flight)
            self.isPresentingModal = true
            self.presentNavigationController(self.navigationController!, from: presentingVC, token: token, url: url)
        }
    }
    
    private func presentNavigationController(_ navController: UINavigationController, from presentingVC: UIViewController, token: String, url: String) {
        passageLogger.info("[SDK] Presenting navigation controller...")
        passageLogger.debug("[SDK] Presenting VC: \(presentingVC), Nav controller: \(navController)")
        passageLogger.debug("[SDK] onExit before presentation: \(self.onExit != nil ? "exists" : "nil")")
        
        presentingVC.present(navController, animated: true) { [weak self] in
            guard let self = self else {
                passageLogger.error("[SDK] Self became nil during presentation!")
                return
            }
            
            passageLogger.info("[SDK] ✅ Modal presented successfully")
            passageLogger.debug("[SDK] onExit callback after presentation: \(self.onExit != nil ? "exists" : "nil")")
            
            // Initialize remote control if needed
            self.initializeRemoteControl(with: token)
            passageAnalytics.trackOpenSuccess(url: url)

            // Mark presentation as finished
            self.isPresentingModal = false
        }
    }
    
    public func close() {
        passageLogger.debugMethod("close")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Check if already closing
            guard !self.isClosing else {
                passageLogger.debug("[SDK] close() called but already closing, ignoring")
                return
            }
            
            self.isClosing = true
            
            // Call onExit before dismissing
            self.onExit?("programmatic_close")
            passageAnalytics.trackModalClosed(reason: "programmatic_close")
            
            self.navigationController?.dismiss(animated: true) { [weak self] in
                guard let self = self else {
                    passageLogger.error("[SDK] Self became nil during programmatic close!")
                    return
                }
                
                passageLogger.info("[SDK] Navigation controller dismissed (programmatic)")
                // Don't cleanup webviews - keep them alive for reuse
                self.cleanupAfterClose()
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
    
    /// Clear cookies for a specific URL only (preserves localStorage, sessionStorage, and other data)
    /// Use clearWebViewData() if you want to clear everything including localStorage and sessionStorage
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
    
    /// Clear all cookies only (preserves localStorage, sessionStorage, and other data)
    /// Use clearWebViewData() if you want to clear everything including localStorage and sessionStorage
    public func clearAllCookies() {
        passageLogger.info("[SDK] Clearing all cookies only (preserving localStorage, sessionStorage)")
        
        DispatchQueue.main.async {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                passageLogger.debug("[SDK] Found \(cookies.count) cookies to clear")
                
                for cookie in cookies {
                    WKWebsiteDataStore.default().httpCookieStore.delete(cookie)
                }
                
                passageLogger.info("[SDK] All cookies cleared successfully")
            }
        }
    }
    
    /// Clear all cookies only (preserves localStorage, sessionStorage, and other data) with completion handler
    /// Use clearWebViewData() if you want to clear everything including localStorage and sessionStorage
    public func clearAllCookies(completion: @escaping () -> Void) {
        passageLogger.info("[SDK] Clearing all cookies only (preserving localStorage, sessionStorage)")
        
        DispatchQueue.main.async {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                passageLogger.debug("[SDK] Found \(cookies.count) cookies to clear")
                
                for cookie in cookies {
                    WKWebsiteDataStore.default().httpCookieStore.delete(cookie)
                }
                
                passageLogger.info("[SDK] All cookies cleared successfully")
                completion()
            }
        }
    }
    
    public func clearWebViewState() {
        passageLogger.info("[SDK] Clearing webview navigation state (preserving cookies, localStorage, sessionStorage)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Clear webview navigation state only - preserves cookies, localStorage, sessionStorage
            self.webViewController?.clearWebViewState()
            
            passageLogger.info("[SDK] WebView navigation state cleared successfully")
        }
    }
    
    /// Clear all webview data including cookies, localStorage, sessionStorage
    /// This is a manual method that should be called when you want to completely reset the webview state
    public func clearWebViewData() {
        passageLogger.info("[SDK] Clearing ALL webview data including cookies, localStorage, sessionStorage")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Clear all webview data including cookies, localStorage, sessionStorage
            self.webViewController?.clearWebViewData()
            
            passageLogger.info("[SDK] ALL WebView data cleared successfully")
        }
    }
    
    /// Clear all webview data including cookies, localStorage, sessionStorage with completion handler
    /// This is a manual method that should be called when you want to completely reset the webview state
    public func clearWebViewData(completion: @escaping () -> Void) {
        passageLogger.info("[SDK] Clearing ALL webview data including cookies, localStorage, sessionStorage")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { 
                completion()
                return 
            }
            
            // Clear all webview data including cookies, localStorage, sessionStorage
            self.webViewController?.clearWebViewData {
                passageLogger.info("[SDK] ALL WebView data cleared successfully")
                completion()
            }
        }
    }
    
    /// Reset webview URLs to empty/initial state
    /// This is automatically called when the modal closes, but can be called manually if needed
    public func resetWebViewURLs() {
        passageLogger.info("[SDK] Resetting webview URLs to empty state")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Reset URL state in the webview controller
            self.webViewController?.resetURLState()
            
            passageLogger.info("[SDK] WebView URLs reset successfully")
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
            URLQueryItem(name: "sdkSession", value: sdkSession),
            URLQueryItem(name: "agentName", value: config.agentName)
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
        passageAnalytics.updateSessionInfo(intentToken: token, sessionId: nil)
        
        // Set configuration callback to handle user agent and integration URL (matches React Native)
        remoteControl.setConfigurationCallback { [weak self] userAgent, integrationUrl in
            passageLogger.debug("[SDK] Configuration updated - userAgent: \(userAgent.isEmpty ? "empty" : "provided (\(userAgent.count) chars)"), integrationUrl: \(integrationUrl ?? "none")")
            
            DispatchQueue.main.async {
                // Update automation webview user agent if provided
                if !userAgent.isEmpty {
                    passageLogger.info("[SDK] Setting custom automation user agent (\(userAgent.count) chars)")
                    self?.webViewController?.setAutomationUserAgent(userAgent)
                } else {
                    passageLogger.info("[SDK] Using default automation webview user agent (no custom user agent provided)")
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
                passageLogger.info("[SDK] 🚪 CLOSE MODAL message received from WebView")
                passageLogger.debug("[SDK] Current state - isClosing: \(isClosing), onExit: \(onExit != nil ? "exists" : "nil")")
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
        passageAnalytics.trackOnSuccess(historyCount: history.count, connectionId: connectionId)
        
        // Also trigger onDataComplete if we have data
        if !history.isEmpty {
            let dataResult = PassageDataResult(
                data: history.first?.structuredData,
                prompts: nil // TODO: Add prompt support when implemented
            )
            onDataComplete?(dataResult)
        }
        
        // Mark as closing to prevent duplicate close handling
        isClosing = true
        passageAnalytics.trackModalClosed(reason: "success")
        
        passageLogger.info("[SDK] Dismissing navigation controller from success handler...")
        navigationController?.dismiss(animated: true) { [weak self] in
            guard let self = self else {
                passageLogger.error("[SDK] Self became nil during dismiss animation!")
                return
            }
            
            passageLogger.info("[SDK] Navigation controller dismissed (success)")
            passageLogger.debug("[SDK] onExit after dismiss: \(self.onExit != nil ? "exists" : "nil")")
            
            // Clear webview state after successful connection before cleanup
            self.clearWebViewState()
            self.cleanupAfterClose()
        }
    }
    
    private func handleConnectionError(_ data: [String: Any]) {
        let error = data["error"] as? String ?? "Unknown error"
        let errorData = PassageErrorData(error: error, data: data)
        
        onConnectionError?(errorData)
        passageAnalytics.trackOnError(error: error, data: data)
        
        // Mark as closing to prevent duplicate close handling
        isClosing = true
        passageAnalytics.trackModalClosed(reason: "error")
        navigationController?.dismiss(animated: true) {
            // Clear webview state after error before cleanup
            self.clearWebViewState()
            self.cleanupAfterClose()
        }
    }
    
    private func handleClose() {
        passageLogger.info("[SDK:\(instanceId.prefix(8))] ========== HANDLE CLOSE CALLED ==========")
        passageLogger.info("[SDK:\(instanceId.prefix(8))] Current isClosing: \(isClosing)")
        passageLogger.info("[SDK:\(instanceId.prefix(8))] Current onExit callback: \(onExit != nil ? "EXISTS" : "NIL")")
        passageLogger.debug("[SDK:\(instanceId.prefix(8))] Thread: \(Thread.isMainThread ? "Main" : "Background")")
        
        // Always call onExit if available, even if already closing
        // This ensures the callback is not missed due to race conditions
        if onExit != nil && !isClosing {
            passageLogger.info("[SDK] ✅ Calling onExit callback with reason: user_action")
            onExit?("user_action")
            passageAnalytics.trackModalClosed(reason: "user_action")
        } else {
            passageLogger.warn("[SDK] ❌ NOT calling onExit - onExit: \(onExit != nil), isClosing: \(isClosing)")
            if onExit == nil {
                passageLogger.error("[SDK] ⚠️ onExit is NIL - this is why callback isn't firing!")
            }
            if isClosing {
                passageLogger.warn("[SDK] ⚠️ isClosing is true - preventing callback")
            }
        }
        
        // Prevent duplicate cleanup
        guard !isClosing else {
            passageLogger.warn("[SDK] Already closing, skipping duplicate cleanup")
            return
        }
        
        passageLogger.info("[SDK] Setting isClosing to true")
        isClosing = true
        
        // Clear webview state and perform cleanup
        passageLogger.debug("[SDK] Clearing webview state and performing cleanup")
        clearWebViewState()
        cleanupAfterClose()
    }
    
    private func handleWebviewChange(_ webviewType: String) {
        passageLogger.debug("[SDK] Webview changed to: \(webviewType)")
        passageAnalytics.trackWebViewSwitch(from: lastWebviewType, to: webviewType, reason: "remote_control")
        lastWebviewType = webviewType
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
        passageLogger.info("[SDK] ========== CLEANUP AFTER CLOSE ==========")
        passageLogger.debug("[SDK] Current onExit before cleanup: \(onExit != nil ? "exists" : "nil")")
        passageLogger.info("[SDK] Cleanup called on thread - isMainThread: \(Thread.isMainThread)")
        
        // Reset webview URLs to ensure clean state for next session
        webViewController?.resetURLState()
        
        // Clear callbacks synchronously first to prevent race conditions
        passageLogger.info("[SDK] Clearing callbacks SYNCHRONOUSLY first...")
        self.navigationCompletionHandler = nil
        self.onConnectionComplete = nil
        self.onConnectionError = nil
        self.onDataComplete = nil
        self.onPromptComplete = nil
        self.onExit = nil
        self.onWebviewChange = nil
        passageLogger.info("[SDK] Callbacks cleared synchronously - onExit is now: \(self.onExit != nil ? "STILL EXISTS??" : "nil")")
        
        // Emit modalExit and disconnect remote control asynchronously
        Task { @MainActor in
            passageLogger.debug("[SDK] Async cleanup - emitting modalExit and disconnecting remote control...")
            await remoteControl?.emitModalExit()
            remoteControl?.disconnect()
            
            // Reset closing flag after everything is complete
            // This must be the last thing we do to ensure all cleanup is done
            passageLogger.info("[SDK] Resetting isClosing flag from true to false")
            self.isClosing = false
            
            passageLogger.info("[SDK] ✅ Async cleanup completed - isClosing: \(self.isClosing)")
        }
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
        let window: UIWindow?
        
        if #available(iOS 15.0, *) {
            // Use UIWindowScene.windows for iOS 15+
            window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else if #available(iOS 13.0, *) {
            // Use UIWindowScene.windows for iOS 13-14
            window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            // Fallback for iOS 12 and earlier
            window = UIApplication.shared.windows.first { $0.isKeyWindow }
        }
        
        guard let window = window,
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
        // This should never happen for a singleton, but ensure cleanup if it does
        passageLogger.error("[SDK:\(instanceId.prefix(8))] ❌ PassageSDK DEINIT CALLED! This should never happen for a singleton!")
        cleanup()
        passageLogger.debug("[SDK] PassageSDK deallocated")
    }
}

// MARK: - WebViewModalDelegate
extension Passage: WebViewModalDelegate {
    func webViewModalDidClose() {
        passageLogger.info("[SDK:\(instanceId.prefix(8))] ========== WebViewModalDelegate: webViewModalDidClose ==========")
        passageLogger.info("[SDK:\(instanceId.prefix(8))] Current state - isClosing: \(isClosing), onExit: \(onExit != nil ? "EXISTS" : "NIL")")
        passageLogger.debug("[SDK:\(instanceId.prefix(8))] Delegate called on thread: \(Thread.isMainThread ? "Main" : "Background")")
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
    
    // MARK: - Recording Methods (matching React Native SDK)
    
    /// Complete recording session with optional data
    /// Matches React Native SDK completeRecording method
    public func completeRecording(data: [String: Any]? = nil) async throws {
        passageLogger.debug("[SDK] completeRecording called with data: \(data != nil)")
        
        guard let remoteControl = remoteControl else {
            passageLogger.error("[SDK] completeRecording failed - no remote control available")
            throw PassageError.noRemoteControl
        }
        
        // Call the remote control's complete recording method
        await remoteControl.completeRecording(data: data ?? [:])
        passageLogger.info("[SDK] completeRecording completed successfully")
    }
    
    /// Capture recording data without completing the session
    /// Matches React Native SDK captureRecordingData method
    public func captureRecordingData(data: [String: Any]? = nil) async throws {
        passageLogger.debug("[SDK] captureRecordingData called with data: \(data != nil)")
        
        guard let remoteControl = remoteControl else {
            passageLogger.error("[SDK] captureRecordingData failed - no remote control available")
            throw PassageError.noRemoteControl
        }
        
        // Call the remote control's capture recording data method
        await remoteControl.captureRecordingData(data: data ?? [:])
        passageLogger.info("[SDK] captureRecordingData completed successfully")
    }
    
    /// Complete recording session with optional data (completion handler version for Objective-C compatibility)
    /// Matches React Native SDK completeRecording method
    public func completeRecording(data: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                try await completeRecording(data: data)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
    
    /// Capture recording data without completing the session (completion handler version for Objective-C compatibility)
    /// Matches React Native SDK captureRecordingData method
    public func captureRecordingData(data: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        Task {
            do {
                try await captureRecordingData(data: data)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }
    }
}

// MARK: - Passage Errors

public enum PassageError: Error, LocalizedError {
    case noRemoteControl
    case invalidConfiguration
    case recordingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .noRemoteControl:
            return "Remote control is not available. Make sure Passage is properly configured."
        case .invalidConfiguration:
            return "Invalid Passage configuration."
        case .recordingFailed(let message):
            return "Recording failed: \(message)"
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
    
    /// Clear all webview data including cookies, localStorage, sessionStorage
    /// Note: This method is only available on iOS. On other platforms, it's a no-op.
    public func clearWebViewData() {
        #if canImport(UIKit)
        // Delegate to the iOS implementation
        Passage.shared.clearWebViewData()
        #else
        passageLogger.info("[SDK] clearWebViewData() not available on this platform")
        #endif
    }
    
    /// Clear all webview data including cookies, localStorage, sessionStorage with completion handler
    /// Note: This method is only available on iOS. On other platforms, it's a no-op.
    public func clearWebViewData(completion: @escaping () -> Void) {
        #if canImport(UIKit)
        // Delegate to the iOS implementation
        Passage.shared.clearWebViewData(completion: completion)
        #else
        passageLogger.info("[SDK] clearWebViewData() not available on this platform")
        completion()
        #endif
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
