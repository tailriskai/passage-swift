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

        resetURLState()

        dismiss(animated: true) {
            self.delegate?.webViewModalDidClose()
        }
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

    @objc func showUIWebViewNotification() {
        passageLogger.info("[WEBVIEW] Received showUIWebView notification")
        passageLogger.debug("[WEBVIEW] Notification source: \(String(describing: Thread.callStackSymbols[0...3]))")
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

        passageLogger.info("[KEYBOARD] Keyboard did show while UI webview is visible - dismissing immediately")

        DispatchQueue.main.async { [weak self] in
            self?.view.endEditing(true)
        }
    }

    func presentBottomSheet(title: String, description: String?, points: [String]?, closeButtonText: String?) {
        passageLogger.info("[BOTTOM SHEET] Presenting bottom sheet with title: \(title)")
        passageLogger.debug("[BOTTOM SHEET] Description: \(description ?? "nil")")
        passageLogger.debug("[BOTTOM SHEET] Points count: \(points?.count ?? 0)")
        passageLogger.debug("[BOTTOM SHEET] Close button text: \(closeButtonText ?? "nil")")

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            if let existingBottomSheet = self.presentedViewController as? BottomSheetViewController {
                passageLogger.info("[BOTTOM SHEET] Bottom sheet already visible, updating content")
                existingBottomSheet.updateContent(
                    title: title,
                    description: description,
                    points: points,
                    closeButtonText: closeButtonText
                )
                return
            }

            let bottomSheetVC = BottomSheetViewController(
                title: title,
                description: description,
                points: points,
                closeButtonText: closeButtonText
            )

            if #available(iOS 15.0, *) {
                if let sheet = bottomSheetVC.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                    sheet.prefersGrabberVisible = true
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                    sheet.preferredCornerRadius = 16
                }
            }

            self.present(bottomSheetVC, animated: true) {
                passageLogger.info("[BOTTOM SHEET] Bottom sheet presented successfully")
            }
        }
    }
}
#endif