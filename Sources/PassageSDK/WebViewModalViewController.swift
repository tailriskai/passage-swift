import UIKit
import WebKit

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
    
    // Dual webviews
    private var uiWebView: WKWebView!
    private var automationWebView: WKWebView!
    
    private var currentURL: String = ""
    private var isShowingUIWebView: Bool = true
    private var isAnimating: Bool = false
    
    // Store pending user action command
    private var pendingUserActionCommand: PendingUserActionCommand?
    
    // Store initial URL to load after view appears
    private var initialURLToLoad: String?
    
    // Debug: force rendering just one webview with a predefined URL
    private let debugSingleWebViewUrl: String? = "https://google.com"
    // Temporary: force a simple, Capacitor-like single webview configuration
    private let forceSimpleWebView: Bool = true
    
    // Navigation timeout timer
    private var navigationTimeoutTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupUI()
        setupWebViews()
        
        // Configure navigation bar appearance
        if let navigationBar = navigationController?.navigationBar {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .white
            appearance.shadowColor = .clear
            
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
        }
        
        // Keep navigation bar but leave title empty
        navigationItem.title = ""

        // If in debug single-webview mode, we've already created and loaded it in setupWebViews.
        if let debugUrl = debugSingleWebViewUrl, !debugUrl.isEmpty {
            passageLogger.debug("[DEBUG MODE] viewDidLoad short-circuit; single webview already loading: \(passageLogger.truncateUrl(debugUrl, maxLength: 100))")
            return
        }

        // Parity with Capacitor: if `url` was set, load it immediately
        if !url.isEmpty {
            passageLogger.debug("viewDidLoad: loading provided url: \(passageLogger.truncateUrl(url, maxLength: 100))")
            loadURL(url)
        } else if let pending = initialURLToLoad {
            // If a URL was queued before view was ready, load it now
            passageLogger.debug("viewDidLoad: loading pending initialURLToLoad: \(passageLogger.truncateUrl(pending, maxLength: 100))")
            initialURLToLoad = nil
            loadURL(pending)
        }

        // Keep behavior minimal like Capacitor; UI webview loads in viewDidLoad
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Load initial URL if it was set before view appeared
        if let urlToLoad = initialURLToLoad {
            passageLogger.debug("View appeared, loading deferred URL: \(passageLogger.truncateUrl(urlToLoad, maxLength: 100))")
            passageLogger.debug("View frame: \(view.frame)")
            passageLogger.debug("UIWebView frame: \(uiWebView.frame)")
            passageLogger.debug("Window: \(view.window != nil ? "exists" : "nil")")
            
            initialURLToLoad = nil
            loadURL(urlToLoad)
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
    }
    
    private func setupUI() {
        // Set background color to match web app container (light gray)
        view.backgroundColor = PassageConstants.Colors.webViewBackground
        
        // Add close button for reliability
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(closeModal)
        )
    }
    
    private func createWebView(webViewType: String) -> WKWebView {
        // Create WKWebView configuration
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()
        
        // Enable JavaScript (required)
        configuration.preferences.javaScriptEnabled = true
        
        // Allow inline media playback
        configuration.allowsInlineMediaPlayback = true
        
        // Keep config minimal (match Capacitor behavior for https loads)
        
        // Set up messaging — in simple mode, skip all scripts/handlers to avoid CSP/conflicts
        if !forceSimpleWebView && debugSingleWebViewUrl == nil {
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
                uiWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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
                                    passageLogger.debug("[DEBUG MODE] Loaded HTML bytes: \(html.count). Rendering inline for visibility test.")
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
            uiWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            // Automation webview constraints (same as UI)
            automationWebView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            automationWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            automationWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            automationWebView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        
        // Initially show UI webview, hide automation webview
        uiWebView.alpha = 1
        automationWebView.alpha = 0
        view.bringSubviewToFront(uiWebView)
    }
    
    private func createPassageScript(for webViewType: String) -> String {
        return """
        // Passage \(webViewType.capitalized) WebView Script
        (function() {
          // Prevent multiple initialization
          if (window.passage && window.passage.initialized) {
            console.log('[Passage] Already initialized, skipping');
            return;
          }
          
          // Initialize passage object
          window.passage = {
            initialized: true,
            webViewType: '\(webViewType)',
            
            // Core messaging functionality
            postMessage: function(data) {
              try {
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'message',
                    data: data,
                    webViewType: '\(webViewType)',
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
                    webViewType: '\(webViewType)',
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
                    webViewType: '\(webViewType)',
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
                    webViewType: '\(webViewType)',
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
              return '\(webViewType)';
            },
            
            isAutomationWebView: function() {
              return '\(webViewType)' === 'automation';
            },
            
            isUIWebView: function() {
              return '\(webViewType)' === 'ui';
            }
          };
          
          console.log('[Passage] \(webViewType.capitalized) webview script initialized');
        })();
        """
    }
    
    func loadURL(_ urlString: String) {
        // In debug single-webview mode, ignore external loads that aren't the debug URL
        if let debugUrl = debugSingleWebViewUrl, !debugUrl.isEmpty, urlString != debugUrl {
            passageLogger.debug("[DEBUG MODE] Ignoring external loadURL: \(passageLogger.truncateUrl(urlString, maxLength: 100)) while forcing: \(passageLogger.truncateUrl(debugUrl, maxLength: 100))")
            return
        }

        currentURL = urlString
        
        // Match Capacitor behavior: allow loading immediately even before window is attached
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let url = URL(string: urlString) {
                passageLogger.debug("Loading URL in WebView: \(passageLogger.truncateUrl(urlString, maxLength: 100))")
                let request = URLRequest(url: url)
                self.uiWebView.stopLoading()
                self.uiWebView.load(request)
            }
        }
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
        dismiss(animated: true) {
            self.onClose?()
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
        DispatchQueue.main.async { [weak self] in
            self?.automationWebView?.evaluateJavaScript(script, completionHandler: completion)
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
            
            passageLogger.webView("showUIWebView called - current state: isShowingUIWebView=\(self.isShowingUIWebView), isAnimating=\(self.isAnimating)", webViewType: "ui")
            
            // Cancel any ongoing animation
            if self.isAnimating {
                passageLogger.webView("Cancelling ongoing animation", webViewType: "ui")
                self.uiWebView.layer.removeAllAnimations()
                self.automationWebView.layer.removeAllAnimations()
                self.isAnimating = false
            }
            
            // If already showing UI webview, ensure visual state is correct
            if self.isShowingUIWebView {
                passageLogger.webView("Already showing UI webview, forcing visual state", webViewType: "ui")
                self.view.bringSubviewToFront(self.uiWebView)
                self.uiWebView.alpha = 1
                self.automationWebView.alpha = 0
                return
            }
            
            passageLogger.webView("Animating to UI webview", webViewType: "ui")
            self.isAnimating = true
            self.view.bringSubviewToFront(self.uiWebView)
            
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
                self.uiWebView.alpha = 1
                self.automationWebView.alpha = 0
            }, completion: { _ in
                self.isAnimating = false
                self.isShowingUIWebView = true
                passageLogger.webView("Animation to UI webview complete", webViewType: "ui")
            })
        }
    }
    
    func showAutomationWebView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            // In debug single-webview mode, automation webview is not created
            if self.debugSingleWebViewUrl != nil || self.automationWebView == nil {
                passageLogger.webView("[DEBUG MODE] Ignoring showAutomationWebView (automation webview unavailable)", webViewType: "automation")
                return
            }
            
            passageLogger.webView("showAutomationWebView called - current state: isShowingUIWebView=\(self.isShowingUIWebView), isAnimating=\(self.isAnimating)", webViewType: "automation")
            
            // Cancel any ongoing animation
            if self.isAnimating {
                passageLogger.webView("Cancelling ongoing animation", webViewType: "automation")
                self.uiWebView.layer.removeAllAnimations()
                self.automationWebView.layer.removeAllAnimations()
                self.isAnimating = false
            }
            
            // If already showing automation webview, ensure visual state is correct
            if !self.isShowingUIWebView {
                passageLogger.webView("Already showing automation webview, forcing visual state", webViewType: "automation")
                self.view.bringSubviewToFront(self.automationWebView)
                self.automationWebView.alpha = 1
                self.uiWebView.alpha = 0
                return
            }
            
            passageLogger.webView("Animating to automation webview", webViewType: "automation")
            self.isAnimating = true
            self.view.bringSubviewToFront(self.automationWebView)
            
            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
                self.automationWebView.alpha = 1
                self.uiWebView.alpha = 0
            }, completion: { _ in
                self.isAnimating = false
                self.isShowingUIWebView = false
                passageLogger.webView("Animation to automation webview complete", webViewType: "automation")
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
    
    // MARK: - UIAdaptivePresentationControllerDelegate
    
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Handle pull-down dismissal
        onClose?()
        delegate?.webViewModalDidClose()
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
        // Check if navigation is still in progress
        passageLogger.debug("Checking navigation status...")
        
        // Check if page is loading
        webView.evaluateJavaScript("document.readyState") { result, _ in
            if let state = result as? String {
                passageLogger.debug("Navigation check - Document state: \(state)")
            }
        }
        
        // Check current URL
        if let url = webView.url {
            passageLogger.debug("Navigation check - Current URL: \(url.absoluteString)")
        } else {
            passageLogger.warn("Navigation check - No URL loaded")
        }
        
        // Check if page has any content
        webView.evaluateJavaScript("document.body ? document.body.children.length : -1") { result, _ in
            if let count = result as? Int {
                passageLogger.debug("Navigation check - Body children count: \(count)")
            }
        }
        
        // Check loading state
        passageLogger.debug("Navigation check - isLoading: \(webView.isLoading)")
    }
}

