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

            guard self.automationWebView != nil else {
                passageLogger.error("[WEBVIEW] ❌ Cannot navigate - automation webview is nil")
                passageLogger.error("[WEBVIEW] View loaded: \(self.isViewLoaded)")
                passageLogger.error("[WEBVIEW] View in window: \(self.view.window != nil)")

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
                passageLogger.info("[WEBVIEW] ✅ URL is valid, proceeding with navigation")
                passageLogger.info("[WEBVIEW] Automation webview current URL: \(self.automationWebView?.url?.absoluteString ?? "nil")")
                passageLogger.info("[WEBVIEW] Automation webview is loading: \(self.automationWebView?.isLoading ?? false)")

                self.intendedAutomationURL = url
                passageLogger.info("[WEBVIEW] 📝 Stored intended automation URL: \(url)")

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
        passageLogger.info("[WEBVIEW] Back button tapped")

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

            passageLogger.info("[WEBVIEW] Navigation state cleared successfully (cookies/localStorage/sessionStorage preserved)")
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

        // Check if we're already on the target URL
        let currentURL = automationWebView?.url?.absoluteString
        passageLogger.info("[WEBVIEW] Current URL: \(currentURL ?? "nil")")
        passageLogger.info("[WEBVIEW] Target URL: \(url)")
        passageLogger.info("[WEBVIEW] URLs match: \(currentURL == url)")

        if let currentURL = currentURL, currentURL == url {
            passageLogger.info("[WEBVIEW] ✅ Already on target URL, completing navigation command without navigating")
            passageLogger.info("[WEBVIEW] Sending navigation complete notification immediately")

            // We need to trigger the navigation completion flow without actually navigating
            // This ensures the command result is sent with proper page data
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }

                passageLogger.info("[WEBVIEW] Notifying RemoteControlManager of navigation completion")

                // Call handleNavigationComplete to send success with page data
                self.remoteControl?.handleNavigationComplete(url)

                // Also check for success URL matching
                self.remoteControl?.checkNavigationEnd(url)

                passageLogger.info("[WEBVIEW] Navigation completion handling finished for already-on-URL case")
            }

            return
        }

        clearAutomationNavigationHistory()

        passageLogger.info("[WEBVIEW] 🚀 Calling navigateInAutomationWebView...")
        navigateInAutomationWebView(url)
    }

    @objc func navigateNotification(_ notification: Notification) {
        guard let url = notification.userInfo?["url"] as? String else {
            passageLogger.error("[WEBVIEW] Navigate notification missing URL")
            return
        }
        passageLogger.info("[WEBVIEW] Received UI navigate notification: \(passageLogger.truncateUrl(url, maxLength: 100))")

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
            passageLogger.info("[NAVIGATION] 🚀 \(webViewType) loading: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")

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
            passageLogger.info("[NAVIGATION] ✅ \(webViewType) loaded: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")

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
                passageLogger.info("[NAVIGATION] 💡 Keeping intended automation URL for script injection")
                passageLogger.info("[NAVIGATION] Scripts will be injected even though navigation failed")
            }
        }

        let failedUrl = webView.url?.absoluteString ?? nsError.userInfo["NSErrorFailingURLStringKey"] as? String ?? intendedAutomationURL ?? "unknown"
        handleNavigationStateChange(url: failedUrl, loading: false, webViewType: webViewType)
        passageAnalytics.trackNavigationError(url: failedUrl, webViewType: webViewType, error: error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let webViewType = webView.tag == 2 ? PassageConstants.WebViewTypes.automation : PassageConstants.WebViewTypes.ui

        if let url = webView.url {
            passageLogger.info("[NAVIGATION] 📍 \(webViewType) committed: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")

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
#endif