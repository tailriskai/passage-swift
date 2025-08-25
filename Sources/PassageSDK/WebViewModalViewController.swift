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

class WebViewModalViewController: UIViewController, UIAdaptivePresentationControllerDelegate {
    weak var delegate: WebViewModalDelegate?
    
    var modalTitle: String = ""
    var titleText: String = ""
    var showGrabber: Bool = false
    // Optional initial URL (parity with Capacitor). If set, loads on viewDidLoad.
    var url: String = ""
    
    // Callback closures
    var onMessage: ((Any) -> Void)?
    var onClose: (() -> Void)?
    var onWebviewChange: ((String) -> Void)?
    
    // Remote control reference (for navigation completion)
    var remoteControl: RemoteControlManager?
    
    // Dual webviews - created once and reused across sessions
    // These are never destroyed during the SDK lifecycle unless releaseResources() is called
    private var uiWebView: WKWebView!
    private var automationWebView: WKWebView!
    
    private var currentURL: String = ""
    private var isShowingUIWebView: Bool = true
    private var isAnimating: Bool = false
    
    // Store pending user action command
    private var pendingUserActionCommand: PendingUserActionCommand?
    
    // Screenshot support (matching React Native implementation)
    private var currentScreenshot: String?
    private var previousScreenshot: String?
    
    // Store initial URL to load after view appears
    private var initialURLToLoad: String?
    
    // Debug: force rendering just one webview with a predefined URL
    private let debugSingleWebViewUrl: String? = nil
    // Temporary: force a simple, Capacitor-like single webview configuration
    private let forceSimpleWebView: Bool = false
    
    // Navigation timeout timer
    private var navigationTimeoutTimer: Timer?
    private var navigationStartTime: Date?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        passageLogger.info("[WEBVIEW] ========== VIEW DID LOAD ==========")
        passageLogger.info("[WEBVIEW] Initial URL: \(url.isEmpty ? "empty" : passageLogger.truncateUrl(url, maxLength: 100))")
        passageLogger.info("[WEBVIEW] Show grabber: \(showGrabber)")
        passageLogger.info("[WEBVIEW] Title text: \(titleText)")
        passageLogger.info("[WEBVIEW] Force simple webview: \(forceSimpleWebView)")
        passageLogger.info("[WEBVIEW] Debug single webview URL: \(debugSingleWebViewUrl ?? "nil")")
        
        // Setup screenshot accessors for remote control
        setupScreenshotAccessors()
        
        setupUI()
        setupWebViews()
        setupNotificationObservers()
        
        // Hide navigation bar completely to remove white header
        navigationController?.setNavigationBarHidden(true, animated: false)
        
        passageLogger.debug("[WEBVIEW] Navigation bar hidden to remove white header")

        // If in debug single-webview mode, we've already created and loaded it in setupWebViews.
        if let debugUrl = debugSingleWebViewUrl, !debugUrl.isEmpty {
            passageLogger.info("[WEBVIEW DEBUG MODE] Single webview mode active with URL: \(passageLogger.truncateUrl(debugUrl, maxLength: 100))")
            return
        }

        // Parity with Capacitor: if `url` was set, load it immediately
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
        
        passageLogger.info("[WEBVIEW] View appeared")
        
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
        
