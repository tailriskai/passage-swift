#if canImport(UIKit)
import UIKit
@preconcurrency import WebKit

extension WebViewModalViewController {

    @objc func injectScriptNotification(_ notification: Notification) {
        injectScriptNotification(notification, retryCount: 0)
    }

    func injectScriptNotification(_ notification: Notification, retryCount: Int) {
        guard let script = notification.userInfo?["script"] as? String,
              let commandId = notification.userInfo?["commandId"] as? String else {
            passageLogger.error("[WEBVIEW] Inject script notification missing data")
            return
        }

        let commandType = notification.userInfo?["commandType"] as? String ?? "unknown"
        passageLogger.info("[WEBVIEW] Executing \(commandType) script for command: \(commandId) (retry: \(retryCount))")
        passageLogger.debug("[WEBVIEW] View controller instance: \(String(format: "%p", unsafeBitCast(self, to: Int.self)))")
        passageLogger.debug("[WEBVIEW] Webview states - UI: \(uiWebView != nil), Automation: \(automationWebView != nil)")

        guard areWebViewsReady() else {
            let maxRetries = 10

            if retryCount >= maxRetries {
                passageLogger.error("[WEBVIEW] Max retries (\(maxRetries)) exceeded, failing script injection")
                passageLogger.error("[WEBVIEW] Final state - UI: \(uiWebView != nil), Automation: \(automationWebView != nil)")
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }

                if self.areWebViewsReady() {
                    passageLogger.info("[WEBVIEW] WebViews now ready, proceeding with script injection")
                    self.injectScriptNotification(notification, retryCount: retryCount + 1)
                } else {
                    self.injectScriptNotification(notification, retryCount: retryCount + 1)
                }
            }
            return
        }

        let usesWindowPassage = script.contains("window.passage.postMessage")
        let isAsyncScript = script.contains("async function") || commandType == "wait"

