#if canImport(UIKit)
import UIKit
@preconcurrency import WebKit

extension WebViewModalViewController {

    func loadURL(_ urlString: String) {
        passageLogger.info("[WEBVIEW] Loading URL: \(passageLogger.truncateUrl(urlString, maxLength: 100))")

        if let debugUrl = debugSingleWebViewUrl, !debugUrl.isEmpty, urlString != debugUrl {
            passageLogger.warn("[WEBVIEW DEBUG MODE] Ignoring external URL, forcing debug URL")
            return
        }

        currentURL = urlString

        guard let url = URL(string: urlString) else {
            passageLogger.error("[WEBVIEW] ❌ Invalid URL: \(urlString)")
            return
        }

        resetForNewSession()

        if uiWebView == nil || automationWebView == nil {
            passageLogger.warn("[WEBVIEW] WebViews not ready, storing URL to load later")
            initialURLToLoad = urlString
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                passageLogger.error("[WEBVIEW] Self is nil in loadURL")
                return
            }

            guard let webView = self.uiWebView else {
                passageLogger.error("[WEBVIEW] ❌ UI WebView is nil")
                self.initialURLToLoad = urlString
                return
            }

            // Log OAuth detection but keep custom user agent
            if self.isOAuthURL(urlString) {
                passageLogger.info("[OAUTH] Detected OAuth URL in UI webview, keeping custom user agent")
                // Keep the custom user agent for OAuth flows
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

    private func resetForNewSession() {
        passageLogger.info("[WEBVIEW] Resetting state for new session")

        pendingUserActionCommand = nil

        currentScreenshot = nil
        previousScreenshot = nil

        currentURL = ""
        initialURLToLoad = nil

        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil

        if !isShowingUIWebView {
            showUIWebView()
        }

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
            if let debugUrl = self.debugSingleWebViewUrl, !debugUrl.isEmpty, url != debugUrl {
                passageLogger.debug("[DEBUG MODE] Ignoring navigateTo: \(passageLogger.truncateUrl(url, maxLength: 100)) while forcing: \(passageLogger.truncateUrl(debugUrl, maxLength: 100))")
                return
            }
            if let urlObj = URL(string: url) {
                let request = URLRequest(url: urlObj)
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

    func navigateInAutomationWebView(_ url: String) {
        passageLogger.debug("[WEBVIEW] ========== NAVIGATE IN AUTOMATION WEBVIEW ==========")
        passageLogger.debug("[WEBVIEW] 🧭 navigateInAutomationWebView called with: \(passageLogger.truncateUrl(url, maxLength: 100))")
        passageLogger.debug("[WEBVIEW] Thread: \(Thread.isMainThread ? "Main" : "Background")")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                passageLogger.error("[WEBVIEW] ❌ Self is nil in navigateInAutomationWebView")
                return
            }

            passageLogger.debug("[WEBVIEW] Now on main thread, checking automation webview...")
            passageLogger.debug("[WEBVIEW] Automation webview exists: \(self.automationWebView != nil)")

            guard self.automationWebView != nil else {
                passageLogger.error("[WEBVIEW] ❌ Cannot navigate - automation webview is nil")
                passageLogger.debug("[WEBVIEW] View loaded: \(self.isViewLoaded)")
                passageLogger.debug("[WEBVIEW] View in window: \(self.view.window != nil)")

                if self.isViewLoaded && self.view.window != nil {
                    passageLogger.info("[WEBVIEW] 🔧 Attempting to setup webviews before navigation")
                    self.setupWebViews()

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
                passageLogger.info("[WEBVIEW] Navigating automation webview isLoading: \(self.automationWebView?.isLoading ?? false) current URL: \(self.automationWebView?.url?.absoluteString ?? "nil") new url: \(url)")
                passageLogger.debug("[WEBVIEW] Automation webview current URL: \(self.automationWebView?.url?.absoluteString ?? "nil")")
                passageLogger.debug("[WEBVIEW] Automation webview is loading: \(self.automationWebView?.isLoading ?? false)")

                self.intendedAutomationURL = url
                passageLogger.debug("[WEBVIEW] 📝 Stored intended automation URL: \(url)")

                // Log OAuth detection but keep custom user agent
                if self.isOAuthURL(url) {
                    passageLogger.info("[OAUTH] Detected OAuth URL in automation webview, keeping custom user agent")
                    // Keep the custom user agent for OAuth flows
                }

                let request = URLRequest(url: urlObj)
                self.automationWebView?.load(request)

                passageLogger.debug("[WEBVIEW] 🎯 AUTOMATION WEBVIEW LOAD REQUESTED!")
                passageLogger.debug("[WEBVIEW] URL: \(passageLogger.truncateUrl(url, maxLength: 100))")
                passageLogger.debug("[WEBVIEW] This should trigger WKNavigationDelegate methods")
            } else {
                passageLogger.error("[WEBVIEW] ❌ Invalid URL provided: \(url)")
            }
        }
    }

    func navigateInUIWebView(_ url: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            passageLogger.info("[WEBVIEW] Navigating UI webview to: \(url)")

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

    @objc func backButtonTappedWithAnimation() {
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

    @objc func backButtonTapped() {
        passageLogger.debug("[WEBVIEW] Back button tapped")

        if isBackNavigationDisabled {
            passageLogger.debug("[WEBVIEW] Back navigation is disabled - ignoring tap")
            return
        }

        guard let automationWebView = automationWebView, automationWebView.canGoBack else {
            passageLogger.debug("[WEBVIEW] Cannot go back - no history")
            return
        }

        isNavigatingFromBackButton = true
        passageLogger.debug("[WEBVIEW] Set isNavigatingFromBackButton flag - backend tracking will be skipped")

        DispatchQueue.main.async { [weak self] in
            automationWebView.goBack()
            passageLogger.debug("[WEBVIEW] Automation webview navigating back")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.updateBackButtonVisibility()
            }
        }
    }

    func updateBackButtonVisibility() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let backButton = self.backButton else { return }

            let isAutomationVisible = !self.isShowingUIWebView
            let hasHistory = self.automationWebView?.canGoBack ?? false
            let isEnabled = !self.isBackNavigationDisabled
            let shouldShow = isAutomationVisible && hasHistory && isEnabled
            let targetAlpha: CGFloat = shouldShow ? 1.0 : 0.0

            if backButton.alpha != targetAlpha {
                UIView.animate(withDuration: 0.2) {
                    backButton.alpha = targetAlpha
                }
                passageLogger.debug("[WEBVIEW] Back button visibility updated: \(shouldShow ? "visible" : "hidden") (automation visible: \(isAutomationVisible), has history: \(hasHistory), enabled: \(isEnabled))")
            }

            if let automationWebView = self.automationWebView {
                let wasEnabled = automationWebView.allowsBackForwardNavigationGestures
                automationWebView.allowsBackForwardNavigationGestures = shouldShow

                if wasEnabled != shouldShow {
                    passageLogger.debug("[WEBVIEW] Built-in back swipe gesture \(shouldShow ? "enabled" : "disabled")")
                }
            }
        }
    }

    func clearAutomationNavigationHistory() {
        passageLogger.info("[WEBVIEW] Clearing automation webview navigation history")

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let automationWebView = self.automationWebView else { return }

            self.isBackNavigationDisabled = true
            passageLogger.debug("[WEBVIEW] Back navigation disabled")

            self.updateBackButtonVisibility()

            if automationWebView.canGoBack {
                automationWebView.loadHTMLString("", baseURL: nil)
                passageLogger.debug("[WEBVIEW] Cleared automation webview history")
            }
        }
    }

    func handleNavigationStateChange(url: String, loading: Bool, webViewType: String) {
        passageLogger.debug("[NAVIGATION] State change - \(webViewType): \(passageLogger.truncateUrl(url, maxLength: 100)), loading: \(loading)")

        if webViewType == PassageConstants.WebViewTypes.automation && !url.isEmpty {
            if loading {
                if isNavigatingFromBackButton {
                    passageLogger.debug("[NAVIGATION] Skipping browser state send - navigation triggered by back button")
                } else {
                    let browserStateData: [String: Any] = [
                        "url": url
                    ]

                    NotificationCenter.default.post(
                        name: .sendBrowserState,
                        object: nil,
                        userInfo: browserStateData
                    )

                    passageLogger.debug("[NAVIGATION] Page starting to load for automation webview, sent browser state")
                }
            } else {
                if isNavigatingFromBackButton {
                    passageLogger.debug("[NAVIGATION] Back button navigation completed, resetting flag")
                    isNavigatingFromBackButton = false
                }

                if isBackNavigationDisabled {
                    passageLogger.debug("[NAVIGATION] Re-enabling back navigation after programmatic navigate completed")
                    isBackNavigationDisabled = false
                }

                remoteControl?.handleNavigationComplete(url)

                passageLogger.debug("[NAVIGATION] Page loaded for automation webview, checking for reinjection")

                updateBackButtonVisibility()
            }
        }
    }

    func resetURLState() {
        passageLogger.info("[WEBVIEW] Resetting URL state to empty/initial values")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.url = ""
            self.currentURL = ""
            self.initialURLToLoad = nil

            passageLogger.debug("[WEBVIEW] URL state reset complete: url='', currentURL='', initialURLToLoad=nil")
        }
    }