        // Cancel any pending navigation timeout
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
    }
    
    deinit {
        // Clean up timer
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupUI() {
        // Set background color to match web app container (light gray)
        view.backgroundColor = PassageConstants.Colors.webViewBackground
        
        // No close button - modal should be dismissed via swipe down or programmatically
    }
    
    private func setupNotificationObservers() {
        passageLogger.info("[WEBVIEW] Setting up notification observers")
        
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
    }
    
    @objc private func showUIWebViewNotification() {
        passageLogger.info("[WEBVIEW] Received showUIWebView notification")
        showUIWebView()
    }
    
    @objc private func showAutomationWebViewNotification() {
        passageLogger.info("[WEBVIEW] Received showAutomationWebView notification")
        showAutomationWebView()
    }
    
    @objc private func navigateInAutomationNotification(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? String else {
            passageLogger.error("[WEBVIEW] Navigate notification missing URL")
            return
        }
        let commandId = notification.userInfo?["commandId"] as? String
        passageLogger.info("[WEBVIEW] Received navigate notification: \(passageLogger.truncateUrl(url, maxLength: 100))")
        passageLogger.debug("[WEBVIEW] Command ID: \(commandId ?? "nil")")
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
        guard let script = notification.userInfo?["script"] as? String,
              let commandId = notification.userInfo?["commandId"] as? String else {
            passageLogger.error("[WEBVIEW] Inject script notification missing data")
            return
        }
        
        let commandType = notification.userInfo?["commandType"] as? String ?? "unknown"
        passageLogger.info("[WEBVIEW] Executing \(commandType) script for command: \(commandId)")
        
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
    
    private func createWebView(webViewType: String) -> WKWebView {
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
        
        // Keep config minimal (match Capacitor behavior for https loads)
        
        // Set up messaging — in simple mode, skip all scripts/handlers to avoid CSP/conflicts
        if !forceSimpleWebView && debugSingleWebViewUrl == nil {
            passageLogger.info("[WEBVIEW] Setting up message handlers and scripts")
            let userContentController = WKUserContentController()
            
            // Add message handler for modal communication (using Capacitor-style handler name)
            userContentController.add(self, name: PassageConstants.MessageHandlers.capacitorWebViewModal)
            
            // Inject window.passage script immediately on webview creation
            let passageScript = createPassageScript(for: webViewType)
            let userScript = WKUserScript(
                source: passageScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            userContentController.addUserScript(userScript)
            
            // Add console logging script
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
                
                // Capture uncaught errors
                window.addEventListener('error', function(event) {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                        window.webkit.messageHandlers.passageWebView.postMessage({
                            type: 'javascript_error',
                            message: event.message,
                            source: event.filename,
                            line: event.lineno,
                            column: event.colno,
                            stack: event.error ? event.error.stack : '',
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
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        // In debug/simple mode, set a Safari-like user agent
        if debugSingleWebViewUrl != nil || forceSimpleWebView {
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
        
        // Use default user agent (match Capacitor)
        
        // Tag webviews for identification
        webView.tag = webViewType == PassageConstants.WebViewTypes.automation ? 2 : 1
        
        return webView
    }
    
    private func setupWebViews() {
        // Check if webviews are already created
        if uiWebView != nil {
            passageLogger.info("[WEBVIEW] WebViews already created, skipping setup")
            return
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
        
        // Create both webviews (default behavior)
        uiWebView = createWebView(webViewType: PassageConstants.WebViewTypes.ui)
        automationWebView = createWebView(webViewType: PassageConstants.WebViewTypes.automation)
        
        // Add both webviews to the view hierarchy
        view.addSubview(uiWebView)
        view.addSubview(automationWebView)
        
        // Setup constraints for both webviews (they overlap)
        NSLayoutConstraint.activate([
            // UI webview constraints
            uiWebView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            uiWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            uiWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            uiWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            
            // Automation webview constraints (same as UI)
            automationWebView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            automationWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            automationWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            automationWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Initially show UI webview, hide automation webview
        uiWebView.alpha = 1
        automationWebView.alpha = 0
        view.bringSubviewToFront(uiWebView)
    }
    
    private func createPassageScript(for webViewType: String) -> String {
        if webViewType == PassageConstants.WebViewTypes.automation {
            // Full script for automation webview (matches Capacitor implementation)
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
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capacitorWebViewModal) {
                      console.log('[Passage] Sending message via webkit handler');
                      window.webkit.messageHandlers.capacitorWebViewModal.postMessage({
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
                      console.log('[Passage] capacitorWebViewModal handler:', typeof window.webkit?.messageHandlers?.capacitorWebViewModal);
                    }
                  } catch (error) {
                    console.error('[Passage] Error posting message:', error);
                  }
                },
                
                // Navigation functionality
                navigate: function(url) {
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capacitorWebViewModal) {
                      window.webkit.messageHandlers.capacitorWebViewModal.postMessage({
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
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capacitorWebViewModal) {
                      window.webkit.messageHandlers.capacitorWebViewModal.postMessage({
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
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capacitorWebViewModal) {
                      window.webkit.messageHandlers.capacitorWebViewModal.postMessage({
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
                }
              };
              
              console.log('[Passage] Automation webview script initialized successfully');
              console.log('[Passage] window.passage.initialized:', window.passage.initialized);
              console.log('[Passage] window.passage.webViewType:', window.passage.webViewType);
            })();
            """
        } else {
            // Full script for UI webview (matches Capacitor implementation)
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
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capacitorWebViewModal) {
                      window.webkit.messageHandlers.capacitorWebViewModal.postMessage({
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
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capacitorWebViewModal) {
                      window.webkit.messageHandlers.capacitorWebViewModal.postMessage({
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
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capacitorWebViewModal) {
                      window.webkit.messageHandlers.capacitorWebViewModal.postMessage({
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
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.capacitorWebViewModal) {
                      window.webkit.messageHandlers.capacitorWebViewModal.postMessage({
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
                }
              };
              
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
        
        // Load URL
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                passageLogger.error("[WEBVIEW] Self is nil in loadURL")
                return
            }
            
            guard let webView = self.uiWebView else {
                passageLogger.error("[WEBVIEW] ❌ UI WebView is nil")
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
            let request = URLRequest(url: url)
            self?.uiWebView.load(request)
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
                    self.uiWebView?.load(request)
                } else {
                    self.automationWebView?.load(request)
                }
            }
        }
    }
    
    // Navigate in automation webview (for remote control)
    func navigateInAutomationWebView(_ url: String) {
        DispatchQueue.main.async { [weak self] in
            if let urlObj = URL(string: url) {
                let request = URLRequest(url: urlObj)
                self?.automationWebView?.load(request)
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
        
        // Reset URL state immediately when modal closes
        resetURLState()
        
        dismiss(animated: true) {
            // Only call delegate method to avoid duplicate handleClose calls
            // The delegate (PassageSDK) will handle the close logic
            self.delegate?.webViewModalDidClose()
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
            
            // Cancel any ongoing animation
            if self.isAnimating {
                self.uiWebView.layer.removeAllAnimations()
                self.automationWebView.layer.removeAllAnimations()
                self.isAnimating = false
            }
            
            // If already showing UI webview, ensure visual state is correct
            if self.isShowingUIWebView {
                self.view.bringSubviewToFront(self.uiWebView)
                self.uiWebView.alpha = 1
                self.automationWebView.alpha = 0
                return
            }
            
            passageLogger.debug("[WEBVIEW] Switching to UI webview")
            self.isAnimating = true
            self.view.bringSubviewToFront(self.uiWebView)
            
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
                self.uiWebView.alpha = 1
                self.automationWebView.alpha = 0
            }, completion: { _ in
                self.isAnimating = false
                self.isShowingUIWebView = true
                self.onWebviewChange?("ui")
            })
        }
    }
    
    func showAutomationWebView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // In debug single-webview mode, automation webview is not created
            if self.debugSingleWebViewUrl != nil || self.automationWebView == nil {
                passageLogger.debug("[DEBUG MODE] Ignoring showAutomationWebView (automation webview unavailable)")
                return
            }
            
            // Cancel any ongoing animation
            if self.isAnimating {
                self.uiWebView.layer.removeAllAnimations()
                self.automationWebView.layer.removeAllAnimations()
                self.isAnimating = false
            }
            
            // If already showing automation webview, ensure visual state is correct
            if !self.isShowingUIWebView {
                self.view.bringSubviewToFront(self.automationWebView)
                self.automationWebView.alpha = 1
                self.uiWebView.alpha = 0
                return
            }
            
            passageLogger.debug("[WEBVIEW] Switching to automation webview")
            self.isAnimating = true
            self.view.bringSubviewToFront(self.automationWebView)
            
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
                self.automationWebView.alpha = 1
                self.uiWebView.alpha = 0
            }, completion: { _ in
                self.isAnimating = false
                self.isShowingUIWebView = false
                self.onWebviewChange?("automation")
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
    
    private func setupScreenshotAccessors() {
        guard let remoteControl = remoteControl else {
            passageLogger.debug("[WEBVIEW] No remote control available for screenshot setup")
            return
        }
        
        // Set screenshot accessors (matching React Native implementation)
        remoteControl.setScreenshotAccessors((
            getCurrentScreenshot: { [weak self] in
                return self?.currentScreenshot
            },
            getPreviousScreenshot: { [weak self] in
                return self?.previousScreenshot
            }
        ))
        
        // Set capture image function
        remoteControl.setCaptureImageFunction({ [weak self] in
            return await self?.captureScreenshot()
        })
        
        passageLogger.debug("[WEBVIEW] Screenshot accessors configured")
    }
    
    private func captureScreenshot() async -> String? {
        // Only capture screenshot if record flag is true (matching React Native)
        guard let remoteControl = remoteControl, remoteControl.getRecordFlag() else {
            passageLogger.debug("[WEBVIEW] Screenshot capture skipped - record flag is false")
            return nil
        }
        
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    continuation.resume(returning: nil)
                    return
                }
                
                // Capture screenshot of the automation webview (where the actual content is)
                let targetWebView = self.automationWebView ?? self.uiWebView
                
                guard let webView = targetWebView else {
                    passageLogger.error("[WEBVIEW] No webview available for screenshot capture")
                    continuation.resume(returning: nil)
                    return
                }
                
                passageLogger.debug("[WEBVIEW] Capturing screenshot of \(webView == self.automationWebView ? "automation" : "ui") webview")
                
                // Take screenshot using WKWebView's built-in screenshot functionality
                let config = WKSnapshotConfiguration()
                config.rect = webView.bounds
                
                webView.takeSnapshot(with: config) { [weak self] image, error in
                    if let error = error {
                        passageLogger.error("[WEBVIEW] Screenshot capture failed: \(error)")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    guard let image = image else {
                        passageLogger.error("[WEBVIEW] Screenshot capture returned nil image")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Convert to base64 string (matching React Native format)
                    guard let imageData = image.pngData() else {
                        passageLogger.error("[WEBVIEW] Failed to convert screenshot to PNG data")
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    let base64String = "data:image/png;base64," + imageData.base64EncodedString()
                    
                    // Update screenshot state - move current to previous, set new as current
                    self?.previousScreenshot = self?.currentScreenshot
                    self?.currentScreenshot = base64String
                    
                    passageLogger.debug("[WEBVIEW] Screenshot captured successfully: \(base64String.count) chars")
                    
                    continuation.resume(returning: base64String)
                }
            }
        }
    }
    
    // Set automation webview user agent (matches React Native implementation)
    func setAutomationUserAgent(_ userAgent: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            passageLogger.debug("[WEBVIEW] Setting automation user agent: \(userAgent)")
            self.automationWebView?.customUserAgent = userAgent
        }
    }
    
    // Set automation webview URL (matches React Native implementation)
    func setAutomationUrl(_ url: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            passageLogger.debug("[WEBVIEW] Setting automation URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
            
            if let urlObj = URL(string: url) {
                let request = URLRequest(url: urlObj)
                self.automationWebView?.load(request)
            }
        }
    }
    
    // Handle navigation state changes (like React Native implementation)
    private func handleNavigationStateChange(url: String, loading: Bool, webViewType: String) {
        passageLogger.debug("[NAVIGATION] State change - \(webViewType): \(passageLogger.truncateUrl(url, maxLength: 100)), loading: \(loading)")
        
        // Send browser state update to backend and handle screenshots/reinjection when loading is complete
        if !url.isEmpty {
            // Only capture screenshot and reinject when loading is false (page fully loaded)
            if !loading {
                // Handle injectScript command reinjection for record mode
                if webViewType == PassageConstants.WebViewTypes.automation {
                    // Send browser state to remote control (matches React Native implementation)
                    NotificationCenter.default.post(
                        name: .sendBrowserState,
                        object: nil,
                        userInfo: ["url": url, "webViewType": webViewType]
                    )
                    
                    // Call handleNavigationComplete directly (matches React Native implementation)
                    remoteControl?.handleNavigationComplete(url)
                    
                    passageLogger.debug("[NAVIGATION] Page loaded for \(webViewType), checking for reinjection")
                }
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
        
        // Show error to user
        let alert = UIAlertController(
            title: "Connection Timeout",
            message: "The page is taking too long to load. Please check your internet connection and try again.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.uiWebView.reload()
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.closeModal()
        })
        
        present(alert, animated: true)
    }
    
    private func showNavigationError(_ message: String) {
        let alert = UIAlertController(
            title: "Navigation Error",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
            self?.uiWebView.reload()
        })
        alert.addAction(UIAlertAction(title: "Close", style: .cancel) { [weak self] _ in
            self?.closeModal()
        })
        present(alert, animated: true)
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
        if let url = webView.url?.absoluteString {
            passageAnalytics.trackNavigationError(url: url, webViewType: webViewType, error: error.localizedDescription)
        }
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // Cancel timeout timer
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
        
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        passageLogger.error("Provisional navigation failed: \(error.localizedDescription)")
        
        // Get the attempted URL
        if let url = webView.url {
            passageLogger.error("Failed URL: \(url.absoluteString)")
            passageAnalytics.trackNavigationError(url: url.absoluteString, webViewType: webViewType, error: error.localizedDescription)
        }
        
        // Log more error details
        let nsError = error as NSError
        passageLogger.error("Error domain: \(nsError.domain), code: \(nsError.code)")
        passageLogger.error("Error userInfo: \(nsError.userInfo)")
        
        // Check for common issues
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                passageLogger.error("No internet connection")
            case NSURLErrorCannotFindHost:
                passageLogger.error("Cannot find host")
            case NSURLErrorSecureConnectionFailed:
                passageLogger.error("Secure connection failed - possible certificate issue")
            default:
                break
            }
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
                passageLogger.error("HTTP Error Response: \(httpResponse.statusCode)")
                // Don't allow navigation for error responses
                decisionHandler(.cancel)
                
                // Show error to user
                DispatchQueue.main.async { [weak self] in
                    self?.showNavigationError("Server returned error: \(httpResponse.statusCode)")
                }
                return
            }
        }
        
        decisionHandler(.allow)
    }
}

// MARK: - WKScriptMessageHandler
extension WebViewModalViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == PassageConstants.MessageHandlers.capacitorWebViewModal {
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
                    passageLogger.error("JavaScript Error: \(body["message"] ?? "Unknown error")")
                    if let source = body["source"] as? String {
                        passageLogger.error("  Source: \(source)")
                    }
                    if let line = body["line"] as? Int {
                        passageLogger.error("  Line: \(line)")
                    }
                    if let stack = body["stack"] as? String {
                        passageLogger.error("  Stack: \(stack)")
                    }
                case PassageConstants.MessageTypes.message:
                    // Handle window.passage.postMessage calls (matches Capacitor implementation)
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