        if isAsyncScript && usesWindowPassage {
            passageLogger.debug("[WEBVIEW] Injecting async script with window.passage.postMessage")

            let scriptWithUndefined = script + "; undefined;"

            injectJavaScriptInAutomationWebView(scriptWithUndefined) { result, error in
                if let error = error {
                    passageLogger.error("[WEBVIEW] Async script injection failed: \(error)")
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

                    DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                        passageLogger.warn("[WEBVIEW] Async script timeout for command: \(commandId), no postMessage received")
                    }
                }
            }
        } else {
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

    @objc func getPageDataNotification(_ notification: Notification) {
        guard let commandId = notification.userInfo?["commandId"] as? String else {
            passageLogger.error("[WEBVIEW] Get page data notification missing commandId")
            return
        }
        passageLogger.info("[WEBVIEW] Received get page data notification for command: \(commandId)")
    }

    @objc func collectPageDataNotification(_ notification: Notification) {
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

    @objc func getCurrentUrlForBrowserStateNotification(_ notification: Notification) {
        passageLogger.info("[WEBVIEW URL] ========== GET CURRENT URL FOR BROWSER STATE ==========")

        guard let userInfo = notification.userInfo else {
            passageLogger.error("[WEBVIEW URL] ❌ getCurrentUrlForBrowserState notification missing userInfo")
            return
        }

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

                if let continuation = userInfo["continuation"] as? CheckedContinuation<Void, Never> {
                    continuation.resume()
                } else {
                    passageLogger.warn("[WEBVIEW URL] ⚠️ No continuation to resume")
                }
            }
        }
    }

    func injectJavaScript(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(nil, NSError(domain: "WebViewModal", code: 0, userInfo: [NSLocalizedDescriptionKey: "WebView deallocated"]))
                return
            }
            let targetWebView = self.isShowingUIWebView ? self.uiWebView : self.automationWebView
            targetWebView?.evaluateJavaScript(script, completionHandler: completion)
        }
    }

    func injectJavaScriptInAutomationWebView(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
        injectJavaScriptInAutomationWebView(script, completion: completion, retryCount: 0)
    }

    func injectJavaScriptInAutomationWebView(_ script: String, completion: @escaping (Any?, Error?) -> Void, retryCount: Int) {
        let maxRetries = 10

        DispatchQueue.main.async { [weak self] in
            guard let self = self, let automationWebView = self.automationWebView else {
                completion(nil, NSError(domain: "WebViewModal", code: 0, userInfo: [NSLocalizedDescriptionKey: "Automation WebView not available"]))
                return
            }

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
                    passageLogger.debug("[WEBVIEW] window.passage is ready, injecting script")

                    automationWebView.evaluateJavaScript("window.passage.postMessage('ready')") { testResult, testError in
                        if let testError = testError {
                            passageLogger.error("[WEBVIEW] Test postMessage failed: \(testError)")
                        } else {
                            passageLogger.debug("[WEBVIEW] Test postMessage sent successfully")
                        }

                        automationWebView.evaluateJavaScript(script, completionHandler: completion)
                    }
                } else {
                    if retryCount < maxRetries {
                        passageLogger.debug("[WEBVIEW] window.passage not ready (attempt \(retryCount + 1)/\(maxRetries)), re-injecting window.passage script")
                        passageLogger.debug("[WEBVIEW] window.passage check result: \(String(describing: result))")

                        let passageScript = self.createPassageScript(for: PassageConstants.WebViewTypes.automation)
                        automationWebView.evaluateJavaScript(passageScript) { passageResult, passageError in
                            if let passageError = passageError {
                                passageLogger.error("[WEBVIEW] Error re-injecting window.passage script: \(passageError)")
                            } else {
                                passageLogger.debug("[WEBVIEW] Re-injected window.passage script successfully")
                            }

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.injectJavaScriptInAutomationWebView(script, completion: completion, retryCount: retryCount + 1)
                            }
                        }
                    } else {
                        passageLogger.error("[WEBVIEW] window.passage not ready after \(maxRetries) retries, injecting anyway")
                        automationWebView.evaluateJavaScript(script, completionHandler: completion)
                    }
                }
            }
        }
    }

    private func sendToBackend(apiPath: String, data: Any, headers: [String: String]? = nil, completion: @escaping (Bool, String?) -> Void) {
        passageLogger.info("[SEND_TO_BACKEND] ========== SENDING DATA TO BACKEND ==========")
        passageLogger.info("[SEND_TO_BACKEND] API Path: \(apiPath)")

        guard let remoteControl = remoteControl else {
            passageLogger.error("[SEND_TO_BACKEND] ❌ No remote control available")
            completion(false, "No remote control available")
            return
        }

        let baseUrl = remoteControl.getApiUrl().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullUrlString = baseUrl + apiPath

        guard let url = URL(string: fullUrlString) else {
            passageLogger.error("[SEND_TO_BACKEND] ❌ Invalid URL: \(fullUrlString)")
            completion(false, "Invalid URL")
            return
        }

        passageLogger.info("[SEND_TO_BACKEND] Full URL: \(fullUrlString)")

        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []) else {
            passageLogger.error("[SEND_TO_BACKEND] ❌ Failed to serialize data to JSON")
            completion(false, "Failed to serialize data")
            return
        }

        passageLogger.debug("[SEND_TO_BACKEND] JSON payload size: \(jsonData.count) bytes")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 30.0

        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
                passageLogger.debug("[SEND_TO_BACKEND] Added custom header: \(key)")
            }
        }

        if headers?["x-intent-token"] == nil, let intentToken = remoteControl.getIntentToken() {
            request.setValue(intentToken, forHTTPHeaderField: "x-intent-token")
            passageLogger.debug("[SEND_TO_BACKEND] Added x-intent-token header from remote control")
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                passageLogger.error("[SEND_TO_BACKEND] ❌ Request failed: \(error.localizedDescription)")
                completion(false, error.localizedDescription)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                passageLogger.error("[SEND_TO_BACKEND] ❌ Invalid response type")
                completion(false, "Invalid response")
                return
            }

            passageLogger.info("[SEND_TO_BACKEND] Response status: \(httpResponse.statusCode)")

            if (200...299).contains(httpResponse.statusCode) {
                passageLogger.info("[SEND_TO_BACKEND] ✅ Request succeeded")
                completion(true, nil)
            } else {
                let errorMessage = "HTTP \(httpResponse.statusCode)"
                passageLogger.error("[SEND_TO_BACKEND] ❌ Request failed with status: \(errorMessage)")
                completion(false, errorMessage)
            }
        }

        task.resume()
        passageLogger.debug("[SEND_TO_BACKEND] Request sent")
    }

    func handlePassageMessage(_ data: [String: Any], webViewType: String) {
        if let commandId = data["commandId"] as? String,
           let type = data["type"] as? String {

            passageLogger.info("[WEBVIEW] Handling passage message: \(type) for command: \(commandId)")

            switch type {
            case "injectScript", "wait":
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
                onMessage?(data)
            }
        } else {
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
                onMessage?(data)
            }
        }
    }
}

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
                case PassageConstants.MessageTypes.switchWebview:
                    passageLogger.webView("Switch webview requested", webViewType: webViewType)
                    if isShowingUIWebView {
                        passageLogger.info("[WEBVIEW] Switching from UI to Automation webview")
                        showAutomationWebView()
                    } else {
                        passageLogger.info("[WEBVIEW] Switching from Automation to UI webview")
                        showUIWebView()
                    }
                case PassageConstants.MessageTypes.showBottomSheet:
                    passageLogger.webView("Show bottom sheet requested", webViewType: webViewType)
                    let title = body["title"] as? String
                    let description = body["description"] as? String
                    let points = body["points"] as? [String]
                    let closeButtonText = body["closeButtonText"] as? String
                    let showInput = body["showInput"] as? Bool ?? false
                    passageLogger.info("[BOTTOM SHEET JS] Received showInput from JavaScript: \(showInput)")
                    passageLogger.info("[BOTTOM SHEET JS] Full body: \(body)")
                    presentBottomSheet(title: title, description: description, points: points, closeButtonText: closeButtonText, showInput: showInput)
                case PassageConstants.MessageTypes.setTitle:
                    if let title = body["title"] as? String {
                        passageLogger.webView("Set title: \(title)", webViewType: webViewType)
                        updateTitle(title)
                    }
                case "pageData":
                    passageLogger.debug("[WEBVIEW] Received page data from automation webview")
                    if let data = body["data"] as? [String: Any] {
                        passageLogger.debug("[WEBVIEW] Page data contains: url=\(data["url"] != nil), html=\(passageLogger.truncateHtml(data["html"] as? String)), localStorage=\((data["localStorage"] as? [Any])?.count ?? 0) items, sessionStorage=\((data["sessionStorage"] as? [Any])?.count ?? 0) items")

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
                    if let url = body["url"] as? String,
                       let navigationMethod = body["navigationMethod"] as? String {
                        passageLogger.info("[CLIENT NAV] \(webViewType) - \(navigationMethod): \(passageLogger.truncateUrl(url, maxLength: 100))")

                        handleNavigationStateChange(url: url, loading: false, webViewType: webViewType)

                        if webViewType == PassageConstants.WebViewTypes.automation {
                            remoteControl?.checkNavigationEnd(url)
                        }

                        if let urlObj = URL(string: url) {
                            delegate?.webViewModal(didNavigateTo: urlObj)
                        }

                        passageAnalytics.trackNavigationSuccess(url: url, webViewType: webViewType, duration: nil)
                    }
                case "captureScreenshot":
                    passageLogger.info("[WEBVIEW] Manual screenshot capture requested from \(webViewType) webview")

                    Task {
                        await remoteControl?.captureScreenshotManually()
                    }

                case "sendToBackend":
                    passageLogger.info("[WEBVIEW] sendToBackend called from \(webViewType) webview")

                    guard let apiPath = body["apiPath"] as? String else {
                        passageLogger.error("[WEBVIEW] sendToBackend missing apiPath parameter")
                        return
                    }

                    guard let data = body["data"] else {
                        passageLogger.error("[WEBVIEW] sendToBackend missing data parameter")
                        return
                    }

                    let headers = body["headers"] as? [String: String]

                    passageLogger.debug("[WEBVIEW] sendToBackend - apiPath: \(apiPath)")
                    if let headers = headers {
                        passageLogger.debug("[WEBVIEW] sendToBackend - headers: \(headers.keys.joined(separator: ", "))")
                    }

                    sendToBackend(apiPath: apiPath, data: data, headers: headers) { success, error in
                        if let error = error {
                            passageLogger.error("[WEBVIEW] sendToBackend failed: \(error)")
                        } else if success {
                            passageLogger.debug("[WEBVIEW] sendToBackend succeeded")
                        }
                    }

                case "changeAutomationUserAgent":
                    passageLogger.info("[WEBVIEW] changeAutomationUserAgent called from \(webViewType) webview")

                    guard let userAgent = body["userAgent"] as? String else {
                        passageLogger.error("[WEBVIEW] changeAutomationUserAgent missing userAgent parameter")
                        return
                    }

                    passageLogger.debug("[WEBVIEW] changeAutomationUserAgent - new user agent: \(userAgent)")
                    changeAutomationUserAgentAndReload(userAgent)

                case "openLink":
                    passageLogger.info("[WEBVIEW] openLink called from \(webViewType) webview")

                    guard let urlString = body["url"] as? String else {
                        passageLogger.error("[WEBVIEW] openLink missing url parameter")
                        return
                    }

                    guard let url = URL(string: urlString) else {
                        passageLogger.error("[WEBVIEW] openLink invalid URL: \(urlString)")
                        return
                    }

                    passageLogger.debug("[WEBVIEW] Opening external link: \(urlString)")

                    DispatchQueue.main.async {
                        if UIApplication.shared.canOpenURL(url) {
                            UIApplication.shared.open(url, options: [:]) { success in
                                if success {
                                    passageLogger.info("[WEBVIEW] Successfully opened external link: \(urlString)")
                                } else {
                                    passageLogger.error("[WEBVIEW] Failed to open external link: \(urlString)")
                                }
                            }
                        } else {
                            passageLogger.error("[WEBVIEW] Cannot open URL (invalid scheme or restricted): \(urlString)")
                        }
                    }

                case "CLOSE_CONFIRMED":
                    passageLogger.info("[WEBVIEW] Close confirmation received - proceeding with close")
                    DispatchQueue.main.async {
                        self.closeModal()
                    }
                case "CLOSE_CANCELLED":
                    passageLogger.info("[WEBVIEW] Close cancelled by user")
                    self.closeButtonPressCount = 0
                    if self.wasShowingAutomationBeforeClose {
                        passageLogger.info("[WEBVIEW] Switching back to automation webview after close cancellation")
                        self.showAutomationWebView()
                    }
                    self.wasShowingAutomationBeforeClose = false
                case "enableKeyboard":
                    passageLogger.info("[KEYBOARD] Keyboard enabled via JavaScript from \(webViewType) webview")
                    DispatchQueue.main.async {
                        self.isKeyboardEnabled = true
                    }
                case "disableKeyboard":
                    passageLogger.info("[KEYBOARD] Keyboard disabled via JavaScript from \(webViewType) webview")
                    DispatchQueue.main.async {
                        self.isKeyboardEnabled = false
                        self.view.endEditing(true)
                    }
                case PassageConstants.MessageTypes.message:
                    if let data = body["data"] {
                        if let dataString = data as? String,
                           let jsonData = dataString.data(using: .utf8),
                           let parsedData = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                            handlePassageMessage(parsedData, webViewType: webViewType)
                        } else if let dataDict = data as? [String: Any] {
                            handlePassageMessage(dataDict, webViewType: webViewType)
                        } else {
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
                onMessage?(message.body)
            }
        }
    }
}
#endif