    func clearWebViewState() {
        passageLogger.info("[WEBVIEW] Clearing webview navigation state (preserving cookies, localStorage, sessionStorage)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let uiWebView = self.uiWebView {
                passageLogger.debug("[WEBVIEW] Clearing UI webview navigation state")

                if uiWebView.isLoading {
                    uiWebView.stopLoading()
                }

                uiWebView.loadHTMLString("", baseURL: nil)
            }

            if let automationWebView = self.automationWebView {
                passageLogger.debug("[WEBVIEW] Clearing automation webview navigation state")

                if automationWebView.isLoading {
                    automationWebView.stopLoading()
                }

                automationWebView.loadHTMLString("", baseURL: nil)
            }

            self.resetForNewSession()

            self.url = ""

            passageLogger.debug("[WEBVIEW] Navigation state cleared successfully (cookies/localStorage/sessionStorage preserved)")
        }
    }

    func clearWebViewData() {
        clearWebViewData(completion: nil)
    }

    func clearWebViewData(completion: (() -> Void)?) {
        passageLogger.info("[WEBVIEW] Clearing ALL webview data including cookies, localStorage, sessionStorage")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion?()
                return
            }

            let group = DispatchGroup()

            if let uiWebView = self.uiWebView {
                passageLogger.debug("[WEBVIEW] Clearing ALL UI webview data")

                if uiWebView.isLoading {
                    uiWebView.stopLoading()
                }

                uiWebView.loadHTMLString("", baseURL: nil)

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

                if automationWebView.isLoading {
                    automationWebView.stopLoading()
                }

                automationWebView.loadHTMLString("", baseURL: nil)

                group.enter()
                let dataStore = automationWebView.configuration.websiteDataStore
                let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
                dataStore.removeData(ofTypes: dataTypes, modifiedSince: Date(timeIntervalSince1970: 0)) {
                    passageLogger.debug("[WEBVIEW] ALL automation webview data cleared (cookies, localStorage, sessionStorage)")
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.resetForNewSession()

                self.url = ""

                passageLogger.info("[WEBVIEW] ALL webview data cleared successfully")
                completion?()
            }
        }
    }

    @objc func navigateInAutomationNotification(_ notification: Notification) {
        passageLogger.debug("[WEBVIEW] ========== NAVIGATE IN AUTOMATION NOTIFICATION ==========")
        passageLogger.debug("[WEBVIEW] 📡 Received navigateInAutomation notification")

        guard let url = notification.userInfo?["url"] as? String else {
            passageLogger.error("[WEBVIEW] ❌ Navigate notification missing URL")
            passageLogger.debug("[WEBVIEW] Available userInfo keys: \(notification.userInfo?.keys.map { "\($0)" } ?? [])")
            return
        }
        let commandId = notification.userInfo?["commandId"] as? String
        passageLogger.info("[WEBVIEW] Navigate notification - URL: \(url), CommandID: \(commandId ?? "nil")")

        // Check if we're already on the target URL
        let currentURL = automationWebView?.url?.absoluteString
        passageLogger.debug("[WEBVIEW] Current URL: \(currentURL ?? "nil")")
        passageLogger.debug("[WEBVIEW] Target URL: \(url)")
        passageLogger.debug("[WEBVIEW] URLs match: \(currentURL == url)")

        if let currentURL = currentURL, currentURL == url {
            passageLogger.info("[WEBVIEW] ✅ Already on target URL, completing navigation command without navigating")
            passageLogger.debug("[WEBVIEW] Sending navigation complete notification immediately")

            // We need to trigger the navigation completion flow without actually navigating
            // This ensures the command result is sent with proper page data
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                passageLogger.debug("[WEBVIEW] Notifying RemoteControlManager of navigation completion")

                // Call handleNavigationComplete to send success with page data
                self.remoteControl?.handleNavigationComplete(url)

                // Also check for success URL matching
                self.remoteControl?.checkNavigationEnd(url)

                passageLogger.debug("[WEBVIEW] Navigation completion handling finished for already-on-URL case")
            }

            return
        }

        clearAutomationNavigationHistory()

        passageLogger.debug("[WEBVIEW] 🚀 Calling navigateInAutomationWebView...")
        navigateInAutomationWebView(url)
    }

    @objc func navigateNotification(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? String else {
            passageLogger.error("[WEBVIEW] Navigate notification missing URL")
            return
        }
        passageLogger.info("[WEBVIEW] Received UI navigate notification: \(url)")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.navigateInUIWebView(url)
        }
    }

    private func handleNavigationTimeout(for webView: WKWebView) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        passageLogger.error("Navigation timeout after 30 seconds for \(webViewType) webview")

        webView.stopLoading()

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

        passageLogger.error("[WebView] Connection timeout - page took too long to load")
    }

    private func showNavigationError(_ message: String) {
        passageLogger.error("[WebView] Navigation error: \(message)")
    }

    private func checkNavigationStatus(for webView: WKWebView) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui

        passageLogger.debug("[NAVIGATION] \(webViewType) - Loading: \(webView.isLoading), Progress: \(Int(webView.estimatedProgress * 100))%")

        if webViewType == PassageConstants.WebViewTypes.automation {
            if let url = webView.url {
                passageLogger.debug("[NAVIGATION] \(webViewType) URL: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
            }
        }

        if !webView.isLoading && webView.estimatedProgress < 1.0 {
            webView.evaluateJavaScript("document.readyState") { result, error in
                if let state = result as? String, state != "complete" {
                    passageLogger.warn("[NAVIGATION] \(webViewType) document not ready: \(state)")
                }
            }
        }
    }
}

