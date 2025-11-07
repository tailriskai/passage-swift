#if canImport(UIKit)
import UIKit
@preconcurrency import WebKit

extension WebViewModalViewController {

    func createWebView(webViewType: String) -> PassageWKWebView {
        passageLogger.info("[WEBVIEW] ========== CREATING WEBVIEW ==========")
        passageLogger.info("[WEBVIEW] WebView type: \(webViewType)")
        passageLogger.info("[WEBVIEW] Force simple webview: \(forceSimpleWebView)")
        passageLogger.info("[WEBVIEW] Debug URL: \(debugSingleWebViewUrl ?? "nil")")

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        if #available(iOS 14.0, *) {
            passageLogger.debug("[WEBVIEW] JavaScript enabled by default (iOS 14+)")
        } else {
            configuration.preferences.javaScriptEnabled = true
            passageLogger.debug("[WEBVIEW] JavaScript enabled: true (iOS 13)")
        }

        // Enable JavaScript to open windows automatically (for OAuth popups)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        passageLogger.debug("[WEBVIEW] JavaScript can open windows automatically: true")

        configuration.allowsInlineMediaPlayback = true
        passageLogger.debug("[WEBVIEW] Inline media playback allowed: true")

        if !forceSimpleWebView && debugSingleWebViewUrl == nil {
            passageLogger.info("[WEBVIEW] Setting up message handlers and scripts")
            let userContentController = WKUserContentController()

            userContentController.add(self, name: PassageConstants.MessageHandlers.passageWebView)

            let passageScript = createPassageScript(for: webViewType)
            let userScript = WKUserScript(
                source: passageScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            userContentController.addUserScript(userScript)

            let consoleScript = """
            (function() {
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

                window.addEventListener('error', function(event) {
                    const isWeakMapError = event.message && event.message.includes('WeakMap');

                    if (isWeakMapError) {
                        window.PASSAGE_INTERNAL_LOGGER.error('[Passage] WeakMap error detected:', event.message);
                        window.PASSAGE_INTERNAL_LOGGER.error('[Passage] This may be caused by global JavaScript injection timing');
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

                window.addEventListener('unhandledrejection', function(event) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Unhandled promise rejection:', event.reason);
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

        let webView = PassageWKWebView(frame: .zero, configuration: configuration)

        // User agent configuration
        if webViewType == PassageConstants.WebViewTypes.automation {
            // Apply automation user agent regardless of OAuth
            if automationUserAgent != nil {
                webView.customUserAgent = automationUserAgent
                passageLogger.debug("[WEBVIEW] Applied stored user agent to automation webview: \(automationUserAgent ?? "")")
            }
        } else if debugSingleWebViewUrl != nil || forceSimpleWebView {
            webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        }

        webView.navigationDelegate = self
        webView.uiDelegate = self // Set UI delegate for popup handling
        webView.translatesAutoresizingMaskIntoConstraints = false

        webView.backgroundColor = .white
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .white

        webView.scrollView.minimumZoomScale = 1.0
        webView.scrollView.maximumZoomScale = 1.0
        webView.scrollView.bouncesZoom = false

        if webViewType == PassageConstants.WebViewTypes.automation {
            webView.allowsBackForwardNavigationGestures = true
            passageLogger.debug("[WEBVIEW] Enabled back/forward navigation gestures for automation webview")
        } else {
            webView.allowsBackForwardNavigationGestures = false
        }

        if #available(iOS 16.4, *) {
            webView.isInspectable = true
            passageLogger.debug("WebView inspection enabled for iOS 16.4+")
        } else {
            #if DEBUG
            webView.perform(Selector(("setInspectable:")), with: true)
            passageLogger.debug("WebView inspection enabled via legacy method")
            #endif
        }

    webView.tag = webViewType == PassageConstants.WebViewTypes.automation ? 2 : 1

    webView.addObserver(self, forKeyPath: #keyPath(WKWebView.url), options: [.new, .old], context: nil)

    if let remoteControl = remoteControl {
        remoteControl.detectWebViewUserAgent(from: webView)
    }

    return webView
}

    func setupWebViews() {
        passageLogger.info("[WEBVIEW] ========== SETUP WEBVIEWS ==========")
        passageLogger.info("[WEBVIEW] Current state - UI: \(uiWebView != nil), Automation: \(automationWebView != nil)")
        passageLogger.info("[WEBVIEW] Superviews - UI: \(uiWebView?.superview != nil), Automation: \(automationWebView?.superview != nil)")

        if uiWebView != nil && automationWebView != nil && uiWebView.superview != nil && automationWebView.superview != nil {
            passageLogger.info("[WEBVIEW] WebViews already created and active, skipping setup")
            return
        }

        if uiWebView != nil || automationWebView != nil {
            passageLogger.info("[WEBVIEW] Cleaning up partially released WebViews before recreation")
            releaseWebViews()
        }

        if forceSimpleWebView || (debugSingleWebViewUrl != nil) {
            let initialUrl = debugSingleWebViewUrl
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

            if let urlString = initialUrl, let testUrl = URL(string: urlString) {
                var req = URLRequest(url: testUrl)
                req.httpMethod = "HEAD"
                URLSession.shared.dataTask(with: req) { _, response, error in
                    if let error = error {
                        passageLogger.error("[DEBUG MODE] URLSession probe error: \(error.localizedDescription)")
                    } else if let http = response as? HTTPURLResponse {
                        passageLogger.debug("[DEBUG MODE] URLSession probe status: \(http.statusCode) for \(passageLogger.truncateUrl(testUrl.absoluteString, maxLength: 100))")
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                if let urlString = initialUrl {
                    self?.loadURL(urlString)
                } else if let sdkUrl = self?.url, !sdkUrl.isEmpty {
                    self?.loadURL(sdkUrl)
                }
            }
            return
        }

        createHeaderContainer()

        uiWebView = createWebView(webViewType: PassageConstants.WebViewTypes.ui)
        automationWebView = createWebView(webViewType: PassageConstants.WebViewTypes.automation)

        view.addSubview(uiWebView)
        view.addSubview(automationWebView)

        // 🔑 RECORD MODE: Save reference to automation webview bottom constraint for marginBottom updates
        let automationBottom = automationWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -marginBottom)
        automationWebViewBottomConstraint = automationBottom

        NSLayoutConstraint.activate([
            uiWebView.topAnchor.constraint(equalTo: headerContainer!.bottomAnchor),
            uiWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            uiWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            uiWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),

            automationWebView.topAnchor.constraint(equalTo: headerContainer!.bottomAnchor),
            automationWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            automationWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            automationBottom
        ])

        uiWebView.alpha = 1
        automationWebView.alpha = 0
        view.bringSubviewToFront(uiWebView)

        automationWebView.shouldPreventFirstResponder = true
        uiWebView.shouldPreventFirstResponder = false

        if let header = headerContainer {
            view.bringSubviewToFront(header)
        }

        updateBackButtonVisibility()
    }

    func generateGlobalJavaScript() -> String {
        guard let remoteControl = remoteControl else {
            passageLogger.debug("[WEBVIEW] No remote control available for global JavaScript")
            return ""
        }

        let globalScript = remoteControl.getGlobalJavascript()
        passageLogger.info("[WEBVIEW] Global JavaScript retrieved: \(globalScript.isEmpty ? "EMPTY" : "\(globalScript.count) chars")")

        if !globalScript.isEmpty {
            let preview = String(globalScript.prefix(200))
            passageLogger.debug("[WEBVIEW] Global JavaScript preview: \(preview)...")
        }

        if globalScript.isEmpty {
            return ""
        }

        return """
        (function() {
            'use strict';

            if (typeof window === 'undefined') {
                window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Global JavaScript executed outside window context');
                return false;
            }

            function createSafeExecutionContext() {
                const OriginalWeakMap = window.WeakMap;

                function SafeWeakMap(iterable) {
                    const instance = new OriginalWeakMap(iterable);
                    const primitiveKeyMap = new Map();

                    const originalSet = instance.set.bind(instance);
                    const originalGet = instance.get.bind(instance);
                    const originalHas = instance.has.bind(instance);
                    const originalDelete = instance.delete.bind(instance);

                    instance.set = function(key, value) {
                        if (key === null || key === undefined || (typeof key !== 'object' && typeof key !== 'function' && typeof key !== 'symbol')) {
                            window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] WeakMap: Invalid key type, using fallback storage:', typeof key, key);
                            primitiveKeyMap.set(key, value);
                            return instance;
                        }
                        return originalSet(key, value);
                    };

                    instance.get = function(key) {
                        if (key === null || key === undefined || (typeof key !== 'object' && typeof key !== 'function' && typeof key !== 'symbol')) {
                            return primitiveKeyMap.get(key);
                        }
                        return originalGet(key);
                    };

                    instance.has = function(key) {
                        if (key === null || key === undefined || (typeof key !== 'object' && typeof key !== 'function' && typeof key !== 'symbol')) {
                            return primitiveKeyMap.has(key);
                        }
                        return originalHas(key);
                    };

                    instance.delete = function(key) {
                        if (key === null || key === undefined || (typeof key !== 'object' && typeof key !== 'function' && typeof key !== 'symbol')) {
                            return primitiveKeyMap.delete(key);
                        }
                        return originalDelete(key);
                    };

                    return instance;
                }

                Object.setPrototypeOf(SafeWeakMap, OriginalWeakMap);
                SafeWeakMap.prototype = OriginalWeakMap.prototype;

                return SafeWeakMap;
            }

            try {
                const SafeWeakMap = createSafeExecutionContext();
                const originalWeakMap = window.WeakMap;

                window.WeakMap = SafeWeakMap;

                window.PASSAGE_INTERNAL_LOGGER.info('[Passage] Executing global script with WeakMap protection');

                (function() {
                    \(globalScript)
                }).call(window);

                setTimeout(function() {
                    window.WeakMap = originalWeakMap;
                    window.PASSAGE_INTERNAL_LOGGER.info('[Passage] WeakMap protection removed, original WeakMap restored');
                }, 1000);

                return true;
            } catch (error) {
                window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error executing global JavaScript:', error);
                window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error stack:', error.stack);

                if (typeof originalWeakMap !== 'undefined') {
                    window.WeakMap = originalWeakMap;
                }
                return false;
            }
        })();
        """
    }

    func createPassageScript(for webViewType: String) -> String {
        if webViewType == PassageConstants.WebViewTypes.automation {
            let globalScript = generateGlobalJavaScript()
            if globalScript.isEmpty {
              passageLogger.info("[WEBVIEW] ℹ️ No global JavaScript to inject in automation webview (empty script)")
            }
            return """
            (function() {
              if (!window.PASSAGE_INTERNAL_LOGGER) {
                window.PASSAGE_INTERNAL_LOGGER = {
                  info: console.info.bind(console),
                  warn: console.warn.bind(console),
                  error: console.error.bind(console),
                };
              }

              window.PASSAGE_INTERNAL_LOGGER.info('[Passage] Automation webview script starting...');

              if (window.passage && window.passage.initialized) {
                window.PASSAGE_INTERNAL_LOGGER.info('[Passage] Already initialized, skipping');
                return;
              }

              window.PASSAGE_INTERNAL_LOGGER.info('[Passage] Initializing window.passage for automation webview');
              window.passage = {
                initialized: true,
                webViewType: 'automation',

                createLogger: function() {
                  return {
                    info: function() {
                      return window.PASSAGE_INTERNAL_LOGGER.info.apply(this, arguments);
                    },
                    warn: function() {
                      return window.PASSAGE_INTERNAL_LOGGER.warn.apply(this, arguments);
                    },
                    error: function() {
                      return window.PASSAGE_INTERNAL_LOGGER.error.apply(this, arguments);
                    },
                  };
                },

                postMessage: function(data) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] postMessage called with data:', data);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] Sending message via webkit handler');
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'message',
                        data: data,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] Message sent successfully');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available');
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] window.webkit:', typeof window.webkit);
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] window.webkit.messageHandlers:', typeof window.webkit?.messageHandlers);
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] passageWebView handler:', typeof window.webkit?.messageHandlers?.passageWebView);
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error posting message:', error);
                  }
                },


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
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for navigation');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error navigating:', error);
                  }
                },

                close: function() {
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'close',
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for close');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error closing:', error);
                  }
                },

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
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for setTitle');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error setting title:', error);
                  }
                },

                getWebViewType: function() {
                  return 'automation';
                },

                isAutomationWebView: function() {
                  return true;
                },

                isUIWebView: function() {
                  return false;
                },

                captureScreenshot: function() {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] captureScreenshot called');
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'captureScreenshot',
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] Screenshot capture request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for screenshot capture');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error capturing screenshot:', error);
                  }
                },

                sendToBackend: function(apiPath, data, headers) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] sendToBackend called with apiPath:', apiPath);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      const message = {
                        type: 'sendToBackend',
                        apiPath: apiPath,
                        data: data,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      };

                      if (headers) {
                        message.headers = headers;
                      }

                      window.webkit.messageHandlers.passageWebView.postMessage(message);
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] sendToBackend request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for sendToBackend');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error in sendToBackend:', error);
                  }
                },

                sendToSession: function(path, data, headers) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] sendToSession called with path:', path);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      const message = {
                        type: 'sendToSession',
                        path: path,
                        data: data,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      };

                      if (headers) {
                        message.headers = headers;
                      }

                      window.webkit.messageHandlers.passageWebView.postMessage(message);
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] sendToSession request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for sendToSession');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error in sendToSession:', error);
                  }
                },

                switchWebview: function() {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] switchWebview called');
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'switchWebview',
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] switchWebview request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for switchWebview');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error switching webview:', error);
                  }
                },

                showBottomSheetModal: function(params) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] showBottomSheetModal called with params:', params);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'showBottomSheet',
                        title: params.title,
                        description: params.description || null,
                        points: params.points || null,
                        closeButtonText: params.closeButtonText || null,
                        showInput: params.showInput || false,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] showBottomSheetModal request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for showBottomSheetModal');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error showing bottom sheet:', error);
                  }
                },

                changeAutomationUserAgent: function(userAgent) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] changeAutomationUserAgent called with:', userAgent);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'changeAutomationUserAgent',
                        userAgent: userAgent,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] changeAutomationUserAgent request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for changeAutomationUserAgent');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error changing user agent:', error);
                  }
                },

                openLink: function(url) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] openLink called with:', url);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'openLink',
                        url: url,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] openLink request sent for URL:', url);
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for openLink');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error opening link:', error);
                  }
                },

                setRedirectOnDoneCommand: function(enabled) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] setRedirectOnDoneCommand called with:', enabled);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'setRedirectOnDoneCommand',
                        enabled: enabled,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] setRedirectOnDoneCommand request sent:', enabled);
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for setRedirectOnDoneCommand');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error setting redirectOnDoneCommand:', error);
                  }
                },

                showBottomSheetWebsite: function(url) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] showBottomSheetWebsite called with:', url);
                  try {
                    if (!url || typeof url !== 'string') {
                      window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Invalid URL provided to showBottomSheetWebsite');
                      return;
                    }
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'showBottomSheetWebsite',
                        url: url,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] showBottomSheetWebsite request sent for URL:', url);
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for showBottomSheetWebsite');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error showing bottom sheet website:', error);
                  }
                },

                preloadBottomSheetWebsite: function(url) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] preloadBottomSheetWebsite called with:', url);
                  try {
                    if (!url || typeof url !== 'string') {
                      window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Invalid URL provided to preloadBottomSheetWebsite');
                      return;
                    }
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'preloadBottomSheetWebsite',
                        url: url,
                        webViewType: 'automation',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] preloadBottomSheetWebsite request sent for URL:', url);
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for preloadBottomSheetWebsite');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error preloading bottom sheet website:', error);
                  }
                }
              };

              (function() {
                const originalPushState = window.history.pushState;
                const originalReplaceState = window.history.replaceState;

                window.history.pushState = function() {
                  originalPushState.apply(window.history, arguments);
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] pushState navigation to:', window.location.href);
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
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] replaceState navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'replaceState',
                    url: window.location.href,
                    webViewType: 'automation',
                    timestamp: Date.now()
                  });
                };

                window.addEventListener('popstate', function(event) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] popstate navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'popstate',
                    url: window.location.href,
                    webViewType: 'automation',
                    timestamp: Date.now()
                  });
                });

                window.addEventListener('hashchange', function(event) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] hashchange navigation to:', window.location.href);
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

              window.PASSAGE_INTERNAL_LOGGER.info('[Passage] Automation webview script initialized successfully');
              window.PASSAGE_INTERNAL_LOGGER.info('[Passage] window.passage.initialized:', window.passage.initialized);
              window.PASSAGE_INTERNAL_LOGGER.info('[Passage] window.passage.webViewType:', window.passage.webViewType);

              \(globalScript)
            })();
            """
        } else {
            return """
            (function() {
              if (!window.PASSAGE_INTERNAL_LOGGER) {
                window.PASSAGE_INTERNAL_LOGGER = {
                  info: console.info.bind(console),
                  warn: console.warn.bind(console),
                  error: console.error.bind(console),
                };
              }
              if (window.passage && window.passage.initialized) {
                window.PASSAGE_INTERNAL_LOGGER.info('[Passage] Already initialized, skipping');
                return;
              }

              window.passage = {
                initialized: true,
                webViewType: 'ui',

                createLogger: function() {
                  return {
                    info: function() {
                      return window.PASSAGE_INTERNAL_LOGGER.info.apply(this, arguments);
                    },
                    warn: function() {
                      return window.PASSAGE_INTERNAL_LOGGER.warn.apply(this, arguments);
                    },
                    error: function() {
                      return window.PASSAGE_INTERNAL_LOGGER.error.apply(this, arguments);
                    },
                  };
                },

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
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error posting message:', error);
                  }
                },

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
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for navigation');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error navigating:', error);
                  }
                },

                close: function() {
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'close',
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for close');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error closing:', error);
                  }
                },

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
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for setTitle');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error setting title:', error);
                  }
                },

                getWebViewType: function() {
                  return 'ui';
                },

                isAutomationWebView: function() {
                  return false;
                },

                isUIWebView: function() {
                  return true;
                },

                captureScreenshot: function() {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] captureScreenshot called');
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'captureScreenshot',
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] Screenshot capture request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for screenshot capture');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error capturing screenshot:', error);
                  }
                },

                sendToBackend: function(apiPath, data, headers) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] sendToBackend called with apiPath:', apiPath);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      const message = {
                        type: 'sendToBackend',
                        apiPath: apiPath,
                        data: data,
                        webViewType: 'ui',
                        timestamp: Date.now()
                      };

                      if (headers) {
                        message.headers = headers;
                      }

                      window.webkit.messageHandlers.passageWebView.postMessage(message);
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] sendToBackend request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for sendToBackend');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error in sendToBackend:', error);
                  }
                },

                sendToSession: function(path, data, headers) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] sendToSession called with path:', path);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      const message = {
                        type: 'sendToSession',
                        path: path,
                        data: data,
                        webViewType: 'ui',
                        timestamp: Date.now()
                      };

                      if (headers) {
                        message.headers = headers;
                      }

                      window.webkit.messageHandlers.passageWebView.postMessage(message);
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] sendToSession request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for sendToSession');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error in sendToSession:', error);
                  }
                },

                switchWebview: function() {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] switchWebview called');
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'switchWebview',
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] switchWebview request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for switchWebview');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error switching webview:', error);
                  }
                },

                showBottomSheetModal: function(params) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] showBottomSheetModal called with params:', params);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'showBottomSheet',
                        title: params.title,
                        description: params.description || null,
                        points: params.points || null,
                        closeButtonText: params.closeButtonText || null,
                        showInput: params.showInput || false,
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] showBottomSheetModal request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for showBottomSheetModal');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error showing bottom sheet:', error);
                  }
                },

                openLink: function(url) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] openLink called with:', url);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'openLink',
                        url: url,
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] openLink request sent for URL:', url);
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for openLink');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error opening link:', error);
                  }
                },

                enableKeyboard: function() {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] enableKeyboard called');
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'enableKeyboard',
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] enableKeyboard request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for enableKeyboard');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error enabling keyboard:', error);
                  }
                },

                disableKeyboard: function() {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] disableKeyboard called');
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'disableKeyboard',
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] disableKeyboard request sent');
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for disableKeyboard');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error disabling keyboard:', error);
                  }
                },

                setRedirectOnDoneCommand: function(enabled) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] setRedirectOnDoneCommand called with:', enabled);
                  try {
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'setRedirectOnDoneCommand',
                        enabled: enabled,
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] setRedirectOnDoneCommand request sent:', enabled);
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for setRedirectOnDoneCommand');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error setting redirectOnDoneCommand:', error);
                  }
                },

                showBottomSheetWebsite: function(url) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] showBottomSheetWebsite called with:', url);
                  try {
                    if (!url || typeof url !== 'string') {
                      window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Invalid URL provided to showBottomSheetWebsite');
                      return;
                    }
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'showBottomSheetWebsite',
                        url: url,
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] showBottomSheetWebsite request sent for URL:', url);
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for showBottomSheetWebsite');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error showing bottom sheet website:', error);
                  }
                },

                preloadBottomSheetWebsite: function(url) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] preloadBottomSheetWebsite called with:', url);
                  try {
                    if (!url || typeof url !== 'string') {
                      window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Invalid URL provided to preloadBottomSheetWebsite');
                      return;
                    }
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.passageWebView) {
                      window.webkit.messageHandlers.passageWebView.postMessage({
                        type: 'preloadBottomSheetWebsite',
                        url: url,
                        webViewType: 'ui',
                        timestamp: Date.now()
                      });
                      window.PASSAGE_INTERNAL_LOGGER.info('[Passage] preloadBottomSheetWebsite request sent for URL:', url);
                    } else {
                      window.PASSAGE_INTERNAL_LOGGER.warn('[Passage] Message handlers not available for preloadBottomSheetWebsite');
                    }
                  } catch (error) {
                    window.PASSAGE_INTERNAL_LOGGER.error('[Passage] Error preloading bottom sheet website:', error);
                  }
                }
              };

              (function() {
                const originalPushState = window.history.pushState;
                const originalReplaceState = window.history.replaceState;

                window.history.pushState = function() {
                  originalPushState.apply(window.history, arguments);
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] pushState navigation to:', window.location.href);
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
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] replaceState navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'replaceState',
                    url: window.location.href,
                    webViewType: 'ui',
                    timestamp: Date.now()
                  });
                };

                window.addEventListener('popstate', function(event) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] popstate navigation to:', window.location.href);
                  window.webkit.messageHandlers.passageWebView.postMessage({
                    type: 'clientNavigation',
                    navigationMethod: 'popstate',
                    url: window.location.href,
                    webViewType: 'ui',
                    timestamp: Date.now()
                  });
                });

                window.addEventListener('hashchange', function(event) {
                  window.PASSAGE_INTERNAL_LOGGER.info('[Passage] hashchange navigation to:', window.location.href);
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

              window.PASSAGE_INTERNAL_LOGGER.info('[Passage] UI webview script initialized with full window.passage object');
            })();
            """
        }
    }

    func setAutomationUserAgent(_ userAgent: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            passageLogger.debug("[WEBVIEW] Setting automation user agent: \(userAgent)")

            self.automationUserAgent = userAgent.isEmpty ? nil : userAgent

            if let automationWebView = self.automationWebView {
                automationWebView.customUserAgent = userAgent
                passageLogger.debug("[WEBVIEW] Applied user agent to existing automation webview")
            } else {
                passageLogger.debug("[WEBVIEW] Automation webview not yet created, user agent will be applied when created")
            }
        }
    }

    func changeAutomationUserAgentAndReload(_ userAgent: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            passageLogger.info("[WEBVIEW] Changing automation user agent and reloading: \(userAgent)")

            // Store the user agent so it persists until modal/session closes
            self.automationUserAgent = userAgent.isEmpty ? nil : userAgent

            guard let automationWebView = self.automationWebView else {
                passageLogger.error("[WEBVIEW] Cannot change user agent - automation webview does not exist")
                return
            }

            // Get current URL to reload
            guard let currentUrl = automationWebView.url?.absoluteString else {
                passageLogger.error("[WEBVIEW] Cannot reload - automation webview has no URL")
                return
            }

            // Apply new user agent
            automationWebView.customUserAgent = userAgent
            passageLogger.debug("[WEBVIEW] Applied new user agent to automation webview")

            // Reload the page with the new user agent
            if let url = URL(string: currentUrl) {
                let request = URLRequest(url: url)
                automationWebView.load(request)
                passageLogger.info("[WEBVIEW] Reloading automation webview with new user agent")
            } else {
                passageLogger.error("[WEBVIEW] Failed to create URL from: \(currentUrl)")
            }
        }
    }

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

    func updateGlobalJavaScript() {
        passageLogger.info("[WEBVIEW] 🔄 updateGlobalJavaScript() called")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                passageLogger.error("[WEBVIEW] Self is nil in updateGlobalJavaScript")
                return
            }

            let newGlobalScript = self.generateGlobalJavaScript()

            passageLogger.info("[WEBVIEW] Current automation webview exists: \(self.automationWebView != nil)")
            passageLogger.info("[WEBVIEW] New global script length: \(newGlobalScript.count) chars")

            if !newGlobalScript.isEmpty {
                passageLogger.info("[WEBVIEW] 🚀 Global JavaScript updated (\(newGlobalScript.count) chars), recreating automation webview")

                var currentUrl: String?
                if let automationWebView = self.automationWebView {
                    currentUrl = automationWebView.url?.absoluteString
                    passageLogger.debug("[WEBVIEW] Current automation webview URL: \(currentUrl ?? "nil")")
                }

                self.recreateAutomationWebView()

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

        if let oldAutomationWebView = automationWebView {
            oldAutomationWebView.removeFromSuperview()
        }

        automationWebView = createWebView(webViewType: PassageConstants.WebViewTypes.automation)

        view.addSubview(automationWebView)
        automationWebView.translatesAutoresizingMaskIntoConstraints = false

        guard let headerContainer = headerContainer else {
            passageLogger.error("[WEBVIEW] Header container is nil when recreating automation webview")
            return
        }

        NSLayoutConstraint.activate([
            automationWebView.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            automationWebView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            automationWebView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            automationWebView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])

        automationWebView.alpha = 0

        view.bringSubviewToFront(headerContainer)

        passageLogger.info("[WEBVIEW] Automation webview recreated successfully")
    }

    func releaseWebViews() {
        passageLogger.info("[WEBVIEW] 🗑️ Releasing WebView instances to free JavaScriptCore memory")
        passageLogger.info("[WEBVIEW] View controller instance: \(String(format: "%p", unsafeBitCast(self, to: Int.self)))")

        // Reset user agent when session closes
        automationUserAgent = nil
        passageLogger.debug("[WEBVIEW] Reset automation user agent on webview release")

        if Thread.isMainThread {
            performWebViewRelease()
        } else {
            DispatchQueue.main.sync { [weak self] in
                self?.performWebViewRelease()
            }
        }
    }

    private func performWebViewRelease() {
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

        if let uiWebView = self.uiWebView {
            uiWebView.loadHTMLString("", baseURL: nil)
            passageLogger.debug("[WEBVIEW] Force unloaded UI WebView content")
        }

        if let automationWebView = self.automationWebView {
            automationWebView.loadHTMLString("", baseURL: nil)
            passageLogger.debug("[WEBVIEW] Force unloaded automation WebView content")
        }

        self.uiWebView?.removeFromSuperview()
        self.automationWebView?.removeFromSuperview()
        passageLogger.debug("[WEBVIEW] WebViews removed from view hierarchy")

        self.uiWebView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        self.automationWebView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))

        self.uiWebView?.navigationDelegate = nil
        self.uiWebView?.uiDelegate = nil
        self.automationWebView?.navigationDelegate = nil
        self.automationWebView?.uiDelegate = nil

        self.uiWebView?.configuration.userContentController.removeAllUserScripts()
        self.uiWebView?.configuration.userContentController.removeAllScriptMessageHandlers()
        self.automationWebView?.configuration.userContentController.removeAllUserScripts()
        self.automationWebView?.configuration.userContentController.removeAllScriptMessageHandlers()

        self.uiWebView = nil
        self.automationWebView = nil
        passageLogger.debug("[WEBVIEW] WebView references set to nil")

        self.currentScreenshot = nil
        self.previousScreenshot = nil
        self.pendingUserActionCommand = nil

        self.navigationTimeoutTimer?.invalidate()
        self.navigationTimeoutTimer = nil

        passageLogger.info("[WEBVIEW] ✅ WebView instances fully released - JavaScriptCore memory should be freed")
    }

    func hasActiveWebViews() -> Bool {
        return uiWebView != nil || automationWebView != nil
    }

    func areWebViewsReady() -> Bool {
        passageLogger.debug("[WEBVIEW] Checking if WebViews are ready for script injection")

        guard let uiWebView = uiWebView, let automationWebView = automationWebView else {
            passageLogger.debug("[WEBVIEW] ❌ WebViews don't exist: uiWebView=\(uiWebView != nil), automationWebView=\(automationWebView != nil)")

            if isViewLoaded && view.window != nil {
                passageLogger.info("[WEBVIEW] View is loaded but webviews are nil - attempting to setup webviews")
                setupWebViews()

                if let _ = self.uiWebView, let _ = self.automationWebView {
                    passageLogger.info("[WEBVIEW] WebViews successfully created during ready check")
                    return areWebViewsReady()
                }
            }

            return false
        }

        guard uiWebView.superview != nil && automationWebView.superview != nil else {
            passageLogger.debug("[WEBVIEW] ❌ WebViews not in view hierarchy: uiWebView.superview=\(uiWebView.superview != nil), automationWebView.superview=\(automationWebView.superview != nil)")
            return false
        }

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
}
#endif
