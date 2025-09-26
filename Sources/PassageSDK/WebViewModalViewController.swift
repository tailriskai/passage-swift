#if canImport(UIKit)
import UIKit
@preconcurrency import WebKit

// Define the delegate protocol
protocol WebViewModalDelegate: AnyObject {
    func webViewModalDidClose()
    func webViewModal(didNavigateTo url: URL)
}

// Define structure to hold pending command info
struct PendingUserActionCommand {
    let commandId: String
    let script: String
    let timestamp: Date
}

// Custom WKWebView that can prevent becoming first responder
class PassageWKWebView: WKWebView {
    var shouldPreventFirstResponder: Bool = false
    
    override var canBecomeFirstResponder: Bool {
        return shouldPreventFirstResponder ? false : super.canBecomeFirstResponder
    }
    
    override func becomeFirstResponder() -> Bool {
        return shouldPreventFirstResponder ? false : super.becomeFirstResponder()
    }
}

class WebViewModalViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    weak var delegate: WebViewModalDelegate?
    
    var modalTitle: String = ""
    var titleText: String = ""
    var showGrabber: Bool = false
    // Optional initial URL. If set, loads on viewDidLoad.
    var url: String = ""
    
    // Callback closures
    var onMessage: ((Any) -> Void)?
    var onClose: (() -> Void)?
    var onWebviewChange: ((String) -> Void)?
    
    // Remote control reference (for navigation completion)
    var remoteControl: RemoteControlManager?
    
    // Dual webviews - created once and reused across sessions
    // These are never destroyed during the SDK lifecycle unless releaseResources() is called
    private var uiWebView: PassageWKWebView!
    private var automationWebView: PassageWKWebView!
    
    private var currentURL: String = ""
    private var isShowingUIWebView: Bool = true
    private var isAnimating: Bool = false
    
    
    // Store pending user action command
    private var pendingUserActionCommand: PendingUserActionCommand?
    
    // Screenshot support (matching React Native implementation)
    private var currentScreenshot: String?
    private var previousScreenshot: String?
    
    // Store automation webview custom user agent from configuration
    private var automationUserAgent: String?
    
    // Store initial URL to load after view appears
    private var initialURLToLoad: String?
    
    // Reference to modern close button for animations
    private var modernCloseButton: UIView?

    // Reference to back button for visibility management
    private var backButton: UIView?
    
    // Header container that stays above webviews
    private var headerContainer: UIView?
    
    // Track webview state before showing close confirmation
    private var wasShowingAutomationBeforeClose: Bool = false
    
    // Track close button presses to enable double-press close
    private var closeButtonPressCount: Int = 0

    // Track if navigation was triggered by back button (to skip backend tracking)
    private var isNavigatingFromBackButton: Bool = false

    // Track if back navigation should be disabled (after programmatic navigate command)
    private var isBackNavigationDisabled: Bool = false
    
    // Debug: force rendering just one webview with a predefined URL
    private let debugSingleWebViewUrl: String? = nil
        // Force a simple single webview configuration
    private let forceSimpleWebView: Bool = false
    
    // Navigation timeout timer
    private var navigationTimeoutTimer: Timer?
    private var navigationStartTime: Date?
    
    // Track intended navigation URLs to handle navigation failures
    private var intendedAutomationURL: String?
    private var intendedUIURL: String?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        passageLogger.info("[WEBVIEW] ========== VIEW DID LOAD ==========")
        passageLogger.info("[WEBVIEW] View controller instance: \(String(format: "%p", unsafeBitCast(self, to: Int.self)))")
        passageLogger.info("[WEBVIEW] Initial URL: \(url.isEmpty ? "empty" : passageLogger.truncateUrl(url, maxLength: 100))")
        passageLogger.info("[WEBVIEW] Show grabber: \(showGrabber)")
        passageLogger.info("[WEBVIEW] Title text: \(titleText)")
        passageLogger.info("[WEBVIEW] Force simple webview: \(forceSimpleWebView)")
        passageLogger.info("[WEBVIEW] Debug single webview URL: \(debugSingleWebViewUrl ?? "nil")")
        passageLogger.info("[WEBVIEW] Existing webviews - UI: \(uiWebView != nil), Automation: \(automationWebView != nil)")
        
        // Log view state
        passageLogger.info("[WEBVIEW] View loaded: \(isViewLoaded)")
        passageLogger.info("[WEBVIEW] View in window: \(view.window != nil)")
        passageLogger.info("[WEBVIEW] View superview: \(view.superview != nil)")
        
        // Disable modal drag-to-dismiss
        isModalInPresentation = true
        
        // Setup screenshot accessors for remote control
        setupScreenshotAccessors()
        
        setupUI()
        
        // Don't set up notification observers here - do it in viewDidAppear
        // to avoid duplicate observers from reused view controllers
        
        // Hide navigation bar since we're using custom header
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        passageLogger.debug("[WEBVIEW] Navigation bar shown with custom header")

        // If in debug single-webview mode, we've already created and loaded it in setupWebViews.
        if let debugUrl = debugSingleWebViewUrl, !debugUrl.isEmpty {
            passageLogger.info("[WEBVIEW DEBUG MODE] Single webview mode active with URL: \(passageLogger.truncateUrl(debugUrl, maxLength: 100))")
            return
        }

        // If `url` was set, load it immediately
        if !url.isEmpty {
            passageLogger.info("[WEBVIEW] Loading provided URL immediately: \(passageLogger.truncateUrl(url, maxLength: 100))")
            loadURL(url)
        } else if let pending = initialURLToLoad {
            // If a URL was queued before view was ready, load it now
            passageLogger.info("[WEBVIEW] Loading pending URL: \(passageLogger.truncateUrl(pending, maxLength: 100))")
            initialURLToLoad = nil
            loadURL(pending)
        } else {
            passageLogger.warn("[WEBVIEW] No URL to load in viewDidLoad")
        }

        passageLogger.info("[WEBVIEW] viewDidLoad completed")
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        passageLogger.info("[WEBVIEW] ========== VIEW DID APPEAR ==========")
        passageLogger.info("[WEBVIEW] View controller instance: \(String(format: "%p", unsafeBitCast(self, to: Int.self)))")
        passageLogger.info("[WEBVIEW] Webview states - UI: \(uiWebView != nil), Automation: \(automationWebView != nil)")
        passageLogger.info("[WEBVIEW] Webview superviews - UI: \(uiWebView?.superview != nil), Automation: \(automationWebView?.superview != nil)")
        
        // Reset close button press counter when modal appears
        closeButtonPressCount = 0
        passageLogger.debug("[WEBVIEW] Reset close button press counter")
        
        // Re-add notification observers (they were removed in viewWillDisappear)
        setupNotificationObservers()

        // Ensure WebViews are set up only if they're not already properly configured
        if uiWebView == nil || automationWebView == nil || uiWebView?.superview == nil || automationWebView?.superview == nil {
            passageLogger.info("[WEBVIEW] WebViews not properly set up, initializing...")
            setupWebViews()
            
            // Load any pending URL after webviews are set up
            if let pendingURL = initialURLToLoad {
                passageLogger.info("[WEBVIEW] Loading pending URL after webview setup: \(passageLogger.truncateUrl(pendingURL, maxLength: 100))")
                initialURLToLoad = nil
                loadURL(pendingURL)
            }
        } else {
            passageLogger.debug("[WEBVIEW] WebViews already properly configured")
        }

        // Quick validation - only log if there are issues
        if uiWebView == nil {
            passageLogger.error("[WEBVIEW] UI WebView is nil!")
        } else if let url = uiWebView?.url {
            passageLogger.debug("[WEBVIEW] UI WebView URL: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
        }
        
        // Load initial URL if it was set before view appeared
        if let urlToLoad = initialURLToLoad {
            passageLogger.info("[WEBVIEW] Loading deferred URL: \(passageLogger.truncateUrl(urlToLoad, maxLength: 100))")
            initialURLToLoad = nil
            loadURL(urlToLoad)
        }
        
        // Reset to UI webview when reappearing (in case automation was shown)
        if !isShowingUIWebView {
            passageLogger.info("[WEBVIEW] Resetting to UI webview on reappear")
            showUIWebView()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        passageLogger.info("[WEBVIEW] ========== VIEW WILL DISAPPEAR ==========")
        passageLogger.info("[WEBVIEW] View controller instance: \(String(format: "%p", unsafeBitCast(self, to: Int.self)))")
        
        // Cancel any pending navigation timeout
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
        
        
        // Remove notification observers to prevent duplicate notifications
        NotificationCenter.default.removeObserver(self)
        passageLogger.info("[WEBVIEW] Removed all notification observers")
    }
    
    deinit {
        passageLogger.info("[WEBVIEW] ========== DEINIT ==========")
        passageLogger.info("[WEBVIEW] View controller instance being deallocated: \(String(format: "%p", unsafeBitCast(self, to: Int.self)))")
        
        // Clean up timers
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
        
        // Remove KVO observers
        uiWebView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        automationWebView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
        passageLogger.info("[WEBVIEW] Notification observers removed")
    }
    
    private func setupUI() {
        // Set background color to white to match navigation bar
        view.backgroundColor = UIColor.white
        
        // No close button - modal should be dismissed via swipe down or programmatically
    }
    
    
    private func setupNotificationObservers() {
        passageLogger.info("[WEBVIEW] Setting up notification observers")
        
        // Remove any existing observers first to prevent duplicates
        NotificationCenter.default.removeObserver(self)
        
        // Observe webview switching notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showUIWebViewNotification),
            name: .showUIWebView,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showAutomationWebViewNotification),
            name: .showAutomationWebView,
            object: nil
        )
        
        // Observe navigation notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigateInAutomationNotification(_:)),
            name: .navigateInAutomation,
            object: nil
        )
        
        // Observe general navigation notifications (for UI webview)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigateNotification(_:)),
            name: .navigate,
            object: nil
        )
        
        // Observe script injection notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(injectScriptNotification(_:)),
            name: .injectScript,
            object: nil
        )
        
        // Observe page data request notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(getPageDataNotification(_:)),
            name: .getPageData,
            object: nil
        )
        
        // Observe page data collection notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(collectPageDataNotification(_:)),
            name: .collectPageData,
            object: nil
        )
        
        // Observe URL requests for browser state with screenshot
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(getCurrentUrlForBrowserStateNotification(_:)),
            name: .getCurrentUrlForBrowserState,
            object: nil
        )
        
        // Observe keyboard notifications to prevent keyboard from showing when automation webview has focus
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidShow(_:)),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
    }
    
    @objc private func showUIWebViewNotification() {
        passageLogger.info("[WEBVIEW] Received showUIWebView notification")
        passageLogger.debug("[WEBVIEW] Notification source: \(String(describing: Thread.callStackSymbols[0...3]))")
        showUIWebView()
    }
    
    @objc private func showAutomationWebViewNotification() {
        passageLogger.info("[WEBVIEW] Received showAutomationWebView notification")
        passageLogger.debug("[WEBVIEW] Notification source: \(String(describing: Thread.callStackSymbols[0...3]))")
        showAutomationWebView()
    }
    
    @objc private func navigateInAutomationNotification(_ notification: Notification) {
        passageLogger.info("[WEBVIEW] ========== NAVIGATE IN AUTOMATION NOTIFICATION ==========")
        passageLogger.info("[WEBVIEW] 📡 Received navigateInAutomation notification")

        guard let url = notification.userInfo?["url"] as? String else {
            passageLogger.error("[WEBVIEW] ❌ Navigate notification missing URL")
            passageLogger.error("[WEBVIEW] Available userInfo keys: \(notification.userInfo?.keys.map { "\($0)" } ?? [])")
            return
        }
        let commandId = notification.userInfo?["commandId"] as? String
        passageLogger.info("[WEBVIEW] ✅ Navigate URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
        passageLogger.info("[WEBVIEW] Command ID: \(commandId ?? "nil")")

        // Check if we're already on this URL - if so, return success immediately
        if let currentURL = automationWebView?.url?.absoluteString, currentURL == url {
            passageLogger.info("[WEBVIEW] ✅ Already on target URL, returning success without navigating")

            // Notify remote control of successful navigation (even though we didn't actually navigate)
            remoteControl?.checkNavigationEnd(url)

            return
        }

        // Clear navigation history and disable back button for this programmatic navigation
        clearAutomationNavigationHistory()

        passageLogger.info("[WEBVIEW] 🚀 Calling navigateInAutomationWebView...")
        navigateInAutomationWebView(url)
    }
    
    @objc private func navigateNotification(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? String else {
            passageLogger.error("[WEBVIEW] Navigate notification missing URL")
            return
        }
        passageLogger.info("[WEBVIEW] Received UI navigate notification: \(passageLogger.truncateUrl(url, maxLength: 100))")
        
        // Navigate in UI webview with delay (like React Native WEBVIEW_SWITCH_DELAY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.navigateInUIWebView(url)
        }
    }
    
    @objc private func injectScriptNotification(_ notification: Notification) {
        injectScriptNotification(notification, retryCount: 0)
    }

    private func injectScriptNotification(_ notification: Notification, retryCount: Int) {
        guard let script = notification.userInfo?["script"] as? String,
              let commandId = notification.userInfo?["commandId"] as? String else {
            passageLogger.error("[WEBVIEW] Inject script notification missing data")
            return
        }

        let commandType = notification.userInfo?["commandType"] as? String ?? "unknown"
        passageLogger.info("[WEBVIEW] Executing \(commandType) script for command: \(commandId) (retry: \(retryCount))")
        passageLogger.debug("[WEBVIEW] View controller instance: \(String(format: "%p", unsafeBitCast(self, to: Int.self)))")
        passageLogger.debug("[WEBVIEW] Webview states - UI: \(uiWebView != nil), Automation: \(automationWebView != nil)")

        // Check if WebViews are ready for script injection
        guard areWebViewsReady() else {
            // Limit retries to prevent infinite loops
            let maxRetries = 10

            if retryCount >= maxRetries {
                passageLogger.error("[WEBVIEW] Max retries (\(maxRetries)) exceeded, failing script injection")
                passageLogger.error("[WEBVIEW] Final state - UI: \(uiWebView != nil), Automation: \(automationWebView != nil)")
                // Send error result back to remote control
                NotificationCenter.default.post(
                    name: .scriptExecutionResult,
                    object: nil,
                    userInfo: [
                        "commandId": commandId,
                        "success": false,
                        "error": "WebViews not ready for script injection after \(maxRetries) retries - page may not be loaded"
                    ]
                )
                return
            }

            passageLogger.warn("[WEBVIEW] WebViews not ready for script injection, will retry... (attempt \(retryCount + 1)/\(maxRetries))")
            passageLogger.debug("[WEBVIEW] WebViews ready check failed, scheduling retry")

            // Retry after a short delay instead of immediately failing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }

                // Re-check if WebViews are ready now
                if self.areWebViewsReady() {
                    passageLogger.info("[WEBVIEW] WebViews now ready, proceeding with script injection")
                    // Re-call the method with incremented retry count
                    self.injectScriptNotification(notification, retryCount: retryCount + 1)
                } else {
                    // Try again with incremented retry count
                    self.injectScriptNotification(notification, retryCount: retryCount + 1)
                }
            }
            return
        }
        
        // Check if this is an async script that uses window.passage.postMessage
        let usesWindowPassage = script.contains("window.passage.postMessage")
        let isAsyncScript = script.contains("async function") || commandType == "wait"
        
        if isAsyncScript && usesWindowPassage {
            // For async scripts that use window.passage.postMessage, inject with "; undefined;" suffix
            // This matches the React Native implementation
            passageLogger.debug("[WEBVIEW] Injecting async script with window.passage.postMessage")
            
            let scriptWithUndefined = script + "; undefined;"
            
            injectJavaScriptInAutomationWebView(scriptWithUndefined) { result, error in
                if let error = error {
                    passageLogger.error("[WEBVIEW] Async script injection failed: \(error)")
                    // Send error result back to remote control
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .scriptExecutionResult,
                            object: nil,
                            userInfo: [
                                "commandId": commandId,
                                "success": false,
                                "error": error.localizedDescription
                            ]
                        )
                    }
                } else {
                    passageLogger.debug("[WEBVIEW] Async script injected successfully, waiting for result via postMessage")
                    // Don't send result here - the script will send it via window.passage.postMessage
                    
                    // Set up a timeout in case the script doesn't respond
                    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                        // Check if we still haven't received a response
                        passageLogger.warn("[WEBVIEW] Async script timeout for command: \(commandId), no postMessage received")
                    }
                }
            }
        } else {
            // For synchronous scripts, handle normally
            injectJavaScriptInAutomationWebView(script) { result, error in
                if let error = error {
                    passageLogger.error("[WEBVIEW] Script injection failed: \(error)")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .scriptExecutionResult,
                            object: nil,
                            userInfo: [
                                "commandId": commandId,
                                "success": false,
                                "error": error.localizedDescription
                            ]
                        )
                    }
                } else {
                    passageLogger.debug("[WEBVIEW] Script injection completed successfully")
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(
                            name: .scriptExecutionResult,
                            object: nil,
                            userInfo: [
                                "commandId": commandId,
                                "success": true,
                                "result": result as Any
                            ]
                        )
                    }
                }
            }
        }
    }
    
    @objc private func getPageDataNotification(_ notification: Notification) {
        guard let commandId = notification.userInfo?["commandId"] as? String else {
            passageLogger.error("[WEBVIEW] Get page data notification missing commandId")
            return
        }
        passageLogger.info("[WEBVIEW] Received get page data notification for command: \(commandId)")
        // This would typically collect page data and send it back via RemoteControlManager
        // For now, we'll let the RemoteControlManager handle this
    }
    
    @objc private func collectPageDataNotification(_ notification: Notification) {
        guard let script = notification.userInfo?["script"] as? String else {
            passageLogger.error("[WEBVIEW] Collect page data notification missing script")
            return
        }
        
        passageLogger.info("[WEBVIEW] Collecting page data from automation webview")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let automationWebView = self.automationWebView else {
                passageLogger.error("[WEBVIEW] Automation webview not available for page data collection")
                return
            }
            
            automationWebView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    passageLogger.error("[WEBVIEW] Page data collection script failed: \(error)")
                } else {
                    passageLogger.debug("[WEBVIEW] Page data collection script executed successfully")
                }
            }
        }
    }
    
    @objc private func getCurrentUrlForBrowserStateNotification(_ notification: Notification) {
        passageLogger.info("[WEBVIEW URL] ========== GET CURRENT URL FOR BROWSER STATE ==========")
        
        guard let userInfo = notification.userInfo else {
            passageLogger.error("[WEBVIEW URL] ❌ getCurrentUrlForBrowserState notification missing userInfo")
            return
        }
        
        // Log what data we received
        passageLogger.info("[WEBVIEW URL] Notification userInfo keys: \(userInfo.keys.sorted { "\($0)" < "\($1)" })")
        
        if let screenshot = userInfo["screenshot"] as? String {
            passageLogger.info("[WEBVIEW URL] ✅ Screenshot data received: \(screenshot.count) chars")
        } else if userInfo["screenshot"] != nil {
            passageLogger.warn("[WEBVIEW URL] ⚠️ Screenshot field present but not a String: \(type(of: userInfo["screenshot"]!))")
        } else {
            passageLogger.warn("[WEBVIEW URL] ⚠️ No screenshot data in notification")
        }
        
        if let trigger = userInfo["trigger"] as? String {
            passageLogger.debug("[WEBVIEW URL] Trigger: \(trigger)")
        }
        
        if let interval = userInfo["interval"] as? TimeInterval {
            passageLogger.debug("[WEBVIEW URL] Interval: \(interval)")
        }
        
        if let imageOpt = userInfo["imageOptimization"] as? [String: Any] {
            passageLogger.debug("[WEBVIEW URL] Image optimization: \(imageOpt)")
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                passageLogger.error("[WEBVIEW URL] ❌ Self is nil")
                if let continuation = userInfo["continuation"] as? CheckedContinuation<Void, Never> {
                    continuation.resume()
                }
                return
            }
            
            guard let automationWebView = self.automationWebView else {
                passageLogger.warn("[WEBVIEW URL] ⚠️ Automation webview not available, using fallback")
                
                // Fallback to using a default URL if automation webview not available
                let browserStateData: [String: Any] = [
                    "url": self.currentURL ?? "unknown",
                    "screenshot": userInfo["screenshot"] ?? NSNull(),
                    "trigger": userInfo["trigger"] ?? NSNull(),
                    "interval": userInfo["interval"] ?? NSNull(),
                    "imageOptimization": userInfo["imageOptimization"] ?? NSNull()
                ]
                
                passageLogger.info("[WEBVIEW URL] 📤 Sending fallback browser state with URL: \(self.currentURL ?? "unknown")")
                
                NotificationCenter.default.post(
                    name: .sendBrowserState,
                    object: nil,
                    userInfo: browserStateData
                )
                
                if let continuation = userInfo["continuation"] as? CheckedContinuation<Void, Never> {
                    continuation.resume()
                }
                return
            }
            
            passageLogger.debug("[WEBVIEW URL] Getting current URL from automation webview...")
            
            // Get current URL from automation webview
            automationWebView.evaluateJavaScript("window.location.href") { result, error in
                var url = "unknown"
                
                if let error = error {
                    passageLogger.warn("[WEBVIEW URL] Failed to get current URL: \(error)")
                    url = self.currentURL ?? "unknown"
                } else if let urlResult = result as? String {
                    url = urlResult
                    passageLogger.info("[WEBVIEW URL] ✅ Current URL from automation webview: \(passageLogger.truncateUrl(url, maxLength: 100))")
                } else {
                    passageLogger.warn("[WEBVIEW URL] URL result was not a string, using fallback")
                    url = self.currentURL ?? "unknown"
                }
                
                // Send browser state with all the screenshot data
                let browserStateData: [String: Any] = [
                    "url": url,
                    "screenshot": userInfo["screenshot"] ?? NSNull(),
                    "trigger": userInfo["trigger"] ?? NSNull(),
                    "interval": userInfo["interval"] ?? NSNull(),
                    "imageOptimization": userInfo["imageOptimization"] ?? NSNull()
                ]
                
                passageLogger.info("[WEBVIEW URL] 📤 Sending browser state with URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
                let hasScreenshot = browserStateData["screenshot"] as? String != nil
                passageLogger.info("[WEBVIEW URL] Browser state contains screenshot: \(hasScreenshot)")
                
                NotificationCenter.default.post(
                    name: .sendBrowserState,
                    object: nil,
                    userInfo: browserStateData
                )
                
                // Resume the continuation from the screenshot capture
                if let continuation = userInfo["continuation"] as? CheckedContinuation<Void, Never> {
                    continuation.resume()
                } else {
                    passageLogger.warn("[WEBVIEW URL] ⚠️ No continuation to resume")
                }
            }
        }
    }
    
    // MARK: - Keyboard Management
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        // If UI webview is visible, immediately dismiss the keyboard since it must be from the hidden automation webview
        guard isShowingUIWebView else {
            passageLogger.debug("[KEYBOARD] Automation webview is visible, allowing keyboard")
            return
        }
        
        passageLogger.info("[KEYBOARD] Keyboard will show while UI webview is visible - dismissing immediately")
        
        // Immediately dismiss keyboard since UI webview is visible
        DispatchQueue.main.async { [weak self] in
            self?.view.endEditing(true)
        }
    }
    
    @objc private func keyboardDidShow(_ notification: Notification) {
        // If UI webview is visible, immediately dismiss the keyboard
        guard isShowingUIWebView else {
            passageLogger.debug("[KEYBOARD] Automation webview is visible, keyboard allowed")
            return
        }
        
        passageLogger.info("[KEYBOARD] Keyboard did show while UI webview is visible - dismissing immediately")
        
        // Immediately dismiss keyboard
        DispatchQueue.main.async { [weak self] in
            self?.view.endEditing(true)
        }
    }
    
    // MARK: - KVO for URL Changes
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == #keyPath(WKWebView.url) else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        guard let webView = object as? WKWebView else { return }
        
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        
        // Get old and new URLs
        let oldURL = (change?[.oldKey] as? URL)?.absoluteString
        let newURL = (change?[.newKey] as? URL)?.absoluteString
        
        // Only process if URL actually changed
        if let newURL = newURL, newURL != oldURL {
            passageLogger.info("[KVO] URL changed in \(webViewType): \(passageLogger.truncateUrl(newURL, maxLength: 100))")
            
            // Handle the URL change (captures client-side navigation like pushState)
            handleNavigationStateChange(url: newURL, loading: webView.isLoading, webViewType: webViewType)
            
            // For automation webview, check for success URL match
            if webViewType == PassageConstants.WebViewTypes.automation {
                remoteControl?.checkNavigationEnd(newURL)
            }
            
            // Send delegate callback
            if let url = URL(string: newURL) {
                delegate?.webViewModal(didNavigateTo: url)
            }
        }
    }
    
    private func createWebView(webViewType: String) -> PassageWKWebView {
        passageLogger.info("[WEBVIEW] ========== CREATING WEBVIEW ==========")
        passageLogger.info("[WEBVIEW] WebView type: \(webViewType)")
        passageLogger.info("[WEBVIEW] Force simple webview: \(forceSimpleWebView)")
        passageLogger.info("[WEBVIEW] Debug URL: \(debugSingleWebViewUrl ?? "nil")")
        
        // Create WKWebView configuration
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Enable JavaScript (required)
        // Note: javaScriptEnabled is deprecated in iOS 14.0+, but JavaScript is enabled by default
        // We keep this for iOS 13 compatibility, but it's a no-op on iOS 14+
        if #available(iOS 14.0, *) {
            // JavaScript is enabled by default in iOS 14+
            passageLogger.debug("[WEBVIEW] JavaScript enabled by default (iOS 14+)")
        } else {
            configuration.preferences.javaScriptEnabled = true
            passageLogger.debug("[WEBVIEW] JavaScript enabled: true (iOS 13)")
        }
        
        // Allow inline media playback
        configuration.allowsInlineMediaPlayback = true
        passageLogger.debug("[WEBVIEW] Inline media playback allowed: true")
        
        // Keep config minimal for https loads
        
        // Set up messaging — in simple mode, skip all scripts/handlers to avoid CSP/conflicts
        if !forceSimpleWebView && debugSingleWebViewUrl == nil {
            passageLogger.info("[WEBVIEW] Setting up message handlers and scripts")
            let userContentController = WKUserContentController()
            
            // Add message handler for modal communication
            userContentController.add(self, name: PassageConstants.MessageHandlers.passageWebView)
            
            // Inject window.passage script immediately on webview creation
            let passageScript = createPassageScript(for: webViewType)
            let userScript = WKUserScript(
                source: passageScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            userContentController.addUserScript(userScript)
            
            // For automation webview, also inject global JavaScript on every navigation
            if webViewType == PassageConstants.WebViewTypes.automation {
                passageLogger.info("[WEBVIEW] Setting up global JavaScript injection for automation webview")
                let globalScript = generateGlobalJavaScript()
                
                if !globalScript.isEmpty {
                    passageLogger.info("[WEBVIEW] 🚀 Injecting global JavaScript into automation webview")
                    
                    // Wrap the global script to wait for window.passage initialization
                    let delayedGlobalScript = """
                    console.log('[Passage] Global JavaScript injection script starting...');
                    
                    (function() {
                        let attemptCount = 0;
                        const maxAttempts = 100; // 5 seconds max wait
                        
                        function waitForPassage() {
                            attemptCount++;
                            console.log('[Passage] Checking for window.passage... attempt ' + attemptCount);
                            
                            if (window.passage && window.passage.initialized) {
                                console.log('[Passage] ✅ window.passage ready, executing global script');
                                try {
                                    \(globalScript)
                                    console.log('[Passage] ✅ Global script execution completed');
                                } catch (error) {
                                    console.error('[Passage] ❌ Error in global script execution:', error);
                                }
                            } else if (attemptCount < maxAttempts) {
                                console.log('[Passage] ⏳ Waiting for window.passage initialization... (' + attemptCount + '/' + maxAttempts + ')');
                                setTimeout(waitForPassage, 50);
                            } else {
                                console.error('[Passage] ❌ Timeout waiting for window.passage after ' + (maxAttempts * 50) + 'ms');
                            }
                        }
                        
                        // Start checking after a small delay
                        console.log('[Passage] Starting window.passage check in 100ms...');
                        setTimeout(waitForPassage, 100);
                    })();
                    """
                    
                    let globalUserScript = WKUserScript(
                        source: delayedGlobalScript,
                        injectionTime: .atDocumentEnd,
                        forMainFrameOnly: true
                    )
                    userContentController.addUserScript(globalUserScript)
                    passageLogger.info("[WEBVIEW] ✅ Added delayed global JavaScript to automation webview (\(globalScript.count) chars)")
                } else {
                    passageLogger.info("[WEBVIEW] ℹ️ No global JavaScript to inject in automation webview (empty script)")
                }
            }
            
            // Add console logging script with WeakMap error detection
            let consoleScript = """
            (function() {
                // Capture console.error
                const originalError = console.error;
                console.error = function() {
                    originalError.apply(console, arguments);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                        window.webkit.messageHandlers.passageWebView.postMessage({
                            type: 'console_error',
                            message: Array.from(arguments).map(arg => String(arg)).join(' '),
                            webViewType: '\(webViewType)'
                        });
                    }
                };
                
                // Capture uncaught errors with special handling for WeakMap errors
                window.addEventListener('error', function(event) {
                    const isWeakMapError = event.message && event.message.includes('WeakMap');
                    
                    if (isWeakMapError) {
                        console.error('[Passage] WeakMap error detected:', event.message);
                        console.error('[Passage] This may be caused by global JavaScript injection timing');
                    }
                    
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                        window.webkit.messageHandlers.passageWebView.postMessage({
                            type: 'javascript_error',
                            message: event.message,
                            source: event.filename,
                            line: event.lineno,
                            column: event.colno,
                            stack: event.error ? event.error.stack : '',
                            webViewType: '\(webViewType)',
                            isWeakMapError: isWeakMapError
                        });
                    }
                });
                
                // Capture unhandled promise rejections
                window.addEventListener('unhandledrejection', function(event) {
                    console.error('[Passage] Unhandled promise rejection:', event.reason);
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                        window.webkit.messageHandlers.passageWebView.postMessage({
                            type: 'unhandled_rejection',
                            message: String(event.reason),
                            webViewType: '\(webViewType)'
                        });
                    }
                });
            })();
            """
            let consoleUserScript = WKUserScript(
                source: consoleScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            userContentController.addUserScript(consoleUserScript)
            
            configuration.userContentController = userContentController
        } else {
            configuration.userContentController = WKUserContentController()
        }
        
        // Create web view
        let webView = PassageWKWebView(frame: .zero, configuration: configuration)
        
        // Set user agent based on webview type and configuration
        if webViewType == PassageConstants.WebViewTypes.automation && automationUserAgent != nil {
            // Use stored automation user agent from configuration
            webView.customUserAgent = automationUserAgent
            passageLogger.debug("[WEBVIEW] Applied stored user agent to automation webview: \(automationUserAgent ?? "")")
        } else if debugSingleWebViewUrl != nil || forceSimpleWebView {
            // In debug/simple mode, set a Safari-like user agent
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        }
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        
        // Set background color to white initially
        webView.backgroundColor = .white
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .white
        
        // Disable zoom on the scroll view
        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bouncesZoom = false
        
        // Enable Safari debugging
        if #available(iOS 16.4, *) {
            webView.isInspectable = true
            passageLogger.debug("WebView inspection enabled for iOS 16.4+")
        } else {
            // For older iOS versions, enable through private API (development only)
            #if DEBUG
            webView.perform(Selector(("setInspectable:")), with: true)
            passageLogger.debug("WebView inspection enabled via legacy method")
            #endif
        }
        
        // Use default user agent
        
    // Tag webviews for identification
    webView.tag = webViewType == PassageConstants.WebViewTypes.automation ? 2 : 1
    
    // Add observer for URL changes to catch all navigation events
    webView.addObserver(self, forKeyPath: #keyPath(WKWebView.url), options: [.new, .old], context: nil)
    
    // Detect and store the WebView user agent for remote control configuration
    // This ensures the backend receives the actual WebKit user agent instead of CFNetwork
    if let remoteControl = remoteControl {
        // Detect user agent immediately when WebView is created
        remoteControl.detectWebViewUserAgent(from: webView)
    }
    
    return webView
}
    
    private func setupWebViews() {
        passageLogger.info("[WEBVIEW] ========== SETUP WEBVIEWS ==========")
        passageLogger.info("[WEBVIEW] Current state - UI: \(uiWebView != nil), Automation: \(automationWebView != nil)")
        passageLogger.info("[WEBVIEW] Superviews - UI: \(uiWebView?.superview != nil), Automation: \(automationWebView?.superview != nil)")
        
        // Check if webviews are already created and active
        if uiWebView != nil && automationWebView != nil && uiWebView.superview != nil && automationWebView.superview != nil {
            passageLogger.info("[WEBVIEW] WebViews already created and active, skipping setup")
            return
        }

        // If WebViews were previously released, clean up any remaining references
        if uiWebView != nil || automationWebView != nil {
            passageLogger.info("[WEBVIEW] Cleaning up partially released WebViews before recreation")
            releaseWebViews()
        }
        
        // If simple mode or debugSingleWebViewUrl is set, render only one webview and load that URL
        if forceSimpleWebView || (debugSingleWebViewUrl != nil) {
            let initialUrl = debugSingleWebViewUrl
            // Visually distinct background to ensure we see the container
            view.backgroundColor = UIColor.systemYellow.withAlphaComponent(0.2)

            uiWebView = createWebView(webViewType: PassageConstants.WebViewTypes.ui)
            uiWebView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.2)
            view.addSubview(uiWebView)
            NSLayoutConstraint.activate([
                uiWebView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                uiWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                uiWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                uiWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
            ])

            // Add debug overlay label
            let debugLabel = UILabel()
            debugLabel.text = "DEBUG VIEW"
            debugLabel.textColor = .white
            debugLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.6)
            debugLabel.textAlignment = .center
            debugLabel.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(debugLabel)
            NSLayoutConstraint.activate([
                debugLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
                debugLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                debugLabel.heightAnchor.constraint(equalToConstant: 24)
            ])

            automationWebView = nil
            isShowingUIWebView = true
            passageLogger.debug("[SIMPLE MODE] Rendering local HTML to verify WebView rendering pipeline; then try external URL if available")

            // Load simple HTML first to eliminate any network issues
            let html = """
            <html>
              <head>
                <meta name=viewport content="width=device-width, initial-scale=1">
                <style>body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#fef3c7;margin:0;padding:24px} .card{background:#bbf7d0;padding:16px;border-radius:12px;border:2px dashed #16a34a}</style>
              </head>
              <body>
                <div class=card>
                  <h2>WKWebView Debug</h2>
                  <p>If you see this, the webview is rendering HTML correctly.</p>
                </div>
              </body>
            </html>
            """
            uiWebView.loadHTMLString(html, baseURL: nil)

            // Probe network quickly to log connectivity and optionally render fetched HTML
            if let urlString = initialUrl, let testUrl = URL(string: urlString) {
                var req = URLRequest(url: testUrl)
                req.httpMethod = "HEAD"
                URLSession.shared.dataTask(with: req) { _, response, error in
                    if let error = error {
                        passageLogger.error("[DEBUG MODE] URLSession probe error: \(error.localizedDescription)")
                    } else if let http = response as? HTTPURLResponse {
                        passageLogger.debug("[DEBUG MODE] URLSession probe status: \(http.statusCode) for \(passageLogger.truncateUrl(testUrl.absoluteString, maxLength: 100))")
                        // If success, try fetching HTML and render inline as a fallback diagnostic
                        if (200...299).contains(http.statusCode) {
                            URLSession.shared.dataTask(with: testUrl) { data, _, err in
                                if let data = data, let html = String(data: data, encoding: .utf8) {
                                    passageLogger.debug("[DEBUG MODE] Loaded HTML: \(passageLogger.truncateHtml(html)). Rendering inline for visibility test.")
                                    DispatchQueue.main.async { [weak self] in
                                        self?.uiWebView?.loadHTMLString(html, baseURL: testUrl)
                                    }
                                } else if let err = err {
                                    passageLogger.error("[DEBUG MODE] GET fetch error: \(err.localizedDescription)")
                                } else {
                                    passageLogger.error("[DEBUG MODE] GET fetch returned no data")
                                }
                            }.resume()
                        }
                    } else {
                        passageLogger.debug("[DEBUG MODE] URLSession probe got non-HTTP response")
                    }
                }.resume()
            }

            // After a short delay, try loading the external URL (still in debug mode)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                if let urlString = initialUrl {
                    self?.loadURL(urlString)
                } else if let sdkUrl = self?.url, !sdkUrl.isEmpty {
                    self?.loadURL(sdkUrl)
                }
            }
            return
        }
        
        // Create header container first so we can reference it in webview constraints
        createHeaderContainer()
        
        // Create both webviews (default behavior)
        uiWebView = createWebView(webViewType: PassageConstants.WebViewTypes.ui)
        automationWebView = createWebView(webViewType: PassageConstants.WebViewTypes.automation)
        
        // Add both webviews to the view hierarchy
        view.addSubview(uiWebView)
        view.addSubview(automationWebView)
        
        // Setup constraints for both webviews (they overlap) - start below header container
        NSLayoutConstraint.activate([
            // UI webview constraints - start below header container
            uiWebView.topAnchor.constraint(equalTo: headerContainer!.bottomAnchor),
            uiWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            uiWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            uiWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            // Automation webview constraints (same as UI)
            automationWebView.topAnchor.constraint(equalTo: headerContainer!.bottomAnchor),
            automationWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            automationWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            automationWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Initially show UI webview, hide automation webview
        uiWebView.alpha = 1
        automationWebView.alpha = 0
        view.bringSubviewToFront(uiWebView)
        
        // Set initial first responder behavior - prevent automation webview from becoming first responder initially
        automationWebView.shouldPreventFirstResponder = true
        uiWebView.shouldPreventFirstResponder = false
        
        // Ensure header is on top after adding webviews
        if let header = headerContainer {
            view.bringSubviewToFront(header)
        }

        // Update back button visibility when webviews are ready
        updateBackButtonVisibility()
    }
    
    private func createHeaderContainer() {
        // Create header container that will always stay above webviews
        let container = UIView()
        container.backgroundColor = UIColor.white
        container.translatesAutoresizingMaskIntoConstraints = false
        
        // Add container AFTER webviews to ensure proper layering
        view.addSubview(container)
        
        // Position header container at the top with proper height
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 57) // Extends to cover safe area + header height
        ])
        
        self.headerContainer = container
        
        // Add header elements to the container
        addLogoToContainer(container)
        addBackButtonToContainer(container)
        addCloseButtonToContainer(container)
        addHeaderBorderToContainer(container)
        
        // Ensure header stays above webviews
        view.bringSubviewToFront(container)
    }
    
    private func addLogoToView() {
        // Create logo view for direct placement on view
        let logoContainer = UIView()
        logoContainer.backgroundColor = UIColor.clear
        
        var logoView: UIView
        
        if let logoImage = UIImage(named: "passage", in: Bundle(for: Self.self), compatibleWith: nil) {
            // Use embedded image logo
            let logoImageView = UIImageView(image: logoImage)
            logoImageView.contentMode = UIView.ContentMode.scaleAspectFit
            logoView = logoImageView
        } else {
            // Fallback to text logo
            let logoLabel = UILabel()
            logoLabel.text = "passage"
            logoLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
            logoLabel.textColor = UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0) // Passage blue
            logoLabel.textAlignment = .center
            logoView = logoLabel
        }
        
        logoContainer.addSubview(logoView)
        view.addSubview(logoContainer)
        
        logoContainer.translatesAutoresizingMaskIntoConstraints = false
        logoView.translatesAutoresizingMaskIntoConstraints = false
        
        // Center logo at top with exact 120x40 container
        NSLayoutConstraint.activate([
            logoContainer.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            logoContainer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            logoContainer.widthAnchor.constraint(equalToConstant: 120),
            logoContainer.heightAnchor.constraint(equalToConstant: 40),
            
            logoView.centerXAnchor.constraint(equalTo: logoContainer.centerXAnchor),
            logoView.centerYAnchor.constraint(equalTo: logoContainer.centerYAnchor),
            logoView.leadingAnchor.constraint(greaterThanOrEqualTo: logoContainer.leadingAnchor, constant: 4),
            logoView.trailingAnchor.constraint(lessThanOrEqualTo: logoContainer.trailingAnchor, constant: -4),
            logoView.topAnchor.constraint(greaterThanOrEqualTo: logoContainer.topAnchor, constant: 4),
            logoView.bottomAnchor.constraint(lessThanOrEqualTo: logoContainer.bottomAnchor, constant: -4)
        ])
        
        view.bringSubviewToFront(logoContainer)
    }
    
    private func addCloseButtonToView() {
        // Create simple bold X close button without background - black and bigger
        let closeButton = UILabel()
        closeButton.text = "×"
        closeButton.font = UIFont.systemFont(ofSize: 32, weight: .light)
        closeButton.textColor = UIColor.black
        closeButton.textAlignment = .center
        closeButton.backgroundColor = UIColor.clear
        closeButton.isUserInteractionEnabled = true
        
        view.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        
        // Position in top-right corner - centered vertically with logo, 48x48 touch area
        NSLayoutConstraint.activate([
            closeButton.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 48),
            closeButton.heightAnchor.constraint(equalToConstant: 48)
        ])
        
        // Add tap gesture with animation
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(closeButtonTappedWithAnimation))
        closeButton.addGestureRecognizer(tapGesture)
        
        // Store reference for animation
        self.modernCloseButton = closeButton
        
        // Bring to front to ensure it's above webviews
        view.bringSubviewToFront(closeButton)
    }
    
    private func addHeaderBorder() {
        // Create hairline grey border at bottom of header area
        let borderView = UIView()
        borderView.backgroundColor = UIColor.systemGray4
        borderView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(borderView)
        
        // Position border at bottom of header area (56pts from top = 28 + 28 for centered elements)
        NSLayoutConstraint.activate([
            borderView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 56),
            borderView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            borderView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale) // True hairline thickness
        ])
        
        // Bring to front but keep below logo and close button
        view.bringSubviewToFront(borderView)
    }
    
    private func addLogoToContainer(_ container: UIView) {
        // Logo is hidden - no logo will be displayed in the header
        passageLogger.debug("[WEBVIEW] Logo hidden - skipping logo creation")
    }
    
    private func addBackButtonToContainer(_ container: UIView) {
        // Create back button for placement in header container
        let backButton = UILabel()
        backButton.text = "←"
        backButton.font = UIFont.systemFont(ofSize: 26, weight: .light) // 32 * 0.8 = 25.6 ≈ 26
        backButton.textColor = UIColor.black
        backButton.textAlignment = .center
        backButton.backgroundColor = UIColor.clear
        backButton.isUserInteractionEnabled = true
        backButton.alpha = 0 // Initially hidden

        container.addSubview(backButton)
        backButton.translatesAutoresizingMaskIntoConstraints = false

        // Position in header container's safe area portion (left side, mirroring close button)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 4),
            backButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 48),
            backButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        // Add tap gesture with animation
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backButtonTappedWithAnimation))
        backButton.addGestureRecognizer(tapGesture)

        // Store reference for visibility management
        self.backButton = backButton
    }

    private func addCloseButtonToContainer(_ container: UIView) {
        // Create close button for placement in header container
        let closeButton = UILabel()
        closeButton.text = "×"
        closeButton.font = UIFont.systemFont(ofSize: 32, weight: .light)
        closeButton.textColor = UIColor.black
        closeButton.textAlignment = .center
        closeButton.backgroundColor = UIColor.clear
        closeButton.isUserInteractionEnabled = true

        container.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // Position in header container's safe area portion
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 48),
            closeButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        // Add tap gesture with animation
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(closeButtonTappedWithAnimation))
        closeButton.addGestureRecognizer(tapGesture)

        // Store reference for animation
        self.modernCloseButton = closeButton
    }
    
    private func addHeaderBorderToContainer(_ container: UIView) {
        // Create hairline grey border at bottom of header container
        let borderView = UIView()
        borderView.backgroundColor = UIColor.systemGray4
        borderView.translatesAutoresizingMaskIntoConstraints = false
        
        container.addSubview(borderView)
        
        // Position border at bottom of header container
        NSLayoutConstraint.activate([
            borderView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            borderView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale) // True hairline thickness
        ])
    }
    
    private func generateGlobalJavaScript() -> String {
        // Get global JavaScript from remote control manager
        guard let remoteControl = remoteControl else {
            passageLogger.debug("[WEBVIEW] No remote control available for global JavaScript")
            return "" // Return empty string if no remote control
        }
        
        let globalScript = remoteControl.getGlobalJavascript()
        passageLogger.info("[WEBVIEW] Global JavaScript retrieved: \(globalScript.isEmpty ? "EMPTY" : "\(globalScript.count) chars")")
        
        if !globalScript.isEmpty {
            // Log first 200 chars of global script for debugging
            let preview = String(globalScript.prefix(200))
            passageLogger.debug("[WEBVIEW] Global JavaScript preview: \(preview)...")
        }
        
        if globalScript.isEmpty {
            return "" // Return empty string if no global JS
        }
        
        // Wrap the global script with comprehensive error handling and context isolation
        return """
        (function() {
            'use strict';
            
            // Ensure we have a clean context
            if (typeof window === 'undefined') {
                console.warn('[Passage] Global JavaScript executed outside window context');
                return false;
            }
            
            // Create a safe execution environment for third-party libraries
            function createSafeExecutionContext() {
                // Patch WeakMap to handle invalid keys gracefully
                const OriginalWeakMap = window.WeakMap;
                
                function SafeWeakMap(iterable) {
                    const instance = new OriginalWeakMap(iterable);
                    // Use a separate Map to track primitive key wrappers
                    const primitiveKeyMap = new Map();
                    
                    const originalSet = instance.set.bind(instance);
                    const originalGet = instance.get.bind(instance);
                    const originalHas = instance.has.bind(instance);
                    const originalDelete = instance.delete.bind(instance);
                    
                    instance.set = function(key, value) {
                        if (key === null || key === undefined || (typeof key !== 'object' && typeof key !== 'function' && typeof key !== 'symbol')) {
                            console.warn('[Passage] WeakMap: Invalid key type, using fallback storage:', typeof key, key);
                            // Store primitive keys in a separate Map
                            primitiveKeyMap.set(key, value);
                            return instance;
                        }
                        return originalSet(key, value);
                    };
                    
                    instance.get = function(key) {
                        if (key === null || key === undefined || (typeof key !== 'object' && typeof key !== 'function' && typeof key !== 'symbol')) {
                            // Get from primitive key map
                            return primitiveKeyMap.get(key);
                        }
                        return originalGet(key);
                    };
                    
                    instance.has = function(key) {
                        if (key === null || key === undefined || (typeof key !== 'object' && typeof key !== 'function' && typeof key !== 'symbol')) {
                            // Check primitive key map
                            return primitiveKeyMap.has(key);
                        }
                        return originalHas(key);
                    };
                    
                    instance.delete = function(key) {
                        if (key === null || key === undefined || (typeof key !== 'object' && typeof key !== 'function' && typeof key !== 'symbol')) {
                            // Delete from primitive key map
                            return primitiveKeyMap.delete(key);
                        }
                        return originalDelete(key);
                    };
                    
                    return instance;
                }
                
                // Copy static methods
                Object.setPrototypeOf(SafeWeakMap, OriginalWeakMap);
                SafeWeakMap.prototype = OriginalWeakMap.prototype;
                
                return SafeWeakMap;
            }
            
            // Wait for DOM to be ready if needed
            function executeGlobalScript() {
                try {
                    // Create safe execution context
                    const SafeWeakMap = createSafeExecutionContext();
                    const originalWeakMap = window.WeakMap;
                    
                    // Temporarily replace WeakMap
                    window.WeakMap = SafeWeakMap;
                    
                    console.log('[Passage] Executing global script with WeakMap protection');
                    
                    // Execute the global script in isolated scope
                    (function() {
                        \(globalScript)
                    }).call(window);
                    
                    // Restore original WeakMap after a delay to allow library initialization
                    setTimeout(function() {
                        window.WeakMap = originalWeakMap;
                        console.log('[Passage] WeakMap protection removed, original WeakMap restored');
                    }, 1000);
                    
                    return true;
                } catch (error) {
                    console.error('[Passage] Error executing global JavaScript:', error);
                    console.error('[Passage] Error stack:', error.stack);
                    
                    // Restore original WeakMap on error
                    if (typeof originalWeakMap !== 'undefined') {
                        window.WeakMap = originalWeakMap;
                    }
                    return false;
                }
            }
            
            // Execute immediately if DOM is ready, otherwise wait
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', executeGlobalScript);
            } else {
                // Add a small delay to ensure window.passage is fully initialized
                setTimeout(executeGlobalScript, 100);
            }
        })();
        """
    }
    
    private func createPassageScript(for webViewType: String) -> String {
        if webViewType == PassageConstants.WebViewTypes.automation {
            // Full script for automation webview
            return """
            // Passage Automation WebView Script
            (function() {
              console.log('[Passage] Automation webview script starting...');
              
              // Prevent multiple initialization
              if (window.passage && window.passage.initialized) {
                console.log('[Passage] Already initialized, skipping');
                return;
              }
              
              // Initialize passage object for automation webview
              console.log('[Passage] Initializing window.passage for automation webview');
              window.passage = {
                initialized: true,
                webViewType: 'automation',
                
                // Core messaging functionality
                postMessage: function(data) {
                  console.log('[Passage] postMessage called with data:', data);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      console.log('[Passage] Sending message via webkit handler');
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'message',
                        data: data,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      console.log('[Passage] Message sent successfully');
                    } else {
                      console.warn('[Passage] Message handlers not available');
                      console.log('[Passage] window.webkit:', typeof window.webkit);
                      console.log('[Passage] window.webkit.messageHandlers:', typeof window.webkit?.messageHandlers);
                      console.log('[Passage] passageWebView handler:', typeof window.webkit?.messageHandlers?.passageWebView);
                    }
                  } catch (error) {
                    console.error('[Passage] Error posting message:', error);
                  }
                },
                
                
                // Navigation functionality
                navigate: function(url) {
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'navigate',
                        url: url,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                    } else {
                      console.warn('[Passage] Message handlers not available for navigation');
                    }
                  } catch (error) {
                    console.error('[Passage] Error navigating:', error);
                  }
                },
                
                // Modal control
                close: function() {
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'close',
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                    } else {
                      console.warn('[Passage] Message handlers not available for close');
                    }
                  } catch (error) {
                    console.error('[Passage] Error closing:', error);
                  }
                },
                
                // Title management
                setTitle: function(title) {
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'setTitle',
                        title: title,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                    } else {
                      console.warn('[Passage] Message handlers not available for setTitle');
                    }
                  } catch (error) {
                    console.error('[Passage] Error setting title:', error);
                  }
                },
                
                // Utility functions
                getWebViewType: function() {
                  return 'automation';
                },
                
                isAutomationWebView: function() {
                  return true;
                },
                
                isUIWebView: function() {
                  return false;
                },
                
                // Screenshot capture function
                captureScreenshot: function() {
                  console.log('[Passage] captureScreenshot called');
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'captureScreenshot',
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      console.log('[Passage] Screenshot capture request sent');
                    } else {
                      console.warn('[Passage] Message handlers not available for screenshot capture');
                    }
                  } catch (error) {
                    console.error('[Passage] Error capturing screenshot:', error);
                  }
                }
              };
              
              // Monitor client-side navigation events
              (function() {
                // Monitor History API
                const originalPushState = window.history.pushState;
                const originalReplaceState = window.history.replaceState;
                
                window.history.pushState = function() {
                  originalPushState.apply(window.history, arguments);
                  console.log('[Passage] pushState navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'pushState',
                    url: window.location.href,
                    webViewType: 'automation',
                    timestamp: Date.now()
                  });
                };
                
                window.history.replaceState = function() {
                  originalReplaceState.apply(window.history, arguments);
                  console.log('[Passage] replaceState navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'replaceState',
                    url: window.location.href,
                    webViewType: 'automation',
                    timestamp: Date.now()
                  });
                };
                
                // Monitor popstate (back/forward)
                window.addEventListener('popstate', function(event) {
                  console.log('[Passage] popstate navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'popstate',
                    url: window.location.href,
                    webViewType: 'automation',
                    timestamp: Date.now()
                  });
                });
                
                // Monitor hash changes
                window.addEventListener('hashchange', function(event) {
                  console.log('[Passage] hashchange navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'hashchange',
                    url: window.location.href,
                    oldURL: event.oldURL,
                    newURL: event.newURL,
                    webViewType: 'automation',
                    timestamp: Date.now()
                  });
                });
              })();
              
              console.log('[Passage] Automation webview script initialized successfully');
              console.log('[Passage] window.passage.initialized:', window.passage.initialized);
              console.log('[Passage] window.passage.webViewType:', window.passage.webViewType);
            })();
            """
        } else {
            // Full script for UI webview
            return """
            // Passage UI WebView Script - Full window.passage object
            (function() {
              // Prevent multiple initialization
              if (window.passage && window.passage.initialized) {
                console.log('[Passage] Already initialized, skipping');
                return;
              }
              
              // Initialize passage object for UI webview
              window.passage = {
                initialized: true,
                webViewType: 'ui',
                
                // Core messaging functionality
                postMessage: function(data) {
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'message',
                        data: data,
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                    } else {
                      console.warn('[Passage] Message handlers not available');
                    }
                  } catch (error) {
                    console.error('[Passage] Error posting message:', error);
                  }
                },
                
                // Navigation functionality
                navigate: function(url) {
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'navigate',
                        url: url,
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                    } else {
                      console.warn('[Passage] Message handlers not available for navigation');
                    }
                  } catch (error) {
                    console.error('[Passage] Error navigating:', error);
                  }
                },
                
                // Modal control
                close: function() {
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'close',
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                    } else {
                      console.warn('[Passage] Message handlers not available for close');
                    }
                  } catch (error) {
                    console.error('[Passage] Error closing:', error);
                  }
                },
                
                // Title management
                setTitle: function(title) {
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'setTitle',
                        title: title,
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                    } else {
                      console.warn('[Passage] Message handlers not available for setTitle');
                    }
                  } catch (error) {
                    console.error('[Passage] Error setting title:', error);
                  }
                },
                
                // Utility functions
                getWebViewType: function() {
                  return 'ui';
                },
                
                isAutomationWebView: function() {
                  return false;
                },
                
                isUIWebView: function() {
                  return true;
                },
                
                // Screenshot capture function
                captureScreenshot: function() {
                  console.log('[Passage] captureScreenshot called');
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'captureScreenshot',
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                      console.log('[Passage] Screenshot capture request sent');
                    } else {
                      console.warn('[Passage] Message handlers not available for screenshot capture');
                    }
                  } catch (error) {
                    console.error('[Passage] Error capturing screenshot:', error);
                  }
                }
              };
              
              // Monitor client-side navigation events (same as automation)
              (function() {
                // Monitor History API
                const originalPushState = window.history.pushState;
                const originalReplaceState = window.history.replaceState;
                
                window.history.pushState = function() {
                  originalPushState.apply(window.history, arguments);
                  console.log('[Passage] pushState navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'pushState',
                    url: window.location.href,
                    webViewType: 'ui',
                    timestamp: Date.now()
                  });
                };
                
                window.history.replaceState = function() {
                  originalReplaceState.apply(window.history, arguments);
                  console.log('[Passage] replaceState navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'replaceState',
                    url: window.location.href,
                    webViewType: 'ui',
                    timestamp: Date.now()
                  });
                };
                
                // Monitor popstate (back/forward)
                window.addEventListener('popstate', function(event) {
                  console.log('[Passage] popstate navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'popstate',
                    url: window.location.href,
                    webViewType: 'ui',
                    timestamp: Date.now()
                  });
                });
                
                // Monitor hash changes
                window.addEventListener('hashchange', function(event) {
                  console.log('[Passage] hashchange navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'hashchange',
                    url: window.location.href,
                    oldURL: event.oldURL,
                    newURL: event.newURL,
                    webViewType: 'ui',
                    timestamp: Date.now()
                  });
                });
              })();
              
              console.log('[Passage] UI webview script initialized with full window.passage object');
            })();
            """
        }
    }
    
    func loadURL(_ urlString: String) {
        passageLogger.info("[WEBVIEW] Loading URL: \(passageLogger.truncateUrl(urlString, maxLength: 100))")
        
        // In debug single-webview mode, ignore external loads that aren't the debug URL
        if let debugUrl = debugSingleWebViewUrl, !debugUrl.isEmpty, urlString != debugUrl {
            passageLogger.warn("[WEBVIEW DEBUG MODE] Ignoring external URL, forcing debug URL")
            return
        }

        currentURL = urlString
        
        // Validate URL
        guard let url = URL(string: urlString) else {
            passageLogger.error("[WEBVIEW] ❌ Invalid URL: \(urlString)")
            return
        }
        
        // Reset state for new session
        resetForNewSession()
        
        // Ensure webviews are set up before loading
        if uiWebView == nil || automationWebView == nil {
            passageLogger.warn("[WEBVIEW] WebViews not ready, storing URL to load later")
            initialURLToLoad = urlString
            return
        }
        
        // Load URL
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                passageLogger.error("[WEBVIEW] Self is nil in loadURL")
                return
            }
            
            guard let webView = self.uiWebView else {
                passageLogger.error("[WEBVIEW] ❌ UI WebView is nil")
                // Store URL to load when webview is ready
                self.initialURLToLoad = urlString
                return
            }
            
            var request = URLRequest(url: url)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = 30.0
            
            if webView.isLoading {
                passageLogger.debug("[WEBVIEW] Stopping current load")
                webView.stopLoading()
            }
            
            webView.load(request)
        }
    }
    
    // Reset state for a new session when reusing webviews
    private func resetForNewSession() {
        passageLogger.info("[WEBVIEW] Resetting state for new session")
        
        // Clear pending commands
        pendingUserActionCommand = nil
        
        // Clear screenshot state
        currentScreenshot = nil
        previousScreenshot = nil
        
        // Reset URL state variables to empty/initial values
        currentURL = ""
        initialURLToLoad = nil
        // Note: We don't reset 'url' property as it may be set externally for the next session
        
        // Cancel any timers
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
        
        // Ensure we're showing UI webview
        if !isShowingUIWebView {
            showUIWebView()
        }
        
        // Stop any loading in automation webview
        DispatchQueue.main.async { [weak self] in
            if let automationWebView = self?.automationWebView, automationWebView.isLoading {
                passageLogger.debug("[WEBVIEW] Stopping automation webview loading")
                automationWebView.stopLoading()
            }
        }
        
        passageLogger.debug("[WEBVIEW] URL state reset: currentURL='', initialURLToLoad=nil")
    }
    
    func loadURL(_ url: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let uiWebView = self.uiWebView else {
                passageLogger.warn("[WEBVIEW] Cannot load URL - UI WebView has been released")
                return
            }
            let request = URLRequest(url: url)
            uiWebView.load(request)
        }
    }
    
    func navigateTo(_ url: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // In debug single-webview mode, ignore navigations not matching debug URL
            if let debugUrl = self.debugSingleWebViewUrl, !debugUrl.isEmpty, url != debugUrl {
                passageLogger.debug("[DEBUG MODE] Ignoring navigateTo: \(passageLogger.truncateUrl(url, maxLength: 100)) while forcing: \(passageLogger.truncateUrl(debugUrl, maxLength: 100))")
                return
            }
            if let urlObj = URL(string: url) {
                let request = URLRequest(url: urlObj)
                // Use the currently visible webview
                if self.isShowingUIWebView {
                    if let uiWebView = self.uiWebView {
                        uiWebView.load(request)
                    } else {
                        passageLogger.warn("[WEBVIEW] Cannot navigateTo - UI WebView has been released")
                    }
                } else {
                    if let automationWebView = self.automationWebView {
                        automationWebView.load(request)
                    } else {
                        passageLogger.warn("[WEBVIEW] Cannot navigateTo - Automation WebView has been released")
                    }
                }
            }
        }
    }
    
    // Navigate in automation webview (for remote control)
    func navigateInAutomationWebView(_ url: String) {
        passageLogger.info("[WEBVIEW] ========== NAVIGATE IN AUTOMATION WEBVIEW ==========")
        passageLogger.info("[WEBVIEW] 🧭 navigateInAutomationWebView called with: \(passageLogger.truncateUrl(url, maxLength: 100))")
        passageLogger.info("[WEBVIEW] Thread: \(Thread.isMainThread ? "Main" : "Background")")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { 
                passageLogger.error("[WEBVIEW] ❌ Self is nil in navigateInAutomationWebView")
                return 
            }
            
            passageLogger.info("[WEBVIEW] Now on main thread, checking automation webview...")
            passageLogger.info("[WEBVIEW] Automation webview exists: \(self.automationWebView != nil)")
            
            // Ensure webviews are ready
            guard self.automationWebView != nil else {
                passageLogger.error("[WEBVIEW] ❌ Cannot navigate - automation webview is nil")
                passageLogger.error("[WEBVIEW] View loaded: \(self.isViewLoaded)")
                passageLogger.error("[WEBVIEW] View in window: \(self.view.window != nil)")
                
                // If view is loaded, try to setup webviews
                if self.isViewLoaded && self.view.window != nil {
                    passageLogger.info("[WEBVIEW] 🔧 Attempting to setup webviews before navigation")
                    self.setupWebViews()
                    
                    // Try again after setup
                    if self.automationWebView != nil {
                        passageLogger.info("[WEBVIEW] ✅ Webviews set up successfully, retrying navigation")
                        self.navigateInAutomationWebView(url)
                        return
                    } else {
                        passageLogger.error("[WEBVIEW] ❌ Failed to setup automation webview")
                    }
                } else {
                    passageLogger.error("[WEBVIEW] Cannot setup webviews - view not ready")
                }
                return
            }
            
            if let urlObj = URL(string: url) {
                passageLogger.info("[WEBVIEW] ✅ URL is valid, proceeding with navigation")
                passageLogger.info("[WEBVIEW] Automation webview current URL: \(self.automationWebView?.url?.absoluteString ?? "nil")")
                passageLogger.info("[WEBVIEW] Automation webview is loading: \(self.automationWebView?.isLoading ?? false)")
                
                // Store the intended URL before attempting navigation
                // This helps track what we tried to load even if navigation fails
                self.intendedAutomationURL = url
                passageLogger.info("[WEBVIEW] 📝 Stored intended automation URL: \(url)")
                
                // Just load the URL directly - let the webview handle any errors
                let request = URLRequest(url: urlObj)
                self.automationWebView?.load(request)
                
                passageLogger.info("[WEBVIEW] 🎯 AUTOMATION WEBVIEW LOAD REQUESTED!")
                passageLogger.info("[WEBVIEW] URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
                passageLogger.info("[WEBVIEW] This should trigger WKNavigationDelegate methods")
            } else {
                passageLogger.error("[WEBVIEW] ❌ Invalid URL provided: \(url)")
            }
        }
    }
    
    // Navigate in UI webview (for success/error URLs)
    func navigateInUIWebView(_ url: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            passageLogger.info("[WEBVIEW] Navigating UI webview to: \(passageLogger.truncateUrl(url, maxLength: 100))")
            
            if let urlObj = URL(string: url) {
                let request = URLRequest(url: urlObj)
                self.uiWebView?.load(request)
            }
        }
    }
    
    func goBack() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let targetWebView = self.isShowingUIWebView ? self.uiWebView : self.automationWebView
            if targetWebView?.canGoBack == true {
                targetWebView?.goBack()
            }
        }
    }
    
    func goForward() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let targetWebView = self.isShowingUIWebView ? self.uiWebView : self.automationWebView
            if targetWebView?.canGoForward == true {
                targetWebView?.goForward()
            }
        }
    }
    
    @objc private func closeModal() {
        passageLogger.debug("Close button tapped, dismissing modal")
        
        // Reset close button press counter when modal closes
        closeButtonPressCount = 0
        
        // Reset URL state immediately when modal closes
        resetURLState()
        
        dismiss(animated: true) {
            // Only call delegate method to avoid duplicate handleClose calls
            // The delegate (PassageSDK) will handle the close logic
            self.delegate?.webViewModalDidClose()
        }
    }
    
    
    @objc private func closeButtonTappedWithAnimation() {
        // Animate button press
        guard let button = modernCloseButton else { return }

        UIView.animate(withDuration: 0.1, animations: {
            button.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                button.transform = CGAffineTransform.identity
            }) { _ in
                self.closeButtonTapped()
            }
        }
    }

    @objc private func backButtonTappedWithAnimation() {
        // Animate button press
        guard let button = backButton else { return }

        UIView.animate(withDuration: 0.1, animations: {
            button.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.1, animations: {
                button.transform = CGAffineTransform.identity
            }) { _ in
                self.backButtonTapped()
            }
        }
    }

    @objc private func backButtonTapped() {
        passageLogger.info("[WEBVIEW] Back button tapped")

        // Check if back navigation is disabled
        if isBackNavigationDisabled {
            passageLogger.debug("[WEBVIEW] Back navigation is disabled - ignoring tap")
            return
        }

        // Only navigate back in automation webview if it can go back
        guard let automationWebView = automationWebView, automationWebView.canGoBack else {
            passageLogger.debug("[WEBVIEW] Cannot go back - no history")
            return
        }

        // Set flag to indicate this navigation is from back button
        isNavigatingFromBackButton = true
        passageLogger.debug("[WEBVIEW] Set isNavigatingFromBackButton flag - backend tracking will be skipped")

        // Navigate back
        DispatchQueue.main.async { [weak self] in
            automationWebView.goBack()
            passageLogger.debug("[WEBVIEW] Automation webview navigating back")

            // Update back button visibility after navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.updateBackButtonVisibility()
            }
        }
    }

    private func updateBackButtonVisibility() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let backButton = self.backButton else { return }

            // Show back button only if:
            // 1. Automation webview is currently visible (not UI webview)
            // 2. Automation webview has navigation history
            // 3. Back navigation is not disabled
            let isAutomationVisible = !self.isShowingUIWebView
            let hasHistory = self.automationWebView?.canGoBack ?? false
            let isEnabled = !self.isBackNavigationDisabled
            let shouldShow = isAutomationVisible && hasHistory && isEnabled
            let targetAlpha: CGFloat = shouldShow ? 1.0 : 0.0

            // Only animate if visibility is actually changing
            if backButton.alpha != targetAlpha {
                UIView.animate(withDuration: 0.2) {
                    backButton.alpha = targetAlpha
                }
                passageLogger.debug("[WEBVIEW] Back button visibility updated: \(shouldShow ? "visible" : "hidden") (automation visible: \(isAutomationVisible), has history: \(hasHistory), enabled: \(isEnabled))")
            }
        }
    }

    private func clearAutomationNavigationHistory() {
        passageLogger.info("[WEBVIEW] Clearing automation webview navigation history")

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let automationWebView = self.automationWebView else { return }

            // Disable back navigation until next user-initiated navigation
            self.isBackNavigationDisabled = true
            passageLogger.debug("[WEBVIEW] Back navigation disabled")

            // Hide back button immediately
            self.updateBackButtonVisibility()

            // Clear back/forward history by loading about:blank and then the actual URL
            // The actual URL will be loaded by navigateInAutomationWebView after this
            if automationWebView.canGoBack {
                automationWebView.loadHTMLString("", baseURL: nil)
                passageLogger.debug("[WEBVIEW] Cleared automation webview history")
            }
        }
    }
    
    @objc private func closeButtonTapped() {
        // Increment close button press counter
        closeButtonPressCount += 1
        passageLogger.info("[WEBVIEW] Close button tapped (press #\(closeButtonPressCount))")
        
        // If this is the second press, close immediately
        if closeButtonPressCount >= 2 {
            passageLogger.info("[WEBVIEW] Second close button press - closing modal immediately")
            closeModal()
            return
        }
        
        // First press - show confirmation dialog
        passageLogger.info("[WEBVIEW] First close button press - requesting close confirmation")
        
        // Remember current webview state before showing close confirmation
        wasShowingAutomationBeforeClose = !isShowingUIWebView
        
        // First, ensure UI webview is shown if automation webview is active
        if !isShowingUIWebView {
            passageLogger.info("[WEBVIEW] Switching to UI webview before showing close confirmation")
            showUIWebView()
        }
        
        // Send close confirmation request to NextJS app
        if let uiWebView = uiWebView {
            passageLogger.info("[WEBVIEW] Sending close confirmation request to UI webview")
            
            // Call the global function directly or fallback to postMessage
            let script = """
            try {
                if (typeof window.showCloseConfirmation === 'function') {
                    window.showCloseConfirmation();
                } else if (window.passage && window.passage.postMessage) {
                    window.passage.postMessage({type: 'CLOSE_CONFIRMATION_REQUEST'});
                } else {
                    console.log('No close confirmation handler available');
                }
            } catch (error) {
                console.error('Error calling close confirmation:', error);
            }
            """
            
            uiWebView.evaluateJavaScript(script, completionHandler: { result, error in
                if let error = error {
                    passageLogger.error("[WEBVIEW] Failed to send close confirmation request: \(error)")
                    // Fallback to direct close
                    DispatchQueue.main.async {
                        self.closeModal()
                    }
                } else {
                    passageLogger.debug("[WEBVIEW] Close confirmation request sent successfully")
                }
            })
        } else {
            passageLogger.warn("[WEBVIEW] UI webview not available, falling back to direct close")
            closeModal()
        }
    }
    
    func injectJavaScript(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
        // Inject into the currently visible webview
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(nil, NSError(domain: "WebViewModal", code: 0, userInfo: [NSLocalizedDescriptionKey: "WebView deallocated"]))
                return
            }
            let targetWebView = self.isShowingUIWebView ? self.uiWebView : self.automationWebView
            targetWebView?.evaluateJavaScript(script, completionHandler: completion)
        }
    }
    
    // Inject JavaScript in automation webview (for remote control)
    func injectJavaScriptInAutomationWebView(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
        injectJavaScriptInAutomationWebView(script, completion: completion, retryCount: 0)
    }
    
    private func injectJavaScriptInAutomationWebView(_ script: String, completion: @escaping (Any?, Error?) -> Void, retryCount: Int) {
        let maxRetries = 10 // Maximum 5 seconds of retries
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let automationWebView = self.automationWebView else {
                completion(nil, NSError(domain: "WebViewModal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Automation WebView not available"]))
                return
            }
            
            // Check if the webview is still loading
            if automationWebView.isLoading {
                if retryCount < maxRetries {
                    passageLogger.debug("[WEBVIEW] Automation webview is still loading (attempt \(retryCount + 1)/\(maxRetries)), waiting before script injection")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.injectJavaScriptInAutomationWebView(script, completion: completion, retryCount: retryCount + 1)
                    }
                } else {
                    passageLogger.error("[WEBVIEW] Automation webview still loading after \(maxRetries) retries, giving up")
                    completion(nil, NSError(domain: "WebViewModal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Automation WebView still loading after retries"]))
                }
                return
            }
            
            // First check if window.passage is available before injecting the script
            automationWebView.evaluateJavaScript("typeof window.passage !== 'undefined' && window.passage.initialized === true") { result, error in
                if let error = error {
                    passageLogger.error("[WEBVIEW] Error checking window.passage availability: \(error)")
                    if retryCount < maxRetries {
                        passageLogger.debug("[WEBVIEW] Retrying window.passage check (attempt \(retryCount + 1)/\(maxRetries))")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            self.injectJavaScriptInAutomationWebView(script, completion: completion, retryCount: retryCount + 1)
                        }
                    } else {
                        completion(nil, error)
                    }
                    return
                }
                
                if let isPassageReady = result as? Bool, isPassageReady {
                    // window.passage is ready, inject the script
                    passageLogger.debug("[WEBVIEW] window.passage is ready, injecting script")
                    
                    // First, test if window.passage.postMessage works
                    automationWebView.evaluateJavaScript("window.passage.postMessage('test-message-from-swift')") { testResult, testError in
                        if let testError = testError {
                            passageLogger.error("[WEBVIEW] Test postMessage failed: \(testError)")
                        } else {
                            passageLogger.debug("[WEBVIEW] Test postMessage sent successfully")
                        }
                        
                        // Now inject the actual script
                        automationWebView.evaluateJavaScript(script, completionHandler: completion)
                    }
                } else {
                    // window.passage is not ready, try to re-inject it first
                    if retryCount < maxRetries {
                        passageLogger.debug("[WEBVIEW] window.passage not ready (attempt \(retryCount + 1)/\(maxRetries)), re-injecting window.passage script")
                        passageLogger.debug("[WEBVIEW] window.passage check result: \(String(describing: result))")
                        
                        // Re-inject the window.passage script
                        let passageScript = self.createPassageScript(for: PassageConstants.WebViewTypes.automation)
                        automationWebView.evaluateJavaScript(passageScript) { passageResult, passageError in
                            if let passageError = passageError {
                                passageLogger.error("[WEBVIEW] Error re-injecting window.passage script: \(passageError)")
                            } else {
                                passageLogger.debug("[WEBVIEW] Re-injected window.passage script successfully")
                            }
                            
                            // Wait a bit and try the original script injection again
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.injectJavaScriptInAutomationWebView(script, completion: completion, retryCount: retryCount + 1)
                            }
                        }
                    } else {
                        passageLogger.error("[WEBVIEW] window.passage not ready after \(maxRetries) retries, injecting anyway")
                        // Try to inject anyway as a last resort
                        automationWebView.evaluateJavaScript(script, completionHandler: completion)
                    }
                }
            }
        }
    }
    
    func updateTitle(_ title: String) {
        // Keep title empty regardless of what's requested
        navigationItem.title = ""
    }
    
    // Public methods for showing/hiding webviews with animations
    func showUIWebView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Check if WebViews are still available (not released)
            guard let uiWebView = self.uiWebView, let automationWebView = self.automationWebView else {
                passageLogger.warn("[WEBVIEW] Cannot show UI WebView - WebViews have been released")
                return
            }

            // Cancel any ongoing animation
            if self.isAnimating {
                uiWebView.layer.removeAllAnimations()
                automationWebView.layer.removeAllAnimations()
                self.isAnimating = false
            }

            // If already showing UI webview, ensure visual state is correct
            if self.isShowingUIWebView {
                self.view.bringSubviewToFront(uiWebView)
                uiWebView.alpha = 1
                automationWebView.alpha = 0
                // Ensure back button is hidden when UI webview is already showing
                self.updateBackButtonVisibility()
                return
            }

            passageLogger.debug("[WEBVIEW] Switching to UI webview")
            self.isAnimating = true
            self.view.bringSubviewToFront(uiWebView)
            
            // Ensure header container stays on top BEFORE animation
            if let headerContainer = self.headerContainer {
                self.view.bringSubviewToFront(headerContainer)
            }
            
            // Prevent automation webview from becoming first responder when UI is visible
            automationWebView.shouldPreventFirstResponder = true
            uiWebView.shouldPreventFirstResponder = false

            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
                uiWebView.alpha = 1
                automationWebView.alpha = 0
            }, completion: { _ in
                self.isAnimating = false
                self.isShowingUIWebView = true
                self.onWebviewChange?("ui")

                // Hide back button when UI webview is visible
                self.updateBackButtonVisibility()

                // Any keyboard that might be showing will be automatically dismissed by keyboard notifications
            })
        }
    }
    
    func showAutomationWebView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // In debug single-webview mode, automation webview is not created
            if self.debugSingleWebViewUrl != nil {
                passageLogger.debug("[DEBUG MODE] Ignoring showAutomationWebView (debug mode)")
                return
            }

            // Check if WebViews are still available (not released)
            if self.uiWebView == nil || self.automationWebView == nil {
                passageLogger.warn("[WEBVIEW] WebViews not available - attempting to setup")
                
                // If view is loaded, try to setup webviews
                if self.isViewLoaded && self.view.window != nil {
                    passageLogger.info("[WEBVIEW] View is loaded, setting up webviews")
                    self.setupWebViews()
                    
                    // Check again after setup
                    if self.uiWebView == nil || self.automationWebView == nil {
                        passageLogger.error("[WEBVIEW] Failed to setup webviews")
                        return
                    }
                } else {
                    passageLogger.error("[WEBVIEW] Cannot setup webviews - view not ready")
                    return
                }
            }

            guard let uiWebView = self.uiWebView, let automationWebView = self.automationWebView else {
                passageLogger.error("[WEBVIEW] Cannot show Automation WebView - WebViews are nil")
                return
            }

            // Cancel any ongoing animation
            if self.isAnimating {
                uiWebView.layer.removeAllAnimations()
                automationWebView.layer.removeAllAnimations()
                self.isAnimating = false
            }

            // If already showing automation webview, ensure visual state is correct
            if !self.isShowingUIWebView {
                self.view.bringSubviewToFront(automationWebView)
                automationWebView.alpha = 1
                uiWebView.alpha = 0
                // Update back button visibility when automation webview is already showing
                self.updateBackButtonVisibility()
                return
            }

            passageLogger.debug("[WEBVIEW] Switching to automation webview")
            self.isAnimating = true
            self.view.bringSubviewToFront(automationWebView)
            
            // Ensure header container stays on top BEFORE animation
            if let headerContainer = self.headerContainer {
                self.view.bringSubviewToFront(headerContainer)
            }
            
            // Allow automation webview to become first responder when it's visible
            automationWebView.shouldPreventFirstResponder = false
            uiWebView.shouldPreventFirstResponder = true

            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
                automationWebView.alpha = 1
                uiWebView.alpha = 0
            }, completion: { _ in
                self.isAnimating = false
                self.isShowingUIWebView = false
                self.onWebviewChange?("automation")

                // Update back button visibility when automation webview becomes visible
                self.updateBackButtonVisibility()
            })
        }
    }
    
    // Loading indicator methods
    func showLoadingIndicator() {
        showUIWebView()
    }
    
    func hideLoadingIndicator() {
        showUIWebView()
    }
    
    // Better named methods
    func showAutomationWebViewForRemoteControl() {
        showAutomationWebView()
    }
    
    func showUIWebViewForUserInteraction() {
        showUIWebView()
    }
    
    // Get current webview type
    func getCurrentWebViewType() -> String {
        return isShowingUIWebView ? PassageConstants.WebViewTypes.ui : PassageConstants.WebViewTypes.automation
    }
    
    // Release WebView instances to free JavaScriptCore memory
    func releaseWebViews() {
        passageLogger.info("[WEBVIEW] 🗑️ Releasing WebView instances to free JavaScriptCore memory")
        passageLogger.info("[WEBVIEW] View controller instance: \(String(format: "%p", unsafeBitCast(self, to: Int.self)))")
        
        // If we're already on the main thread, execute synchronously
        if Thread.isMainThread {
            performWebViewRelease()
        } else {
            // If not on main thread, execute synchronously on main thread
            DispatchQueue.main.sync { [weak self] in
                self?.performWebViewRelease()
            }
        }
    }
    
    private func performWebViewRelease() {
        // Stop any ongoing loading first
        if let uiWebView = self.uiWebView {
            if uiWebView.isLoading {
                uiWebView.stopLoading()
                passageLogger.debug("[WEBVIEW] Stopped loading on UI WebView")
            }
        }

        if let automationWebView = self.automationWebView {
            if automationWebView.isLoading {
                automationWebView.stopLoading()
                passageLogger.debug("[WEBVIEW] Stopped loading on automation WebView")
            }
        }

        // Force unload content to terminate JavaScript execution
        // This is the key step to free the 512MB JavaScriptCore allocation
        if let uiWebView = self.uiWebView {
            uiWebView.loadHTMLString("", baseURL: nil)
            passageLogger.debug("[WEBVIEW] Force unloaded UI WebView content")
        }

        if let automationWebView = self.automationWebView {
            automationWebView.loadHTMLString("", baseURL: nil)
            passageLogger.debug("[WEBVIEW] Force unloaded automation WebView content")
        }

        // Remove from view hierarchy
        self.uiWebView?.removeFromSuperview()
        self.automationWebView?.removeFromSuperview()
        passageLogger.debug("[WEBVIEW] WebViews removed from view hierarchy")

        // Remove KVO observers before clearing references
        self.uiWebView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        self.automationWebView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        
        // Clear navigation delegates to break retain cycles
        self.uiWebView?.navigationDelegate = nil
        self.uiWebView?.uiDelegate = nil
        self.automationWebView?.navigationDelegate = nil
        self.automationWebView?.uiDelegate = nil

        // Clear message handlers
        self.uiWebView?.configuration.userContentController.removeAllUserScripts()
        self.uiWebView?.configuration.userContentController.removeAllScriptMessageHandlers()
        self.automationWebView?.configuration.userContentController.removeAllUserScripts()
        self.automationWebView?.configuration.userContentController.removeAllScriptMessageHandlers()

        // Finally, release the WebView instances
        // This should terminate the WebContent processes
        self.uiWebView = nil
        self.automationWebView = nil
        passageLogger.debug("[WEBVIEW] WebView references set to nil")

        // Clear related state
        self.currentScreenshot = nil
        self.previousScreenshot = nil
        self.pendingUserActionCommand = nil

        // Cancel any pending timers
        self.navigationTimeoutTimer?.invalidate()
        self.navigationTimeoutTimer = nil

        passageLogger.info("[WEBVIEW] ✅ WebView instances fully released - JavaScriptCore memory should be freed")
    }

    // Check if WebViews are still active (for debugging memory issues)
    func hasActiveWebViews() -> Bool {
        return uiWebView != nil || automationWebView != nil
    }

    func areWebViewsReady() -> Bool {
        passageLogger.debug("[WEBVIEW] Checking if WebViews are ready for script injection")

        // Check if both WebViews exist and are properly loaded
        guard let uiWebView = uiWebView, let automationWebView = automationWebView else {
            passageLogger.debug("[WEBVIEW] ❌ WebViews don't exist: uiWebView=\(uiWebView != nil), automationWebView=\(automationWebView != nil)")
            
            // If webviews don't exist but view is loaded, try to set them up
            if isViewLoaded && view.window != nil {
                passageLogger.info("[WEBVIEW] View is loaded but webviews are nil - attempting to setup webviews")
                setupWebViews()
                
                // Check again after setup
                if let _ = self.uiWebView, let _ = self.automationWebView {
                    passageLogger.info("[WEBVIEW] WebViews successfully created during ready check")
                    return areWebViewsReady() // Recursive call to do full checks
                }
            }
            
            return false
        }

        // Check if they're in the view hierarchy
        guard uiWebView.superview != nil && automationWebView.superview != nil else {
            passageLogger.debug("[WEBVIEW] ❌ WebViews not in view hierarchy: uiWebView.superview=\(uiWebView.superview != nil), automationWebView.superview=\(automationWebView.superview != nil)")
            return false
        }

        // MODIFIED: Check if automation WebView has a URL OR if it has been attempted to load
        // Even if navigation failed, we should allow script injection if a load was attempted
        let hasUrl = automationWebView.url != nil
        let hasIntendedUrl = intendedAutomationURL != nil
        
        passageLogger.debug("[WEBVIEW] Automation WebView URL check:")
        passageLogger.debug("[WEBVIEW]   - Current URL: \(automationWebView.url?.absoluteString ?? "nil")")
        passageLogger.debug("[WEBVIEW]   - Intended URL: \(intendedAutomationURL ?? "nil")")
        passageLogger.debug("[WEBVIEW]   - Has URL: \(hasUrl)")
        passageLogger.debug("[WEBVIEW]   - Has intended URL: \(hasIntendedUrl)")
        
        guard hasUrl || hasIntendedUrl else {
            passageLogger.debug("[WEBVIEW] ❌ Automation WebView has no URL and no intended URL")
            return false
        }

        passageLogger.debug("[WEBVIEW] ✅ WebViews are ready for script injection (URL or intended URL exists)")
        return true
    }

    // Reset URL state to empty/initial values
    func resetURLState() {
        passageLogger.info("[WEBVIEW] Resetting URL state to empty/initial values")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Reset all URL-related state variables
            self.url = ""
            self.currentURL = ""
            self.initialURLToLoad = nil
            
            passageLogger.debug("[WEBVIEW] URL state reset complete: url='', currentURL='', initialURLToLoad=nil")
        }
    }
    
    // Clear webview state (navigation history only, preserves cookies/localStorage/sessionStorage)
    func clearWebViewState() {
        passageLogger.info("[WEBVIEW] Clearing webview navigation state (preserving cookies, localStorage, sessionStorage)")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Clear navigation history only - preserve cookies, localStorage, sessionStorage
            if let uiWebView = self.uiWebView {
                passageLogger.debug("[WEBVIEW] Clearing UI webview navigation state")
                
                // Stop any loading
                if uiWebView.isLoading {
                    uiWebView.stopLoading()
                }
                
                // Clear back/forward history by loading about:blank
                uiWebView.loadHTMLString("", baseURL: nil)
            }
            
            if let automationWebView = self.automationWebView {
                passageLogger.debug("[WEBVIEW] Clearing automation webview navigation state")
                
                // Stop any loading
                if automationWebView.isLoading {
                    automationWebView.stopLoading()
                }
                
                // Clear back/forward history by loading about:blank
                automationWebView.loadHTMLString("", baseURL: nil)
            }
            
            // Reset webview state variables
            self.resetForNewSession()
            
            // Additionally reset the main URL property to empty for next session
            self.url = ""
            
            passageLogger.info("[WEBVIEW] Navigation state cleared successfully (cookies/localStorage/sessionStorage preserved)")
        }
    }
    
    // Clear all webview data including cookies, localStorage, sessionStorage (manual method)
    func clearWebViewData() {
        clearWebViewData(completion: nil)
    }
    
    // Clear all webview data including cookies, localStorage, sessionStorage with completion handler
    func clearWebViewData(completion: (() -> Void)?) {
        passageLogger.info("[WEBVIEW] Clearing ALL webview data including cookies, localStorage, sessionStorage")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { 
                completion?()
                return 
            }
            
            let group = DispatchGroup()
            
            // Clear all website data for both webviews
            if let uiWebView = self.uiWebView {
                passageLogger.debug("[WEBVIEW] Clearing ALL UI webview data")
                
                // Stop any loading
                if uiWebView.isLoading {
                    uiWebView.stopLoading()
                }
                
                // Clear back/forward history by loading about:blank
                uiWebView.loadHTMLString("", baseURL: nil)
                
                // Clear ALL website data for this webview
                group.enter()
                let dataStore = uiWebView.configuration.websiteDataStore
                let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
                    passageLogger.debug("[WEBVIEW] ALL UI webview data cleared (cookies, localStorage, sessionStorage)")
                    group.leave()
                }
            }
            
            if let automationWebView = self.automationWebView {
                passageLogger.debug("[WEBVIEW] Clearing ALL automation webview data")
                
                // Stop any loading
                if automationWebView.isLoading {
                    automationWebView.stopLoading()
                }
                
                // Clear back/forward history by loading about:blank
                automationWebView.loadHTMLString("", baseURL: nil)
                
                // Clear ALL website data for this webview
                group.enter()
                let dataStore = automationWebView.configuration.websiteDataStore
                let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
                    passageLogger.debug("[WEBVIEW] ALL automation webview data cleared (cookies, localStorage, sessionStorage)")
                    group.leave()
                }
            }
            
            // Wait for all clearing operations to complete
            group.notify(queue: .main) {
                // Reset webview state variables
                self.resetForNewSession()
                
                // Additionally reset the main URL property to empty for next session
                self.url = ""
                
                passageLogger.info("[WEBVIEW] ALL webview data cleared successfully")
                completion?()
            }
        }
    }
    
    // MARK: - Screenshot Support (matching React Native implementation)
    
    // Structure to hold optimized image data with base64 string
    private struct OptimizedImageData {
        let data: Data
        let base64String: String
        let format: String
        let originalSize: CGSize
        let optimizedSize: CGSize
        let compressionQuality: Double
    }
    
    private func setupScreenshotAccessors() {
        passageLogger.info("[WEBVIEW] ========== SETTING UP SCREENSHOT ACCESSORS ==========")
        
        guard let remoteControl = remoteControl else {
            passageLogger.error("[WEBVIEW] ❌ No remote control available for screenshot setup")
            return
        }
        
        passageLogger.info("[WEBVIEW] ✅ Remote control available, configuring screenshot accessors")
        
        // Set screenshot accessors (matching React Native implementation)
        remoteControl.setScreenshotAccessors((
            getCurrentScreenshot: { [weak self] in
                let screenshot = self?.currentScreenshot
                passageLogger.debug("[WEBVIEW ACCESSOR] getCurrentScreenshot called, returning: \(screenshot != nil ? "\(screenshot!.count) chars" : "nil")")
                return screenshot
            },
            getPreviousScreenshot: { [weak self] in
                let screenshot = self?.previousScreenshot
                passageLogger.debug("[WEBVIEW ACCESSOR] getPreviousScreenshot called, returning: \(screenshot != nil ? "\(screenshot!.count) chars" : "nil")")
                return screenshot
            }
        ))
        
        // Set capture image function - chooses between webview-only or whole UI based on flags
        remoteControl.setCaptureImageFunction({ [weak self] in
            passageLogger.debug("[WEBVIEW ACCESSOR] captureImageFunction called")
            
            guard let self = self, let remoteControl = self.remoteControl else {
                return nil
            }
            
            // Check record flag first - if true, capture whole UI
            if remoteControl.getRecordFlag() {
                passageLogger.debug("[WEBVIEW ACCESSOR] Record flag is true - capturing whole UI")
                return await self.captureWholeUIScreenshot()
            }
            // Otherwise, check captureScreenshot flag for webview-only capture
            else if remoteControl.getCaptureScreenshotFlag() {
                passageLogger.debug("[WEBVIEW ACCESSOR] CaptureScreenshot flag is true - capturing automation webview only")
                return await self.captureScreenshot()
            }
            else {
                passageLogger.debug("[WEBVIEW ACCESSOR] No screenshot flags enabled")
                return nil
            }
        })
        
        passageLogger.info("[WEBVIEW] ✅ Screenshot accessors configured successfully")
    }
    
    /// Apply image optimization based on JWT parameters
    private func applyImageOptimization(to image: UIImage) -> OptimizedImageData? {
        guard let remoteControl = remoteControl else {
            passageLogger.error("[IMAGE OPTIMIZATION] No remote control available")
            return nil
        }
        
        // Get image optimization parameters from configuration (not JWT)
        let imageOptParams = remoteControl.getImageOptimizationParameters()
        
        // Default values if not specified in configuration
        let quality = (imageOptParams?["quality"] as? Double) ?? 0.6
        let maxWidth = (imageOptParams?["maxWidth"] as? Double) ?? 960.0
        let maxHeight = (imageOptParams?["maxHeight"] as? Double) ?? 540.0
        let format = (imageOptParams?["format"] as? String) ?? "jpeg"
        
        let originalSize = image.size
        
        passageLogger.info("[IMAGE OPTIMIZATION] ========== APPLYING IMAGE OPTIMIZATION ==========")
        passageLogger.info("[IMAGE OPTIMIZATION] Source: Configuration (not JWT)")
        passageLogger.info("[IMAGE OPTIMIZATION] Config available: \(imageOptParams != nil)")
        passageLogger.info("[IMAGE OPTIMIZATION] Original size: \(originalSize)")
        passageLogger.info("[IMAGE OPTIMIZATION] Max dimensions: \(maxWidth)x\(maxHeight)")
        passageLogger.info("[IMAGE OPTIMIZATION] Quality: \(quality)")
        passageLogger.info("[IMAGE OPTIMIZATION] Format: \(format)")
        
        // Calculate new size maintaining aspect ratio
        let aspectRatio = originalSize.width / originalSize.height
        var newWidth = originalSize.width
        var newHeight = originalSize.height
        
        // Resize if image is larger than max dimensions
        if originalSize.width > maxWidth || originalSize.height > maxHeight {
            if aspectRatio > 1 {
                // Landscape: width is the limiting factor
                newWidth = min(originalSize.width, maxWidth)
                newHeight = newWidth / aspectRatio
            } else {
                // Portrait: height is the limiting factor
                newHeight = min(originalSize.height, maxHeight)
                newWidth = newHeight * aspectRatio
            }
        }
        
        let newSize = CGSize(width: newWidth, height: newHeight)
        passageLogger.info("[IMAGE OPTIMIZATION] Optimized size: \(newSize)")
        
        // Resize image if needed
        let resizedImage: UIImage
        if newSize != originalSize {
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
            UIGraphicsEndImageContext()
            passageLogger.info("[IMAGE OPTIMIZATION] ✅ Image resized from \(originalSize) to \(newSize)")
        } else {
            resizedImage = image
            passageLogger.info("[IMAGE OPTIMIZATION] ✅ No resizing needed")
        }
        
        // Convert to appropriate format with compression
        let imageData: Data?
        let mimeType: String
        
        if format.lowercased() == "jpeg" || format.lowercased() == "jpg" {
            imageData = resizedImage.jpegData(compressionQuality: quality)
            mimeType = "data:image/jpeg;base64,"
            passageLogger.info("[IMAGE OPTIMIZATION] ✅ Converted to JPEG with quality \(quality)")
        } else {
            imageData = resizedImage.pngData()
            mimeType = "data:image/png;base64,"
            passageLogger.info("[IMAGE OPTIMIZATION] ✅ Converted to PNG (quality parameter ignored for PNG)")
        }
        
        guard let data = imageData else {
            passageLogger.error("[IMAGE OPTIMIZATION] ❌ Failed to convert image to \(format)")
            return nil
        }
        
        let base64String = mimeType + data.base64EncodedString()
        
        let optimizedData = OptimizedImageData(
            data: data,
            base64String: base64String,
            format: format,
            originalSize: originalSize,
            optimizedSize: newSize,
            compressionQuality: quality
        )
        
        passageLogger.info("[IMAGE OPTIMIZATION] ✅ Optimization complete:")
        passageLogger.info("[IMAGE OPTIMIZATION]   Original: \(Int(originalSize.width))x\(Int(originalSize.height))")
        passageLogger.info("[IMAGE OPTIMIZATION]   Optimized: \(Int(newSize.width))x\(Int(newSize.height))")
        passageLogger.info("[IMAGE OPTIMIZATION]   Data size: \(data.count) bytes")
        passageLogger.info("[IMAGE OPTIMIZATION]   Base64 length: \(base64String.count) chars")
        
        return optimizedData
    }
    
    private func captureScreenshot() async -> String? {
        passageLogger.info("[WEBVIEW SCREENSHOT] ========== CAPTURING SCREENSHOT ==========")
        
        // Only capture screenshot if captureScreenshot flag is true (webview-only capture)
        guard let remoteControl = remoteControl else {
            passageLogger.error("[WEBVIEW SCREENSHOT] ❌ No remote control available")
            return nil
        }
        
        let captureScreenshotFlag = remoteControl.getCaptureScreenshotFlag()
        passageLogger.info("[WEBVIEW SCREENSHOT] Capture screenshot flag: \(captureScreenshotFlag)")
        
        guard captureScreenshotFlag else {
            passageLogger.warn("[WEBVIEW SCREENSHOT] ⚠️ Screenshot capture skipped - captureScreenshot flag is false")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    passageLogger.error("[WEBVIEW SCREENSHOT] ❌ Self is nil")
                    continuation.resume(returning: nil)
                    return
                }
                
                // Always prefer automation webview for screenshot capture (where the actual content is)
                guard let webView = self.automationWebView else {
                    passageLogger.error("[WEBVIEW SCREENSHOT] ❌ Automation webview not available for screenshot capture")
                    passageLogger.error("[WEBVIEW SCREENSHOT] automationWebView: \(self.automationWebView != nil)")
                    passageLogger.error("[WEBVIEW SCREENSHOT] uiWebView: \(self.uiWebView != nil)")
                    continuation.resume(returning: nil)
                    return
                }
                
                passageLogger.info("[WEBVIEW SCREENSHOT] 📸 Capturing screenshot of automation webview")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView bounds: \(webView.bounds)")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView isHidden: \(webView.isHidden)")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView alpha: \(webView.alpha)")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView URL: \(webView.url?.absoluteString ?? "nil")")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView isLoading: \(webView.isLoading)")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView estimatedProgress: \(webView.estimatedProgress)")
                passageLogger.debug("[WEBVIEW SCREENSHOT] WebView hasOnlySecureContent: \(webView.hasOnlySecureContent)")
                
                // WKWebView.takeSnapshot requires webview to be visible to capture content
                // Instead of changing alpha, temporarily show it behind the UI webview (invisible to user)
                let originalAlpha = webView.alpha
                let needsVisibility = originalAlpha == 0
                
                if needsVisibility {
                    passageLogger.debug("[WEBVIEW SCREENSHOT] Temporarily showing webview behind UI webview for snapshot")
                    // Make it visible but keep it behind the UI webview so user doesn't see it
                    webView.alpha = 1.0
                    if let uiWebView = self.uiWebView {
                        self.view.sendSubviewToBack(webView)
                        self.view.bringSubviewToFront(uiWebView)
                        passageLogger.debug("[WEBVIEW SCREENSHOT] Automation webview moved behind UI webview")
                    }
                }
                
                // Configure snapshot with proper bounds and screen update handling
                let config = WKSnapshotConfiguration()
                config.rect = webView.bounds
                // Ensure we capture after screen updates complete
                config.afterScreenUpdates = true
                
                passageLogger.debug("[WEBVIEW SCREENSHOT] Using WKWebView.takeSnapshot with config - rect: \(config.rect), afterScreenUpdates: \(config.afterScreenUpdates)")
                
                // Minimal delay to ensure content is rendered, then capture immediately
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    // Use WKWebView.takeSnapshot - specifically designed for WKWebView content
                    webView.takeSnapshot(with: config) { [weak self] image, error in
                        // Restore original visibility state immediately
                        if needsVisibility {
                            webView.alpha = originalAlpha
                            passageLogger.debug("[WEBVIEW SCREENSHOT] Restored webview to hidden state (alpha: \(originalAlpha))")
                        }
                    
                    if let error = error {
                        passageLogger.error("[WEBVIEW SCREENSHOT] ❌ WKWebView.takeSnapshot failed: \(error)")
                        passageLogger.error("[WEBVIEW SCREENSHOT] Error details: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    guard let image = image else {
                        passageLogger.error("[WEBVIEW SCREENSHOT] ❌ WKWebView.takeSnapshot returned nil image")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    passageLogger.info("[WEBVIEW SCREENSHOT] ✅ WKWebView.takeSnapshot succeeded, captured image size: \(image.size)")
                    
                    // Apply image optimization from configuration parameters
                    let optimizedImageData = self?.applyImageOptimization(to: image)
                    
                    guard let optimizedData = optimizedImageData else {
                        passageLogger.error("[WEBVIEW SCREENSHOT] ❌ Failed to apply image optimization")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let base64String = optimizedData.base64String
                    
                    // Update screenshot state - move current to previous, set new as current
                    self?.previousScreenshot = self?.currentScreenshot
                    self?.currentScreenshot = base64String
                    
                    passageLogger.info("[WEBVIEW SCREENSHOT] ✅ Screenshot captured and optimized successfully:")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Original: \(Int(optimizedData.originalSize.width))x\(Int(optimizedData.originalSize.height))")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Optimized: \(Int(optimizedData.optimizedSize.width))x\(Int(optimizedData.optimizedSize.height))")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Format: \(optimizedData.format)")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Quality: \(optimizedData.compressionQuality)")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Final size: \(base64String.count) chars")
                    passageLogger.info("[WEBVIEW SCREENSHOT]   Method: WKWebView.takeSnapshot (proper WebView content capture)")
                    
                        continuation.resume(returning: base64String)
                    }
                }
            }
        }
    }
    
    /// Capture the whole UI view (including native iOS elements) when record flag is true
    private func captureWholeUIScreenshot() async -> String? {
        passageLogger.info("[WHOLE UI SCREENSHOT] ========== CAPTURING WHOLE UI SCREENSHOT ==========")
        
        guard let remoteControl = remoteControl else {
            passageLogger.error("[WHOLE UI SCREENSHOT] ❌ No remote control available")
            return nil
        }
        
        let recordFlag = remoteControl.getRecordFlag()
        passageLogger.info("[WHOLE UI SCREENSHOT] Record flag: \(recordFlag)")
        
        guard recordFlag else {
            passageLogger.warn("[WHOLE UI SCREENSHOT] ⚠️ Whole UI screenshot capture skipped - record flag is false")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    passageLogger.error("[WHOLE UI SCREENSHOT] ❌ Self is nil")
                    continuation.resume(returning: nil)
                    return
                }
                
                guard let view = self.view else {
                    passageLogger.error("[WHOLE UI SCREENSHOT] ❌ View is nil")
                    continuation.resume(returning: nil)
                    return
                }
                
                passageLogger.info("[WHOLE UI SCREENSHOT] 📸 Capturing screenshot of whole UI view")
                passageLogger.debug("[WHOLE UI SCREENSHOT] View bounds: \(view.bounds)")
                passageLogger.debug("[WHOLE UI SCREENSHOT] View frame: \(view.frame)")
                passageLogger.debug("[WHOLE UI SCREENSHOT] View isHidden: \(view.isHidden)")
                passageLogger.debug("[WHOLE UI SCREENSHOT] View alpha: \(view.alpha)")
                
                // Use UIView rendering to capture the entire view hierarchy including native iOS elements
                let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
                let image = renderer.image { context in
                    // Render the entire view hierarchy into the context
                    view.layer.render(in: context.cgContext)
                }
                
                passageLogger.info("[WHOLE UI SCREENSHOT] ✅ Whole UI screenshot captured, image size: \(image.size)")
                
                // Apply image optimization from configuration parameters
                let optimizedImageData = self.applyImageOptimization(to: image)
                
                guard let optimizedData = optimizedImageData else {
                    passageLogger.error("[WHOLE UI SCREENSHOT] ❌ Failed to apply image optimization")
                    continuation.resume(returning: nil)
                    return
                }
                
                let base64String = optimizedData.base64String
                
                // Update screenshot state - move current to previous, set new as current
                self.previousScreenshot = self.currentScreenshot
                self.currentScreenshot = base64String
                
                passageLogger.info("[WHOLE UI SCREENSHOT] ✅ Whole UI screenshot captured and optimized successfully:")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Original: \(Int(optimizedData.originalSize.width))x\(Int(optimizedData.originalSize.height))")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Optimized: \(Int(optimizedData.optimizedSize.width))x\(Int(optimizedData.optimizedSize.height))")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Format: \(optimizedData.format)")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Quality: \(optimizedData.compressionQuality)")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Final size: \(base64String.count) chars")
                passageLogger.info("[WHOLE UI SCREENSHOT]   Method: UIGraphicsImageRenderer (captures whole UI including native elements)")
                
                continuation.resume(returning: base64String)
            }
        }
    }
    
    // Set automation webview user agent (matches React Native implementation)
    func setAutomationUserAgent(_ userAgent: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            passageLogger.debug("[WEBVIEW] Setting automation user agent: \(userAgent)")
            
            // Store the user agent for when webview is recreated
            self.automationUserAgent = userAgent.isEmpty ? nil : userAgent
            
            // Apply to current webview if it exists
            if let automationWebView = self.automationWebView {
                automationWebView.customUserAgent = userAgent
                passageLogger.debug("[WEBVIEW] Applied user agent to existing automation webview")
            } else {
                passageLogger.debug("[WEBVIEW] Automation webview not yet created, user agent will be applied when created")
            }
        }
    }
    
    // Set automation webview URL (matches React Native implementation)
    func setAutomationUrl(_ url: String) {
        passageLogger.info("[WEBVIEW] ========== SET AUTOMATION URL CALLED ==========")
        passageLogger.info("[WEBVIEW] 🚀 setAutomationUrl called with: \(passageLogger.truncateUrl(url, maxLength: 100))")
        passageLogger.info("[WEBVIEW] Thread: \(Thread.isMainThread ? "Main" : "Background")")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { 
                passageLogger.error("[WEBVIEW] ❌ Self is nil in setAutomationUrl")
                return 
            }
            
            passageLogger.info("[WEBVIEW] Now on main thread, proceeding with URL setting")
            passageLogger.info("[WEBVIEW] Automation webview exists: \(self.automationWebView != nil)")
            
            if self.automationWebView == nil {
                passageLogger.error("[WEBVIEW] ❌ CRITICAL: Automation webview is NIL!")
                passageLogger.error("[WEBVIEW] This means webviews were not set up properly")
                
                // Try to setup webviews if view is loaded
                if self.isViewLoaded && self.view.window != nil {
                    passageLogger.info("[WEBVIEW] Attempting to setup webviews for automation URL")
                    self.setupWebViews()
                    
                    if self.automationWebView != nil {
                        passageLogger.info("[WEBVIEW] ✅ Webviews set up successfully, retrying URL load")
                    } else {
                        passageLogger.error("[WEBVIEW] ❌ Failed to setup webviews")
                        return
                    }
                } else {
                    passageLogger.error("[WEBVIEW] Cannot setup webviews - view not ready")
                    return
                }
            }
            
            if let urlObj = URL(string: url) {
                passageLogger.info("[WEBVIEW] ✅ URL is valid, loading in automation webview")
                
                // Store the intended URL before attempting navigation
                self.intendedAutomationURL = url
                passageLogger.info("[WEBVIEW] 📝 Stored intended automation URL from setAutomationUrl: \(url)")
                
                let request = URLRequest(url: urlObj)
                self.automationWebView?.load(request)
                passageLogger.info("[WEBVIEW] 🎯 AUTOMATION WEBVIEW LOAD REQUESTED!")
                passageLogger.info("[WEBVIEW] This should trigger navigation and give the webview a URL")
            } else {
                passageLogger.error("[WEBVIEW] ❌ Invalid URL provided: \(url)")
            }
        }
    }
    
    /// Update global JavaScript configuration and recreate automation webview if needed
    /// This should be called when configuration changes include new globalJavascript
    func updateGlobalJavaScript() {
        passageLogger.info("[WEBVIEW] 🔄 updateGlobalJavaScript() called")
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { 
                passageLogger.error("[WEBVIEW] Self is nil in updateGlobalJavaScript")
                return 
            }
            
            // Check if we have an automation webview and if global JS has changed
            let newGlobalScript = self.generateGlobalJavaScript()
            
            passageLogger.info("[WEBVIEW] Current automation webview exists: \(self.automationWebView != nil)")
            passageLogger.info("[WEBVIEW] New global script length: \(newGlobalScript.count) chars")
            
            if !newGlobalScript.isEmpty {
                passageLogger.info("[WEBVIEW] 🚀 Global JavaScript updated (\(newGlobalScript.count) chars), recreating automation webview")
                
                // Store current URL if automation webview exists
                var currentUrl: String?
                if let automationWebView = self.automationWebView {
                    currentUrl = automationWebView.url?.absoluteString
                    passageLogger.debug("[WEBVIEW] Current automation webview URL: \(currentUrl ?? "nil")")
                }
                
                // Recreate automation webview with new global JavaScript
                self.recreateAutomationWebView()
                
                // Reload the current URL if we had one
                if let url = currentUrl, !url.isEmpty {
                    passageLogger.info("[WEBVIEW] Reloading automation webview with URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
                    self.setAutomationUrl(url)
                }
            } else {
                passageLogger.info("[WEBVIEW] ℹ️ No global JavaScript to update (empty script)")
            }
        }
    }
    
    private func recreateAutomationWebView() {
        passageLogger.debug("[WEBVIEW] Recreating automation webview with updated configuration")
        
        // Remove old automation webview
        if let oldAutomationWebView = automationWebView {
            oldAutomationWebView.removeFromSuperview()
        }
        
        // Create new automation webview
        automationWebView = createWebView(webViewType: PassageConstants.WebViewTypes.automation)
        
        // Add to view hierarchy
        view.addSubview(automationWebView)
        automationWebView.translatesAutoresizingMaskIntoConstraints = false
        
        // Ensure header container exists before setting constraints
        guard let headerContainer = headerContainer else {
            passageLogger.error("[WEBVIEW] Header container is nil when recreating automation webview")
            return
        }
        
        // Set constraints to position automation webview BELOW the header container
        NSLayoutConstraint.activate([
            automationWebView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            automationWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            automationWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            automationWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Set initial visibility (automation webview starts hidden)
        automationWebView.alpha = 0
        
        // Ensure header container stays on top
        view.bringSubviewToFront(headerContainer)
        
        passageLogger.info("[WEBVIEW] Automation webview recreated successfully")
    }
    
    // Handle navigation state changes (like React Native implementation)
    private func handleNavigationStateChange(url: String, loading: Bool, webViewType: String) {
        passageLogger.debug("[NAVIGATION] State change - \(webViewType): \(passageLogger.truncateUrl(url, maxLength: 100)), loading: \(loading)")

        // Only send browser state for automation webview
        if webViewType == PassageConstants.WebViewTypes.automation && !url.isEmpty {
            if loading {
                // Skip backend tracking if navigation was triggered by back button
                if isNavigatingFromBackButton {
                    passageLogger.debug("[NAVIGATION] Skipping browser state send - navigation triggered by back button")
                    // Don't send browser state for back button navigations
                } else {
                    // Send browser state on navigation start - only include fields defined in BrowserStateRequestDto
                    let browserStateData: [String: Any] = [
                        "url": url
                        // Only url is sent - other fields (html, localStorage, sessionStorage, cookies, screenshot)
                        // are captured separately when needed
                    ]

                    NotificationCenter.default.post(
                        name: .sendBrowserState,
                        object: nil,
                        userInfo: browserStateData
                    )

                    passageLogger.debug("[NAVIGATION] Page starting to load for automation webview, sent browser state")
                }
            } else {
                // Reset back button navigation flag when navigation completes
                if isNavigatingFromBackButton {
                    passageLogger.debug("[NAVIGATION] Back button navigation completed, resetting flag")
                    isNavigatingFromBackButton = false
                }

                // Re-enable back navigation after first navigation completes (from programmatic navigate)
                if isBackNavigationDisabled {
                    passageLogger.debug("[NAVIGATION] Re-enabling back navigation after programmatic navigate completed")
                    isBackNavigationDisabled = false
                }

                // Handle injectScript command reinjection for record mode when loading is complete
                // Call handleNavigationComplete directly (matches React Native implementation)
                remoteControl?.handleNavigationComplete(url)

                passageLogger.debug("[NAVIGATION] Page loaded for automation webview, checking for reinjection")

                // Update back button visibility after navigation completes
                updateBackButtonVisibility()
            }
        }
    }
    
    // Handle window.passage.postMessage calls (matches React Native implementation)
    private func handlePassageMessage(_ data: [String: Any], webViewType: String) {
        // Handle internal messages (like React Native remote control)
        if let commandId = data["commandId"] as? String,
           let type = data["type"] as? String {
            
            passageLogger.info("[WEBVIEW] Handling passage message: \(type) for command: \(commandId)")
            
            switch type {
            case "injectScript", "wait":
                // Handle script execution result
                let success = data["error"] == nil
                
                passageLogger.debug("[WEBVIEW] \(type) command result: success=\(success)")
                
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .scriptExecutionResult,
                        object: nil,
                        userInfo: [
                            "commandId": commandId,
                            "success": success,
                            "result": data["value"] ?? NSNull(),
                            "error": data["error"] as? String ?? ""
                        ]
                    )
                }
                
            default:
                passageLogger.debug("[WEBVIEW] Unhandled passage message type: \(type)")
                // Forward to SDK message handler
                onMessage?(data)
            }
        } else {
            // Handle SDK messages from UI webview (like React Native implementation)
            if webViewType == PassageConstants.WebViewTypes.ui {
                if let messageType = data["type"] as? String {
                    switch messageType {
                    case "CONNECTION_SUCCESS":
                        let connections = data["connections"] as? [[String: Any]] ?? []
                        onMessage?([
                            "type": "CONNECTION_SUCCESS",
                            "connections": connections
                        ])
                        
                    case "CONNECTION_ERROR":
                        let error = data["error"] as? String ?? "Unknown error"
                        onMessage?([
                            "type": "CONNECTION_ERROR",
                            "error": error
                        ])
                        
                    case "CLOSE_MODAL":
                        onMessage?(["type": "CLOSE_MODAL"])
                        
                    default:
                        onMessage?(data)
                    }
                } else {
                    onMessage?(data)
                }
            } else {
                // Forward automation webview messages
                onMessage?(data)
            }
        }
    }
    
    // MARK: - UIAdaptivePresentationControllerDelegate
    
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Handle pull-down dismissal
        passageLogger.info("[WEBVIEW] ========== PRESENTATION CONTROLLER DID DISMISS ==========")
        passageLogger.info("[WEBVIEW] Delegate exists: \(delegate != nil)")
        passageLogger.debug("[WEBVIEW] Delegate type: \(String(describing: delegate))")
        
        // Reset URL state immediately when modal is dismissed
        resetURLState()
        
        // Only call delegate method to avoid duplicate handleClose calls
        // The delegate (PassageSDK) will handle the close logic
        if let delegate = delegate {
            passageLogger.info("[WEBVIEW] Calling delegate.webViewModalDidClose()")
            delegate.webViewModalDidClose()
        } else {
            passageLogger.error("[WEBVIEW] ❌ No delegate to call webViewModalDidClose()!")
        }
    }
    
    // MARK: - Helper Methods
    
    private func handleNavigationTimeout(for webView: WKWebView) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        passageLogger.error("Navigation timeout after 30 seconds for \(webViewType) webview")
        
        // Stop loading
        webView.stopLoading()
        
        // Try to get current state
        webView.evaluateJavaScript("document.readyState") { result, _ in
            if let state = result as? String {
                passageLogger.error("Document state at timeout: \(state)")
            }
        }
        
        webView.evaluateJavaScript("window.location.href") { result, _ in
            if let currentURL = result as? String {
                passageLogger.error("Current URL at timeout: \(currentURL)")
            }
        }
        
        // Don't show alert on HTTP errors as per requirement
        passageLogger.error("[WebView] Connection timeout - page took too long to load")
        // Silently handle the error without showing alert
    }
    
    private func showNavigationError(_ message: String) {
        // Don't show alert on HTTP errors as per requirement
        passageLogger.error("[WebView] Navigation error: \(message)")
        // Silently handle the error without showing alert
    }
    
    private func checkNavigationStatus(for webView: WKWebView) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        
        passageLogger.debug("[NAVIGATION] \(webViewType) - Loading: \(webView.isLoading), Progress: \(Int(webView.estimatedProgress * 100))%")
        
        // Only log URL for automation webview or if there's an issue
        if webViewType == PassageConstants.WebViewTypes.automation {
            if let url = webView.url {
                passageLogger.debug("[NAVIGATION] \(webViewType) URL: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
            }
        }
        
        // Only check document state if there might be an issue
        if !webView.isLoading && webView.estimatedProgress < 1.0 {
            webView.evaluateJavaScript("document.readyState") { result, error in
                if let state = result as? String, state != "complete" {
                    passageLogger.warn("[NAVIGATION] \(webViewType) document not ready: \(state)")
                }
            }
        }
    }
}

