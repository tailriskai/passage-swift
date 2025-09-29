#if canImport(UIKit)
import UIKit
@preconcurrency import WebKit
import AuthenticationServices

extension WebViewModalViewController {

    // MARK: - OAuth Detection

    /// List of OAuth provider domains that require special handling
    private var oauthProviderDomains: [String] {
        return [
            // Google OAuth
            "accounts.google.com",
            "accounts.youtube.com",
            "myaccount.google.com",
            "oauth2.googleapis.com",

            // Facebook OAuth
            "www.facebook.com",
            "m.facebook.com",
            "facebook.com",
            "web.facebook.com",

            // Apple OAuth
            "appleid.apple.com",
            "signin.apple.com",

            // Microsoft OAuth
            "login.microsoftonline.com",
            "login.microsoft.com",
            "login.live.com",
            "account.microsoft.com",

            // GitHub OAuth
            "github.com",

            // Twitter/X OAuth
            "api.twitter.com",
            "twitter.com",
            "x.com",

            // LinkedIn OAuth
            "www.linkedin.com",
            "linkedin.com",

            // Generic OAuth endpoints
            "oauth.io",
            "auth0.com"
        ]
    }

    /// Check if a URL is an OAuth provider URL
    internal func isOAuthURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let host = url.host?.lowercased() else {
            return false
        }

        // Check if the host matches any OAuth provider domain
        for domain in oauthProviderDomains {
            if host == domain || host.hasSuffix(".\(domain)") {
                passageLogger.debug("[OAUTH] Detected OAuth URL: \(urlString)")
                return true
            }
        }

        // Check for common OAuth paths
        let oauthPaths = ["/oauth", "/auth", "/signin", "/login", "/authorize", "/connect"]
        let path = url.path.lowercased()
        for oauthPath in oauthPaths {
            if path.contains(oauthPath) {
                passageLogger.debug("[OAUTH] Detected OAuth path in URL: \(urlString)")
                return true
            }
        }