// MARK: - WKNavigationDelegate
extension WebViewModalViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        passageLogger.webView("Navigation started", webViewType: webViewType)
        
        // Cancel any existing timeout timer
        navigationTimeoutTimer?.invalidate()
        
        // Start a new timeout timer (15 seconds for better UX)
        navigationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.handleNavigationTimeout(for: webView)
        }
        
        // Check navigation status after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkNavigationStatus(for: webView)
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Cancel timeout timer
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
        
        if let url = webView.url {
            let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
            passageLogger.navigation("Navigation finished: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
            
            // Debug: Check if page has content
            webView.evaluateJavaScript("document.body.innerHTML.length") { result, error in
                if let length = result as? Int {
                    passageLogger.debug("Page content length: \(length) characters")
                    if length < 100 {
                        passageLogger.warn("Page appears to have very little content")
                        // Try to get the actual content for debugging
                        webView.evaluateJavaScript("document.body.innerHTML.substring(0, 500)") { html, _ in
                            if let html = html as? String {
                                passageLogger.debug("Page HTML preview: \(html)")
                            }
                        }
                    }
                } else if let error = error {
                    passageLogger.error("Error checking page content: \(error.localizedDescription)")
                }
            }
            
            // Check document ready state
            webView.evaluateJavaScript("document.readyState") { result, _ in
                if let state = result as? String {
                    passageLogger.debug("Document ready state: \(state)")
                }
            }
            
            // Check if window.passage is available
            webView.evaluateJavaScript("typeof window.passage") { result, _ in
                if let type = result as? String {
                    passageLogger.debug("window.passage type: \(type)")
                }
            }
            
            // Check for any JavaScript errors
            webView.evaluateJavaScript("window.onerror ? 'has error handler' : 'no error handler'") { result, _ in
                if let status = result as? String {
                    passageLogger.debug("Window error handler: \(status)")
                }
            }
            
            // Send delegate callback for both webviews
            delegate?.webViewModal(didNavigateTo: url)
            
            // Inject JavaScript to notify about navigation finished
            let navigationData = """
            {
                "type": "navigation_finished",
                "url": "\(url.absoluteString)",
                "webViewType": "\(webViewType)",
                "timestamp": \(Date().timeIntervalSince1970 * 1000)
            }
            """
            
            let script = """
            (function() {
                if (window.passage && window.passage.postMessage) {
                    console.log('[WebViewModal] Sending navigation_finished via window.passage.postMessage');
                    window.passage.postMessage(\(navigationData));
                } else {
                    console.warn('[WebViewModal] window.passage.postMessage not available');
                }
            })();
            """
            
            // Inject into the webview that finished navigation
            webView.evaluateJavaScript(script) { result, error in
                if let error = error {
                    passageLogger.error("Error injecting navigation finished notification: \(error.localizedDescription)")
                } else {
                    passageLogger.debug("Successfully notified JavaScript about navigation finished")
                }
            }
            
            // Also send page loaded event with webview type info
            let pageLoadedData: [String: Any] = [
                "type": PassageConstants.MessageTypes.pageLoaded,
                "url": url.absoluteString,
                "timestamp": Date().timeIntervalSince1970 * 1000,
                "webViewType": webViewType
            ]
            
            // Call the onMessage handler directly
            onMessage?(pageLoadedData)
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Cancel timeout timer
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil
        
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        passageLogger.webView("Navigation failed: \(error.localizedDescription)", webViewType: webViewType)
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
                    fallthrough
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
