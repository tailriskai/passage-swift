#if canImport(UIKit)
import UIKit
@preconcurrency import WebKit

extension WebViewModalViewController {

    func createHeaderContainer() {
        let container = UIView()
        container.backgroundColor = UIColor.white
        container.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(container)

        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: view.topAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 57)
        ])

        self.headerContainer = container

        addLogoToContainer(container)
        addBackButtonToContainer(container)
        addCloseButtonToContainer(container)
        addHeaderBorderToContainer(container)

        view.bringSubviewToFront(container)
    }

    func addLogoToContainer(_ container: UIView) {
        passageLogger.debug("[WEBVIEW] Logo hidden - skipping logo creation")
    }

    func addBackButtonToContainer(_ container: UIView) {
        let backButton = UILabel()
        backButton.text = "←"
        backButton.font = UIFont.systemFont(ofSize: 26, weight: .light)
        backButton.textColor = UIColor.black
        backButton.textAlignment = .center
        backButton.backgroundColor = UIColor.clear
        backButton.isUserInteractionEnabled = true
        backButton.alpha = 0

        container.addSubview(backButton)
        backButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 4),
            backButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 48),
            backButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(backButtonTappedWithAnimation))
        backButton.addGestureRecognizer(tapGesture)

        self.backButton = backButton
    }

    func addCloseButtonToContainer(_ container: UIView) {
        let closeButton = UILabel()
        closeButton.text = "×"
        closeButton.font = UIFont.systemFont(ofSize: 32, weight: .light)
        closeButton.textColor = UIColor.black
        closeButton.textAlignment = .center
        closeButton.backgroundColor = UIColor.clear
        closeButton.isUserInteractionEnabled = true

        container.addSubview(closeButton)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 4),
            closeButton.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 48),
            closeButton.heightAnchor.constraint(equalToConstant: 48)
        ])

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(closeButtonTappedWithAnimation))
        closeButton.addGestureRecognizer(tapGesture)

        self.modernCloseButton = closeButton
    }

    func addHeaderBorderToContainer(_ container: UIView) {
        let borderView = UIView()
        borderView.backgroundColor = UIColor.systemGray4
        borderView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(borderView)

        NSLayoutConstraint.activate([
            borderView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            borderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            borderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            borderView.heightAnchor.constraint(equalToConstant: 1.0 / UIScreen.main.scale)
        ])
    }

    @objc func closeModal() {
        passageLogger.debug("Close button tapped, dismissing modal")

        closeButtonPressCount = 0
        isUIWebViewLockedByRecording = false

        resetURLState()

        dismiss(animated: true) {
            self.delegate?.webViewModalDidClose()
        }
    }

    // MARK: - OAuth Callback Handling

    func handleOAuthCallback(url: URL) {
        passageLogger.info("[OAUTH] Handling OAuth callback URL: \(url.absoluteString)")

        // Extract OAuth parameters (code, state, etc.)
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var params: [String: String] = [:]
            components.queryItems?.forEach { item in
                params[item.name] = item.value
            }

            // Check for OAuth success
            if params.keys.contains("code") {
                passageLogger.info("[OAUTH] OAuth authorization successful, code received")
                // The web application should handle the code exchange
            }

            // Check for OAuth error
            if let error = params["error"] {
                passageLogger.error("[OAUTH] OAuth authorization failed: \(error)")
                if let errorDescription = params["error_description"] {
                    passageLogger.error("[OAUTH] Error description: \(errorDescription)")
                }
            }
        }

        // Continue loading the callback URL in the webview
        // The web application will handle the OAuth flow completion
    }

    @objc func closeButtonTappedWithAnimation() {
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

    @objc func closeButtonTapped() {
        closeButtonPressCount += 1
        passageLogger.info("[WEBVIEW] Close button tapped (press #\(closeButtonPressCount))")

        if closeButtonPressCount >= 2 {
            passageLogger.info("[WEBVIEW] Second close button press - closing modal immediately")
            closeModal()
            return
        }

        passageLogger.info("[WEBVIEW] First close button press - requesting close confirmation")

        wasShowingAutomationBeforeClose = !isShowingUIWebView

        if !isShowingUIWebView {
            passageLogger.info("[WEBVIEW] Switching to UI webview before showing close confirmation")
            showUIWebView()
        }

        if let uiWebView = uiWebView {
            passageLogger.info("[WEBVIEW] Sending close confirmation request to UI webview")

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

    func updateTitle(_ title: String) {
        navigationItem.title = ""
    }

    func showUIWebView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let uiWebView = self.uiWebView, let automationWebView = self.automationWebView else {
                passageLogger.warn("[WEBVIEW] Cannot show UI WebView - WebViews have been released")
                return
            }

            if self.isAnimating {
                uiWebView.layer.removeAllAnimations()
                automationWebView.layer.removeAllAnimations()
                self.isAnimating = false
            }

            if self.isShowingUIWebView {
                self.view.bringSubviewToFront(uiWebView)
                uiWebView.alpha = 1
                automationWebView.alpha = 0
                self.updateBackButtonVisibility()
                return
            }

            passageLogger.debug("[WEBVIEW] Switching to UI webview")
            self.isAnimating = true
            self.view.bringSubviewToFront(uiWebView)

            if let headerContainer = self.headerContainer {
                self.view.bringSubviewToFront(headerContainer)
            }

            automationWebView.shouldPreventFirstResponder = true
            uiWebView.shouldPreventFirstResponder = false

            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
                uiWebView.alpha = 1
                automationWebView.alpha = 0
            }, completion: { _ in
                self.isAnimating = false
                self.isShowingUIWebView = true
                self.onWebviewChange?("ui")

                self.updateBackButtonVisibility()
            })
        }
    }

    func showAutomationWebView() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if self.debugSingleWebViewUrl != nil {
                passageLogger.debug("[DEBUG MODE] Ignoring showAutomationWebView (debug mode)")
                return
            }

            if self.uiWebView == nil || self.automationWebView == nil {
                passageLogger.warn("[WEBVIEW] WebViews not available - attempting to setup")

                if self.isViewLoaded && self.view.window != nil {
                    passageLogger.info("[WEBVIEW] View is loaded, setting up webviews")
                    self.setupWebViews()

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

            if self.isAnimating {
                uiWebView.layer.removeAllAnimations()
                automationWebView.layer.removeAllAnimations()
                self.isAnimating = false
            }

            if !self.isShowingUIWebView {
                self.view.bringSubviewToFront(automationWebView)
                automationWebView.alpha = 1
                uiWebView.alpha = 0
                self.updateBackButtonVisibility()
                return
            }

            passageLogger.debug("[WEBVIEW] Switching to automation webview")
            self.isAnimating = true
            self.view.bringSubviewToFront(automationWebView)

            if let headerContainer = self.headerContainer {
                self.view.bringSubviewToFront(headerContainer)
            }

            automationWebView.shouldPreventFirstResponder = false
            uiWebView.shouldPreventFirstResponder = true

            UIView.animate(withDuration: 0.2, delay: 0, options: [.curveEaseInOut, .allowUserInteraction], animations: {
                automationWebView.alpha = 1
                uiWebView.alpha = 0
            }, completion: { _ in
                self.isAnimating = false
                self.isShowingUIWebView = false
                self.onWebviewChange?("automation")

                self.updateBackButtonVisibility()
            })
        }
    }

    func showLoadingIndicator() {
        showUIWebView()
    }

    func hideLoadingIndicator() {
        showUIWebView()
    }

    func showAutomationWebViewForRemoteControl() {
        showAutomationWebView()
    }

    func showUIWebViewForUserInteraction() {
        showUIWebView()
    }

    func getCurrentWebViewType() -> String {
        return isShowingUIWebView ? PassageConstants.WebViewTypes.ui : PassageConstants.WebViewTypes.automation
    }

    @objc func showUIWebViewNotification(_ notification: Notification) {
        passageLogger.info("[WEBVIEW] Received showUIWebView notification")
        passageLogger.debug("[WEBVIEW] Notification source: \(String(describing: Thread.callStackSymbols[0...3]))")

        // Check if this is a lock request from completeRecording in record mode
        if let userInfo = notification.userInfo,
           let lockUIWebView = userInfo["lockUIWebView"] as? Bool,
           lockUIWebView {
            passageLogger.info("[WEBVIEW] Locking UI webview - will persist until modal closes")
            isUIWebViewLockedByRecording = true
        }

        showUIWebView()
    }

    @objc func showAutomationWebViewNotification() {
        passageLogger.info("[WEBVIEW] Received showAutomationWebView notification")
        passageLogger.debug("[WEBVIEW] Notification source: \(String(describing: Thread.callStackSymbols[0...3]))")
        showAutomationWebView()
    }

    @objc func keyboardWillShow(_ notification: Notification) {
        guard isShowingUIWebView else {
            passageLogger.debug("[KEYBOARD] Automation webview is visible, allowing keyboard")
            return
        }

        if isKeyboardEnabled {
            passageLogger.debug("[KEYBOARD] Keyboard enabled via JavaScript flag, allowing keyboard")
            return
        }

        passageLogger.info("[KEYBOARD] Keyboard will show while UI webview is visible - dismissing immediately")

        DispatchQueue.main.async { [weak self] in
            self?.view.endEditing(true)
        }
    }

    @objc func keyboardDidShow(_ notification: Notification) {
        guard isShowingUIWebView else {
            passageLogger.debug("[KEYBOARD] Automation webview is visible, keyboard allowed")
            return
        }

        if isKeyboardEnabled {
            passageLogger.debug("[KEYBOARD] Keyboard enabled via JavaScript flag, allowing keyboard")
            return
        }

        passageLogger.info("[KEYBOARD] Keyboard did show while UI webview is visible - dismissing immediately")

        DispatchQueue.main.async { [weak self] in
            self?.view.endEditing(true)
        }
    }

    func presentBottomSheet(title: String?, description: String?, points: [String]?, closeButtonText: String?, showInput: Bool = false) {
        passageLogger.info("[BOTTOM SHEET] Presenting bottom sheet with title: \(title ?? "nil")")
        passageLogger.debug("[BOTTOM SHEET] Description: \(description ?? "nil")")
        passageLogger.debug("[BOTTOM SHEET] Points count: \(points?.count ?? 0)")
        passageLogger.debug("[BOTTOM SHEET] Close button text: \(closeButtonText ?? "nil")")
        passageLogger.debug("[BOTTOM SHEET] Show input: \(showInput)")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let existingBottomSheet = self.presentedViewController as? BottomSheetViewController {
                passageLogger.info("[BOTTOM SHEET] Bottom sheet already visible, updating content")
                existingBottomSheet.updateContent(
                    title: title,
                    description: description,
                    points: points,
                    closeButtonText: closeButtonText,
                    showInput: showInput,
                    onSubmit: { [weak self] url in
                        guard let self = self else { return }
                        passageLogger.info("[BOTTOM SHEET] Navigating to URL in automation webview: \(url)")
                        self.navigateInAutomationWebView(url)
                    }
                )
                return
            }

            let bottomSheetVC = BottomSheetViewController(
                title: title,
                description: description,
                points: points,
                closeButtonText: closeButtonText,
                showInput: showInput,
                onSubmit: { [weak self] url in
                    guard let self = self else { return }
                    passageLogger.info("[BOTTOM SHEET] Navigating to URL in automation webview: \(url)")
                    self.navigateInAutomationWebView(url)
                }
            )

            // Sheet configuration is handled in BottomSheetViewController's viewDidLoad

            self.present(bottomSheetVC, animated: true) {
                passageLogger.info("[BOTTOM SHEET] Bottom sheet presented successfully")
            }
        }
    }

    /// Preload a website in a hidden modal for faster presentation later
    /// - Parameter url: The URL string to preload
    @available(iOS 16.0, *)
    func preloadWebsiteModal(url: String) {
        passageLogger.info("[WEBSITE_MODAL] 🔄 preloadWebsiteModal called with URL: \(url)")

        // Validate URL
        guard let urlObj = URL(string: url) else {
            passageLogger.error("[WEBSITE_MODAL] Invalid URL format for preload: \(url)")
            return
        }

        // Only allow http and https schemes
        guard let scheme = urlObj.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            passageLogger.error("[WEBSITE_MODAL] Invalid URL scheme for preload. Only http and https are allowed: \(url)")
            return
        }

        // If already preloaded with same URL, do nothing
        if let preloadedURL = preloadedWebsiteURL, preloadedURL == url {
            passageLogger.info("[WEBSITE_MODAL] URL already preloaded, skipping: \(url)")
            return
        }

        // Replace existing preloaded modal if different URL
        if preloadedWebsiteModalVC != nil {
            passageLogger.info("[WEBSITE_MODAL] Replacing existing preloaded modal")
            preloadedWebsiteModalVC = nil
            preloadedWebsiteURL = nil
        }

        passageLogger.info("[WEBSITE_MODAL] Creating preloaded WebsiteModalViewController for URL: \(urlObj.absoluteString)")

        // Create the website modal view controller with automation user agent
        let websiteModalVC = WebsiteModalViewController(url: urlObj, customUserAgent: automationUserAgent)

        // Configure presentation style as a sheet with large detent
        websiteModalVC.modalPresentationStyle = UIModalPresentationStyle.pageSheet

        if let sheet = websiteModalVC.sheetPresentationController {
            sheet.detents = [UISheetPresentationController.Detent.large()]
            sheet.prefersGrabberVisible = true
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
        }

        // Store the preloaded modal and URL FIRST
        preloadedWebsiteModalVC = websiteModalVC
        preloadedWebsiteURL = url

        // Present off-screen to keep it alive and trigger loading
        passageLogger.info("[WEBSITE_MODAL] 📲 Presenting modal off-screen to preload...")

        // Create an invisible container to present from
        let offscreenWindow = UIWindow(frame: CGRect(x: -10000, y: -10000, width: 1, height: 1))
        let offscreenVC = UIViewController()
        offscreenWindow.rootViewController = offscreenVC
        offscreenWindow.windowLevel = .normal - 1  // Below everything
        offscreenWindow.isHidden = false
        offscreenWindow.alpha = 0.0  // Invisible

        // Present the modal off-screen
        offscreenVC.present(websiteModalVC, animated: false) {
            passageLogger.info("[WEBSITE_MODAL] ✅ Website modal preloaded and presented off-screen")

            // Immediately dismiss it visually but keep the VC alive
            websiteModalVC.view.alpha = 0.0
            websiteModalVC.view.isHidden = true
        }
    }

    /// Present a website in a modal sheet
    /// If the URL matches a preloaded modal, it will be shown instantly
    /// - Parameter url: The URL string to load in the modal
    @available(iOS 16.0, *)
    func presentWebsiteModal(url: String) {
        passageLogger.info("[WEBSITE_MODAL] 🎬 presentWebsiteModal called with URL: \(url)")
        passageLogger.info("[WEBSITE_MODAL]   - Preloaded URL: \(preloadedWebsiteURL ?? "none")")
        passageLogger.info("[WEBSITE_MODAL]   - Has preloaded VC: \(preloadedWebsiteModalVC != nil)")

        // Validate URL
        guard let urlObj = URL(string: url) else {
            passageLogger.error("[WEBSITE_MODAL] Invalid URL format: \(url)")
            return
        }

        // Only allow http and https schemes
        guard let scheme = urlObj.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            passageLogger.error("[WEBSITE_MODAL] Invalid URL scheme. Only http and https are allowed: \(url)")
            return
        }

        let websiteModalVC: WebsiteModalViewController

        // Check if we have a preloaded modal for this URL
        if let preloadedURL = preloadedWebsiteURL,
           preloadedURL == url,
           let preloadedVC = preloadedWebsiteModalVC as? WebsiteModalViewController {
            passageLogger.info("[WEBSITE_MODAL] ♻️ Using preloaded modal for URL: \(url)")

            // Dismiss from off-screen presentation first
            if preloadedVC.presentingViewController != nil {
                passageLogger.info("[WEBSITE_MODAL] Dismissing from off-screen presentation...")
                preloadedVC.dismiss(animated: false) {
                    passageLogger.info("[WEBSITE_MODAL] Off-screen dismissal complete")
                }
            }

            // Make it visible again
            preloadedVC.view.alpha = 1.0
            preloadedVC.view.isHidden = false

            websiteModalVC = preloadedVC

            // Don't clear the preloaded modal - keep it for reuse after dismissal
        } else {
            passageLogger.info("[WEBSITE_MODAL] 🆕 Creating new WebsiteModalViewController for URL: \(urlObj.absoluteString)")

            // Create a new website modal view controller with automation user agent
            websiteModalVC = WebsiteModalViewController(url: urlObj, customUserAgent: automationUserAgent)

            // Configure presentation style as a sheet with large detent
            websiteModalVC.modalPresentationStyle = UIModalPresentationStyle.pageSheet

            if let sheet = websiteModalVC.sheetPresentationController {
                // Set large detent (partial height from bottom)
                sheet.detents = [UISheetPresentationController.Detent.large()]

                // Allow user dismissal via swipe/tap outside
                sheet.prefersGrabberVisible = true

                // Optional: Allow scrolling to expand when content is scrolled to top
                sheet.prefersScrollingExpandsWhenScrolledToEdge = false

                passageLogger.debug("[WEBSITE_MODAL] Sheet presentation configured with .large detent")
            }
        }

        // Present the modal
        present(websiteModalVC, animated: true) {
            passageLogger.info("[WEBSITE_MODAL] Website modal presented successfully")
        }
    }
}
#endif