        return false
    }

    /// Check if the current navigation is part of an OAuth flow
    func isInOAuthFlow() -> Bool {
        // Check UI webview
        if let uiURL = uiWebView?.url?.absoluteString, isOAuthURL(uiURL) {
            return true
        }

        // Check automation webview
        if let autoURL = automationWebView?.url?.absoluteString, isOAuthURL(autoURL) {
            return true
        }

        return false
    }

    // MARK: - OAuth Configuration

    /// Get appropriate user agent for the given URL
    func getUserAgent(for urlString: String) -> String? {
        if isOAuthURL(urlString) {
            // Use default Safari user agent for OAuth flows
            passageLogger.info("[OAUTH] Using default Safari user agent for OAuth URL")
            return nil // nil means use the default WKWebView user agent
        } else if debugSingleWebViewUrl != nil || forceSimpleWebView {
            // Use custom user agent for debug mode
            return "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        } else {
            // Use stored user agent if available
            return automationUserAgent
        }
    }

    /// Configure webview for OAuth flow
    func configureForOAuth(_ webView: WKWebView, url: String) {
        if isOAuthURL(url) {
            passageLogger.info("[OAUTH] Configuring webview for OAuth flow")

            // Keep custom user agent - don't change it for OAuth
            // Ensure cookies are enabled and persistent
            webView.configuration.websiteDataStore = WKWebsiteDataStore.default()

            passageLogger.debug("[OAUTH] WebView configured for OAuth with custom user agent preserved")
        }
    }

    // MARK: - External URL Scheme Handling

    /// Check if URL should be opened externally (app-to-app OAuth)
    internal func shouldOpenExternally(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""

        // List of schemes that should open externally for OAuth
        let externalSchemes = [
            "googlechrome",
            "googlechromes",
            "fb",
            "fbauth2",
            "twitter",
            "linkedin",
            "github"
        ]

        if externalSchemes.contains(scheme) {
            passageLogger.info("[OAUTH] External OAuth scheme detected: \(scheme)")
            return true
        }

        // Check for universal links
        if scheme == "https" || scheme == "http" {
            let host = url.host?.lowercased() ?? ""
            // Some OAuth providers use app links
            if host.contains("app.link") || host.contains("deep.link") {
                passageLogger.info("[OAUTH] Universal link detected for OAuth: \(host)")
                return true
            }
        }

        return false
    }

    /// Handle external OAuth URL
    internal func handleExternalOAuthURL(_ url: URL) {
        passageLogger.info("[OAUTH] Attempting to open external OAuth URL: \(url.absoluteString)")

        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    passageLogger.info("[OAUTH] Successfully opened external OAuth URL")
                } else {
                    passageLogger.error("[OAUTH] Failed to open external OAuth URL")
                }
            }
        } else {
            passageLogger.warn("[OAUTH] Cannot open external OAuth URL - app may not be installed")
            // Fallback to web-based OAuth if app is not available
            // The navigation will continue in the webview
        }
    }

    // MARK: - OAuth Popup Handling

    /// Handle OAuth popup window
    internal func handleOAuthPopup(for navigationAction: WKNavigationAction,
                                   windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url else {
            return nil
        }

        passageLogger.info("[OAUTH] Handling OAuth popup for URL: \(url.absoluteString)")

        // For OAuth popups, we'll load them in the current webview
        // This prevents popup blockers and keeps the OAuth flow in our control
        if isOAuthURL(url.absoluteString) {
            passageLogger.info("[OAUTH] Loading OAuth popup URL in current webview")

            // Determine which webview to use
            let targetWebView = isShowingUIWebView ? uiWebView : automationWebView

            // Load the OAuth URL in the current webview
            targetWebView?.load(navigationAction.request)

            // Return nil to prevent creating a new webview
            return nil
        }

        // For non-OAuth popups, allow default behavior
        return nil
    }

    // MARK: - OAuth JavaScript Configuration

    /// Check if JavaScript injection should be skipped for OAuth
    /// NOTE: Currently always returns false - we inject JS even for OAuth flows
    func shouldSkipJavaScriptInjection(for url: String) -> Bool {
        // JavaScript injection is now enabled for all URLs including OAuth
        // to maintain full SDK functionality during OAuth flows
        return false
    }

    /// Get OAuth-safe JavaScript configuration
    func getOAuthSafeConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()

        // Use default data store for OAuth (persistent cookies)
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        // Enable JavaScript (required for OAuth)
        configuration.preferences.javaScriptEnabled = true

        // Allow JavaScript to open windows (for OAuth popups)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Allow inline media playback (some OAuth providers use videos)
        configuration.allowsInlineMediaPlayback = true

        // Don't require user action for media playback
        configuration.mediaTypesRequiringUserActionForPlayback = []

        // Allow picture-in-picture (some OAuth providers might use it)
        if #available(iOS 14.0, *) {
            configuration.allowsPictureInPictureMediaPlayback = true
        }

        passageLogger.debug("[OAUTH] Created OAuth-safe configuration")

        return configuration
    }
}

// MARK: - ASWebAuthenticationSession Support

extension WebViewModalViewController {

    /// Use ASWebAuthenticationSession for OAuth when appropriate
    @available(iOS 12.0, *)
    func performOAuthWithAuthenticationSession(url: URL,
                                              callbackScheme: String?,
                                              completion: @escaping (URL?, Error?) -> Void) {
        passageLogger.info("[OAUTH] Starting ASWebAuthenticationSession for URL: \(url.absoluteString)")

        let session = ASWebAuthenticationSession(url: url,
                                                 callbackURLScheme: callbackScheme) { callbackURL, error in
            if let error = error {
                passageLogger.error("[OAUTH] ASWebAuthenticationSession error: \(error.localizedDescription)")
                completion(nil, error)
            } else if let callbackURL = callbackURL {
                passageLogger.info("[OAUTH] ASWebAuthenticationSession success with callback: \(callbackURL.absoluteString)")
                completion(callbackURL, nil)
            } else {
                passageLogger.warn("[OAUTH] ASWebAuthenticationSession completed with no callback URL")
                completion(nil, nil)
            }
        }

        if #available(iOS 13.0, *) {
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false // Use shared cookies
        }

        session.start()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

@available(iOS 13.0, *)
extension WebViewModalViewController: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return self.view.window ?? UIWindow()
    }
}

#endif