extension WebViewModalViewController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui

        if let url = webView.url {
            passageLogger.info("[NAVIGATION] 🚀 \(webViewType) loading: \(url.absoluteString)")

            // Check if this is a popup webview navigating to OAuth
            if let popupWebView = webView as? PassageWKWebView,
               popupWebViews.contains(where: { $0 === popupWebView }) {
                if isOAuthURL(url.absoluteString) {
                    passageLogger.info("[OAUTH] Popup navigating to OAuth URL, keeping custom user agent")
                    // Keep the custom user agent for OAuth flows in popups
                    // User agent is already set during popup creation
                }
            }

            if webViewType == PassageConstants.WebViewTypes.automation {
                remoteControl?.checkNavigationStart(url.absoluteString)
            }

            handleNavigationStateChange(url: url.absoluteString, loading: true, webViewType: webViewType)
            passageAnalytics.trackNavigationStart(url: url.absoluteString, webViewType: webViewType)
            navigationStartTime = Date()
        } else {
            passageLogger.warn("[NAVIGATION] \(webViewType) loading with no URL")
        }

        navigationTimeoutTimer?.invalidate()

        navigationTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            passageLogger.error("[NAVIGATION] ⏱️ TIMEOUT: \(webViewType) navigation didn't complete in 15 seconds")
            self?.handleNavigationTimeout(for: webView)
        }

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
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil

        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui

        if let url = webView.url {
            passageLogger.info("[NAVIGATION] ✅ \(webViewType) loaded: \(url.absoluteString)")

            if webViewType == PassageConstants.WebViewTypes.automation {
                remoteControl?.checkNavigationEnd(url.absoluteString)
            }

            delegate?.webViewModal(didNavigateTo: url)

            handleNavigationStateChange(url: url.absoluteString, loading: false, webViewType: webViewType)
            let duration = navigationStartTime != nil ? Date().timeIntervalSince(navigationStartTime!) : nil
            passageAnalytics.trackNavigationSuccess(url: url.absoluteString, webViewType: webViewType, duration: duration)
            navigationStartTime = nil
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil

        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        passageLogger.webView("Navigation failed: \(error.localizedDescription)", webViewType: webViewType)

        if let url = webView.url {
            handleNavigationStateChange(url: url.absoluteString, loading: false, webViewType: webViewType)
            passageAnalytics.trackNavigationError(url: url.absoluteString, webViewType: webViewType, error: error.localizedDescription)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil

        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui
        let nsError = error as NSError

        passageLogger.error("[NAVIGATION] ❌ \(webViewType) navigation FAILED: \(error.localizedDescription)")
        passageLogger.error("[NAVIGATION] Error domain: \(nsError.domain), code: \(nsError.code)")

        if webViewType == PassageConstants.WebViewTypes.automation {
            passageLogger.error("[NAVIGATION] ❌ CRITICAL: Automation webview navigation failed!")
            passageLogger.error("[NAVIGATION] This will cause script injection to fail")
            passageLogger.error("[NAVIGATION] Error details: \(nsError)")

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

            if intendedAutomationURL != nil {
                passageLogger.debug("[NAVIGATION] 💡 Keeping intended automation URL for script injection")
                passageLogger.debug("[NAVIGATION] Scripts will be injected even though navigation failed")
            }
        }

        let failedUrl = webView.url?.absoluteString ?? nsError.userInfo["NSErrorFailingURLStringKey"] as? String ?? intendedAutomationURL ?? "unknown"
        handleNavigationStateChange(url: failedUrl, loading: false, webViewType: webViewType)
        passageAnalytics.trackNavigationError(url: failedUrl, webViewType: webViewType, error: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui

        if let url = webView.url {
            passageLogger.debug("[NAVIGATION] 📍 \(webViewType) committed: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")

            handleNavigationStateChange(url: url.absoluteString, loading: true, webViewType: webViewType)

            if webViewType == PassageConstants.WebViewTypes.automation {
                remoteControl?.checkNavigationStart(url.absoluteString)
            }
        }
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui

        if let url = webView.url {
            passageLogger.info("[NAVIGATION] 🔄 \(webViewType) redirected: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")

            handleNavigationStateChange(url: url.absoluteString, loading: true, webViewType: webViewType)

            if webViewType == PassageConstants.WebViewTypes.automation {
                remoteControl?.checkNavigationStart(url.absoluteString)
            }

            passageAnalytics.trackNavigationStart(url: url.absoluteString, webViewType: webViewType)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            passageLogger.debug("Navigation policy check for URL: \(url.absoluteString)")
            passageLogger.debug("Navigation type: \(navigationAction.navigationType.rawValue)")

            // Check if this is an OAuth URL that should be handled specially
            if isOAuthURL(url.absoluteString) {
                passageLogger.info("[OAUTH] Handling OAuth navigation to: \(url.absoluteString)")

                // Check if this should open externally
                if shouldOpenExternally(url) {
                    handleExternalOAuthURL(url)
                    decisionHandler(.cancel)
                    return
                }
            }

            // Handle target="_blank" links
            if navigationAction.targetFrame == nil {
                passageLogger.debug("[NAVIGATION] Target frame is nil (likely target='_blank'), loading in current frame")
                webView.load(navigationAction.request)
                decisionHandler(.cancel)
                return
            }
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse {
            passageLogger.debug("HTTP Response - Status Code: \(httpResponse.statusCode)")
            passageLogger.debug("HTTP Response - URL: \(httpResponse.url?.absoluteString ?? "nil")")

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
            }

            if httpResponse.statusCode >= 400 {
                passageLogger.warn("HTTP Error Response: \(httpResponse.statusCode) - allowing navigation to continue")
            }
        }

        decisionHandler(.allow)
    }
}

extension WebViewModalViewController {
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard keyPath == #keyPath(WKWebView.url) else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }

        guard let webView = object as? WKWebView else { return }

        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui

        let oldURL = (change?[.oldKey] as? URL)?.absoluteString
        let newURL = (change?[.newKey] as? URL)?.absoluteString

        if let newURL = newURL, newURL != oldURL {
            passageLogger.info("[KVO] URL changed in \(webViewType): \(passageLogger.truncateUrl(newURL, maxLength: 100))")

            handleNavigationStateChange(url: newURL, loading: webView.isLoading, webViewType: webViewType)

            if webViewType == PassageConstants.WebViewTypes.automation {
                remoteControl?.checkNavigationEnd(newURL)
            }

            if let url = URL(string: newURL) {
                delegate?.webViewModal(didNavigateTo: url)
            }
        }
    }
}