// MARK: - WKNavigationDelegate
extension WebViewModalViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        
        if let url = webView.url {
            passageLogger.info("[NAVIGATION] 🚀 \(webViewType) loading: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
            
            // Check for success URL match on navigation start (only for automation webview)
            if webViewType == PassageConstants.WebViewTypes.automation {
                remoteControl?.checkNavigationStart(url.absoluteString)
            }
            
            // Handle navigation state change (like React Native implementation)
            handleNavigationStateChange(url: url.absoluteString, loading: true, webViewType: webViewType)
            passageAnalytics.trackNavigationStart(url: url.absoluteString, webViewType: webViewType)
            navigationStartTime = Date()
        } else {
            passageLogger.warn("[NAVIGATION] \(webViewType) loading with no URL")
        }
        
        // Cancel any existing timeout timer
        navigationTimeoutTimer?.invalidate()
        
        // Start a new timeout timer (15 seconds for better UX)
        navigationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            passageLogger.error("[NAVIGATION] ⏱️ TIMEOUT: \(webViewType) navigation didn't complete in 15 seconds")
            self?.handleNavigationTimeout(for: webView)
        }
        
        // Check navigation status at fewer intervals and only for automation webview
        if webViewType == PassageConstants.WebViewTypes.automation {
            let checkIntervals: [Double] = [2.0, 5.0]
            for interval in checkIntervals {
                DispatchQueue.main.asyncAfter(deadline: .now() + interval) { [weak self] in
                    self?.checkNavigationStatus(for: webView)
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Cancel timeout timer
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
        
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        
        if let url = webView.url {
            passageLogger.info("[NAVIGATION] ✅ \(webViewType) loaded: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
            
            // Check for success URL match on navigation end (only for automation webview)
            if webViewType == PassageConstants.WebViewTypes.automation {
                remoteControl?.checkNavigationEnd(url.absoluteString)
            }
            
            // Send delegate callback for both webviews
            delegate?.webViewModal(didNavigateTo: url)
            
            // Handle navigation state change (like React Native implementation)
            handleNavigationStateChange(url: url.absoluteString, loading: false, webViewType: webViewType)
            let duration = navigationStartTime != nil ? Date().timeIntervalSince(navigationStartTime!) : nil
            passageAnalytics.trackNavigationSuccess(url: url.absoluteString, webViewType: webViewType, duration: duration)
            navigationStartTime = nil
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Cancel timeout timer
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
        
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        passageLogger.webView("Navigation failed: \(error.localizedDescription)", webViewType: webViewType)
        
        if let url = webView.url {
            // Handle navigation state change for failed navigation
            handleNavigationStateChange(url: url.absoluteString, loading: false, webViewType: webViewType)
            passageAnalytics.trackNavigationError(url: url.absoluteString, webViewType: webViewType, error: error.localizedDescription)
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Cancel timeout timer
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
        
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        let nsError = error as NSError
        
        passageLogger.error("[NAVIGATION] ❌ \(webViewType) navigation FAILED: \(error.localizedDescription)")
        passageLogger.error("[NAVIGATION] Error domain: \(nsError.domain), code: \(nsError.code)")
        
        // For automation webview navigation failures, this is critical
        if webViewType == PassageConstants.WebViewTypes.automation {
            passageLogger.error("[NAVIGATION] ❌ CRITICAL: Automation webview navigation failed!")
            passageLogger.error("[NAVIGATION] This will cause script injection to fail")
            passageLogger.error("[NAVIGATION] Error details: \(nsError)")
            
            // Check if this is a network connectivity issue
            if nsError.domain == NSURLErrorDomain {
                switch nsError.code {
                case NSURLErrorNotConnectedToInternet:
                    passageLogger.error("[NAVIGATION] ❌ No internet connection")
                case NSURLErrorNetworkConnectionLost:
                    passageLogger.error("[NAVIGATION] ❌ Network connection lost during load")
                case NSURLErrorTimedOut:
                    passageLogger.error("[NAVIGATION] ❌ Navigation timed out")
                case NSURLErrorCannotConnectToHost:
                    passageLogger.error("[NAVIGATION] ❌ Cannot connect to host")
                case NSURLErrorDNSLookupFailed:
                    passageLogger.error("[NAVIGATION] ❌ DNS lookup failed")
                default:
                    passageLogger.error("[NAVIGATION] ❌ Other network error: \(nsError.code)")
                }
            }
            
            // For automation webview, keep the intended URL so scripts can still be injected
            if intendedAutomationURL != nil {
                passageLogger.info("[NAVIGATION] 💡 Keeping intended automation URL for script injection")
                passageLogger.info("[NAVIGATION] Scripts will be injected even though navigation failed")
            }
        }
        
        // Handle navigation state change for failed provisional navigation
        let failedUrl = webView.url?.absoluteString ?? nsError.userInfo["NSErrorFailingURLStringKey"] as? String ?? intendedAutomationURL ?? "unknown"
        handleNavigationStateChange(url: failedUrl, loading: false, webViewType: webViewType)
        passageAnalytics.trackNavigationError(url: failedUrl, webViewType: webViewType, error: error.localizedDescription)
        
        // Let the webview show whatever it can (error page, cached content, etc.)
        // Don't retry or stop navigation - just let it be
    }
    
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        
        if let url = webView.url {
            passageLogger.info("[NAVIGATION] 📍 \(webViewType) committed: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
            
            // Handle navigation state change when navigation is committed (URL bar updates)
            handleNavigationStateChange(url: url.absoluteString, loading: true, webViewType: webViewType)
            
            // Check for success URL match on commit (for automation webview)
            if webViewType == PassageConstants.WebViewTypes.automation {
                remoteControl?.checkNavigationStart(url.absoluteString)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        
        if let url = webView.url {
            passageLogger.info("[NAVIGATION] 🔄 \(webViewType) redirected: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
            
            // Handle server redirects
            handleNavigationStateChange(url: url.absoluteString, loading: true, webViewType: webViewType)
            
            // Check for success URL match on redirect (for automation webview)
            if webViewType == PassageConstants.WebViewTypes.automation {
                remoteControl?.checkNavigationStart(url.absoluteString)
            }
            
            // Track analytics for redirect
            passageAnalytics.trackNavigationStart(url: url.absoluteString, webViewType: webViewType)
        }
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Log navigation details
        if let url = navigationAction.request.url {
            passageLogger.debug("Navigation policy check for URL: \(url.absoluteString)")
            passageLogger.debug("Navigation type: \(navigationAction.navigationType.rawValue)")
        }
        
        // Allow all navigation to happen inside the webview
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        // Log response details
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            passageLogger.debug("HTTP Response - Status Code: \(httpResponse.statusCode)")
            passageLogger.debug("HTTP Response - URL: \(httpResponse.url?.absoluteString ?? "nil")")
            
            // Log important headers
            if let contentType = httpResponse.allHeaderFields["Content-Type"] as? String {
                passageLogger.debug("Content-Type: \(contentType)")
            }
            
            if let contentLength = httpResponse.allHeaderFields["Content-Length"] as? String {
                passageLogger.debug("Content-Length: \(contentLength)")
            }
            
            if let csp = httpResponse.allHeaderFields["Content-Security-Policy"] as? String {
                passageLogger.debug("CSP: \(passageLogger.truncateData(csp, maxLength: 200))")
            }
            
            if let xFrameOptions = httpResponse.allHeaderFields["X-Frame-Options"] as? String {
                passageLogger.warn("X-Frame-Options present: \(xFrameOptions)")
                // X-Frame-Options might prevent loading in WebView
            }
            
            if httpResponse.statusCode >= 400 {
                passageLogger.warn("HTTP Error Response: \(httpResponse.statusCode) - allowing navigation to continue")
                // Allow navigation even for error responses - let the webview show the error page
            }
        }
        
        decisionHandler(.allow)
    }
}

// MARK: - WKScriptMessageHandler
extension WebViewModalViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == PassageConstants.MessageHandlers.passageWebView {
            if let body = message.body as? [String: Any] {
                let type = body["type"] as? String ?? PassageConstants.MessageTypes.message
                let webViewType = body["webViewType"] as? String ?? "unknown"
                
                passageLogger.webView("Received message type: \(type)", webViewType: webViewType)
                
                switch type {
                case PassageConstants.MessageTypes.navigate:
                    if let url = body["url"] as? String {
                        passageLogger.webView("Navigate to: \(passageLogger.truncateUrl(url, maxLength: 100))", webViewType: webViewType)
                        navigateTo(url)
                    }
                case PassageConstants.MessageTypes.close:
                    passageLogger.webView("Close modal", webViewType: webViewType)
                    closeModal()
                case PassageConstants.MessageTypes.setTitle:
                    if let title = body["title"] as? String {
                        passageLogger.webView("Set title: \(title)", webViewType: webViewType)
                        updateTitle(title)
                    }
                case "pageData":
                    // Handle page data collection results
                    passageLogger.debug("[WEBVIEW] Received page data from automation webview")
                    if let data = body["data"] as? [String: Any] {
                        passageLogger.debug("[WEBVIEW] Page data contains: url=\(data["url"] != nil), html=\(passageLogger.truncateHtml(data["html"] as? String)), localStorage=\((data["localStorage"] as? [Any])?.count ?? 0) items, sessionStorage=\((data["sessionStorage"] as? [Any])?.count ?? 0) items")
                        
                        // Forward page data to remote control
                        remoteControl?.handlePageDataResult(data)
                    } else if let error = body["error"] as? String {
                        passageLogger.error("[WEBVIEW] Page data collection error: \(error)")
                        remoteControl?.handlePageDataResult([:])
                    } else {
                        passageLogger.warn("[WEBVIEW] Page data message without data or error field")
                        remoteControl?.handlePageDataResult([:])
                    }
                case "console_error":
                    if let errorMessage = body["message"] as? String {
                        passageLogger.error("JavaScript Console Error: \(errorMessage)")
                    }
                case "javascript_error":
                    let errorMessage = body["message"] ?? "Unknown error"
                    let isWeakMapError = body["isWeakMapError"] as? Bool ?? false
                    
                    if isWeakMapError {
                        passageLogger.error("🚨 WeakMap JavaScript Error: \(errorMessage)")
                        passageLogger.error("  This is likely caused by global JavaScript injection timing issues")
                    } else {
                        passageLogger.error("JavaScript Error: \(errorMessage)")
                    }
                    
                    if let source = body["source"] as? String {
                        passageLogger.error("  Source: \(source)")
                    }
                    if let line = body["line"] as? Int {
                        passageLogger.error("  Line: \(line)")
                    }
                    if let stack = body["stack"] as? String {
                        passageLogger.error("  Stack: \(stack)")
                    }
                case "unhandled_rejection":
                    passageLogger.error("Unhandled Promise Rejection: \(body["message"] ?? "Unknown rejection")")
                case "clientNavigation":
                    // Handle client-side navigation events (pushState, replaceState, hash changes)
                    if let url = body["url"] as? String,
                       let navigationMethod = body["navigationMethod"] as? String {
                        passageLogger.info("[CLIENT NAV] \(webViewType) - \(navigationMethod): \(passageLogger.truncateUrl(url, maxLength: 100))")
                        
                        // Handle the navigation state change
                        handleNavigationStateChange(url: url, loading: false, webViewType: webViewType)
                        
                        // For automation webview, check for success URL match
                        if webViewType == PassageConstants.WebViewTypes.automation {
                            remoteControl?.checkNavigationEnd(url)
                        }
                        
                        // Send delegate callback
                        if let urlObj = URL(string: url) {
                            delegate?.webViewModal(didNavigateTo: urlObj)
                        }
                        
                        // Track analytics
                        passageAnalytics.trackNavigationSuccess(url: url, webViewType: webViewType, duration: nil)
                    }
                case "captureScreenshot":
                    // Handle window.passage.captureScreenshot calls
                    passageLogger.info("[WEBVIEW] Manual screenshot capture requested from \(webViewType) webview")
                    
                    // Trigger screenshot capture via remote control
                    Task {
                        await remoteControl?.captureScreenshotManually()
                    }
                    
                case "CLOSE_CONFIRMED":
                    // User confirmed they want to close the modal
                    passageLogger.info("[WEBVIEW] Close confirmation received - proceeding with close")
                    DispatchQueue.main.async {
                        self.closeModal()
                    }
                case "CLOSE_CANCELLED":
                    // User cancelled the close action
                    passageLogger.info("[WEBVIEW] Close cancelled by user")
                    // Reset close button press counter when user cancels
                    self.closeButtonPressCount = 0
                    // Switch back to automation webview if that's where we were before
                    if self.wasShowingAutomationBeforeClose {
                        passageLogger.info("[WEBVIEW] Switching back to automation webview after close cancellation")
                        self.showAutomationWebView()
                    }
                    // Reset the state
                    self.wasShowingAutomationBeforeClose = false
                case PassageConstants.MessageTypes.message:
                    // Handle window.passage.postMessage calls
                    if let data = body["data"] {
                        if let dataString = data as? String,
                           let jsonData = dataString.data(using: .utf8),
                           let parsedData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            // This is a JSON string from window.passage.postMessage
                            handlePassageMessage(parsedData, webViewType: webViewType)
                        } else if let dataDict = data as? [String: Any] {
                            // This is already a dictionary
                            handlePassageMessage(dataDict, webViewType: webViewType)
                        } else {
                            // Fallback to original behavior
                            onMessage?(data)
                        }
                    } else {
                        onMessage?(body)
                    }
                default:
                    let messageData = body["data"] ?? body
                    onMessage?(messageData)
                }
            } else {
                // Legacy support
                onMessage?(message.body)
            }
        }
    }
}
#endif