// MARK: - WKUIDelegate Implementation

extension WebViewModalViewController {

    /// Handle requests to open a new window (popups, target="_blank", window.open())
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {

        let url = navigationAction.request.url
        let urlString = url?.absoluteString ?? ""

        passageLogger.debug("[WEBVIEW] Window.open/popup request for: \(urlString.isEmpty ? "(empty - will be set via JS)" : urlString)")
        passageLogger.debug("[WEBVIEW] Navigation type: \(navigationAction.navigationType.rawValue)")

        // Check if URL is empty or about:blank (common for JS-controlled popups)
        if urlString.isEmpty || urlString == "about:blank" {
            passageLogger.debug("[WEBVIEW] Empty URL popup - creating new webview for JS-controlled navigation")

            // Create a new webview that will be navigated via JavaScript
            let popupWebView = PassageWKWebView(frame: .zero, configuration: configuration)
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self

            // Apply user agent from parent webview (automation webview user agent)
            if let automationUA = automationWebView?.customUserAgent {
                popupWebView.customUserAgent = automationUA
                passageLogger.debug("[WEBVIEW] Applied automation webview user agent to popup: \(automationUA)")
            } else if let automationConfigUA = automationUserAgent {
                popupWebView.customUserAgent = automationConfigUA
                passageLogger.debug("[WEBVIEW] Applied stored automation user agent to popup: \(automationConfigUA)")
            } else {
                popupWebView.customUserAgent = nil // Use default Safari user agent
                passageLogger.debug("[WEBVIEW] Using default Safari user agent for popup")
            }

            popupWebView.translatesAutoresizingMaskIntoConstraints = false
            popupWebView.backgroundColor = .white

            // Add to view hierarchy
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                // Create popup container if needed
                if self.popupContainerView == nil {
                    let container = UIView()
                    container.backgroundColor = UIColor.black.withAlphaComponent(0.5)
                    container.translatesAutoresizingMaskIntoConstraints = false
                    self.view.addSubview(container)

                    NSLayoutConstraint.activate([
                        container.topAnchor.constraint(equalTo: self.view.topAnchor),
                        container.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                        container.trailingAnchor.constraint(equalTo: self.view.trailingAnchor),
                        container.bottomAnchor.constraint(equalTo: self.view.bottomAnchor)
                    ])

                    self.popupContainerView = container
                    passageLogger.debug("[WEBVIEW] Created popup container view")
                }

                // Add popup to container
                if let container = self.popupContainerView {
                    container.addSubview(popupWebView)

                    // Make popup centered and sized appropriately
                    NSLayoutConstraint.activate([
                        popupWebView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
                        popupWebView.centerYAnchor.constraint(equalTo: container.centerYAnchor),
                        popupWebView.widthAnchor.constraint(equalTo: container.widthAnchor, multiplier: 0.9),
                        popupWebView.heightAnchor.constraint(equalTo: container.heightAnchor, multiplier: 0.8)
                    ])

                    // Add close button to popup
                    let closeButton = UIButton(type: .system)
                    closeButton.setTitle("✕", for: .normal)
                    closeButton.titleLabel?.font = UIFont.systemFont(ofSize: 28, weight: .light)
                    closeButton.tintColor = .white
                    closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.6)
                    closeButton.layer.cornerRadius = 20
                    closeButton.translatesAutoresizingMaskIntoConstraints = false

                    closeButton.addTarget(self, action: #selector(self.closeTopPopup), for: .touchUpInside)

                    container.addSubview(closeButton)

                    NSLayoutConstraint.activate([
                        closeButton.topAnchor.constraint(equalTo: popupWebView.topAnchor, constant: 8),
                        closeButton.trailingAnchor.constraint(equalTo: popupWebView.trailingAnchor, constant: -8),
                        closeButton.widthAnchor.constraint(equalToConstant: 40),
                        closeButton.heightAnchor.constraint(equalToConstant: 40)
                    ])

                    container.isHidden = false
                    self.view.bringSubviewToFront(container)

                    // Track popup webview
                    self.popupWebViews.append(popupWebView)

                    passageLogger.debug("[WEBVIEW] Popup webview added to view hierarchy with close button")
                }
            }

            passageLogger.debug("[WEBVIEW] Created popup webview with OAuth-safe configuration")

            return popupWebView
        }

        // Check if this is an OAuth popup with a known URL
        if isOAuthURL(urlString) {
            passageLogger.info("[WEBVIEW] OAuth popup detected, handling in current webview")
            return handleOAuthPopup(for: navigationAction, windowFeatures: windowFeatures)
        }

        // Check if we should open externally
        if let url = url, shouldOpenExternally(url) {
            handleExternalOAuthURL(url)
            return nil
        }

        // For other popups, load in the current webview
        passageLogger.info("[WEBVIEW] Loading popup URL in current webview: \(urlString)")
        webView.load(navigationAction.request)

        return nil
    }

    /// Handle JavaScript alert panels
    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {

        passageLogger.debug("[WEBVIEW] JavaScript alert: \(message)")

        let alertController = UIAlertController(title: nil,
                                               message: message,
                                               preferredStyle: .alert)

        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler()
        })

        present(alertController, animated: true)
    }

    /// Handle JavaScript confirm panels
    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {

        passageLogger.debug("[WEBVIEW] JavaScript confirm: \(message)")

        let alertController = UIAlertController(title: nil,
                                               message: message,
                                               preferredStyle: .alert)

        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(false)
        })

        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(true)
        })

        present(alertController, animated: true)
    }

    /// Handle JavaScript text input panels
    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {

        passageLogger.debug("[WEBVIEW] JavaScript prompt: \(prompt), default: \(defaultText ?? "nil")")

        let alertController = UIAlertController(title: nil,
                                               message: prompt,
                                               preferredStyle: .alert)

        alertController.addTextField { textField in
            textField.text = defaultText
        }

        alertController.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
            completionHandler(nil)
        })

        alertController.addAction(UIAlertAction(title: "OK", style: .default) { _ in
            completionHandler(alertController.textFields?.first?.text)
        })

        present(alertController, animated: true)
    }

    /// Handle window close requests
    func webViewDidClose(_ webView: WKWebView) {
        passageLogger.info("[WEBVIEW] Window close requested")

        // Check if this is a popup webview
        if let popupWebView = webView as? PassageWKWebView,
           popupWebViews.contains(where: { $0 === popupWebView }) {
            passageLogger.info("[WEBVIEW] Closing popup webview")
            closePopup(popupWebView)
            return
        }

        // Handle main webview close
        if webView == uiWebView || webView == automationWebView {
            closeModal()
        }
    }

    /// Close a specific popup webview
    func closePopup(_ popupWebView: PassageWKWebView) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Remove from tracking
            self.popupWebViews.removeAll { $0 === popupWebView }

            // Remove from view hierarchy
            popupWebView.removeFromSuperview()

            // Hide container if no more popups
            if self.popupWebViews.isEmpty {
                self.popupContainerView?.isHidden = true
                passageLogger.debug("[WEBVIEW] All popups closed, hiding container")
            }

            passageLogger.info("[WEBVIEW] Popup webview closed and cleaned up")
        }
    }

    /// Close all popup webviews
    func closeAllPopups() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            passageLogger.info("[WEBVIEW] Closing all \(self.popupWebViews.count) popup(s)")

            for popup in self.popupWebViews {
                popup.removeFromSuperview()
            }

            self.popupWebViews.removeAll()
            self.popupContainerView?.isHidden = true

            passageLogger.info("[WEBVIEW] All popups closed")
        }
    }

    /// Close the most recently opened popup (called from close button)
    @objc func closeTopPopup() {
        if let topPopup = popupWebViews.last {
            passageLogger.info("[WEBVIEW] User tapped close button on popup")
            closePopup(topPopup)
        }
    }
}
#endif