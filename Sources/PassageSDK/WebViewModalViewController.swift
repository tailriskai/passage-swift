#if canImport(UIKit)
import UIKit
@preconcurrency import WebKit

protocol WebViewModalDelegate: AnyObject {
    func webViewModalDidClose()
    func webViewModal(didNavigateTo url: URL)
}

struct PendingUserActionCommand {
    let commandId: String
    let script: String
    let timestamp: Date
}

class PassageWKWebView: WKWebView {
    var shouldPreventFirstResponder: Bool = false

    override var canBecomeFirstResponder: Bool {
        return shouldPreventFirstResponder ? false : super.canBecomeFirstResponder
    }

    override func becomeFirstResponder() -> Bool {
        return shouldPreventFirstResponder ? false : super.becomeFirstResponder()
    }
}

class WebViewModalViewController: UIViewController, UIAdaptivePresentationControllerDelegate, WKUIDelegate {
    weak var delegate: WebViewModalDelegate?

    var modalTitle: String = ""
    var titleText: String = ""
    var showGrabber: Bool = false
    var url: String = ""

    var onMessage: ((Any) -> Void)?
    var onClose: (() -> Void)?
    var onWebviewChange: ((String) -> Void)?

    var remoteControl: RemoteControlManager? {
        didSet {
            // Set the back-reference for record mode UI locking
            remoteControl?.viewController = self
        }
    }

    /// Bottom margin for record mode UI (matches React Native SDK)
    var marginBottom: CGFloat = 0 {
        didSet {
            updateAutomationWebViewConstraints()
        }
    }

    var uiWebView: PassageWKWebView!
    var automationWebView: PassageWKWebView!

    // Constraints for automation webview (needed for marginBottom updates)
    var automationWebViewBottomConstraint: NSLayoutConstraint?

    var currentURL: String = ""
    var isShowingUIWebView: Bool = true
    var isAnimating: Bool = false

    var pendingUserActionCommand: PendingUserActionCommand?

    var currentScreenshot: String?
    var previousScreenshot: String?

    var automationUserAgent: String?

    var initialURLToLoad: String?

    var modernCloseButton: UIView?

    var backButton: UIView?

    var headerContainer: UIView?

    var wasShowingAutomationBeforeClose: Bool = false

    // Preloaded website modal state (iOS 16.0+)
    var preloadedWebsiteModalVC: Any? // WebsiteModalViewController on iOS 16+
    var preloadedWebsiteURL: String?

    var closeButtonPressCount: Int = 0

    var isNavigatingFromBackButton: Bool = false

    var isBackNavigationDisabled: Bool = false

    let debugSingleWebViewUrl: String? = nil
    let forceSimpleWebView: Bool = false

    var navigationTimeoutTimer: Timer?
    var navigationStartTime: Date?

    var intendedAutomationURL: String?
    var intendedUIURL: String?

    // Popup window management
    var popupWebViews: [PassageWKWebView] = []
    var popupContainerView: UIView?

    // Record mode: Lock UI webview after completeRecording
    var isUIWebViewLockedByRecording: Bool = false

    // Keyboard control: Allow temporary keyboard enablement via JavaScript
    var isKeyboardEnabled: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()

        passageLogger.debug("[WEBVIEW] ========== VIEW DID LOAD ==========")

        isModalInPresentation = true

        setupScreenshotAccessors()

        setupUI()

        navigationController?.setNavigationBarHidden(true, animated: false)

        passageLogger.debug("[WEBVIEW] Navigation bar shown with custom header")

        if let debugUrl = debugSingleWebViewUrl, !debugUrl.isEmpty {
            passageLogger.debug("[WEBVIEW DEBUG MODE] Single webview mode active with URL: \(passageLogger.truncateUrl(debugUrl, maxLength: 100))")
            return
        }

        if !url.isEmpty {
            passageLogger.debug("[WEBVIEW] Loading provided URL immediately: \(passageLogger.truncateUrl(url, maxLength: 100))")
            loadURL(url)
        } else if let pending = initialURLToLoad {
            passageLogger.debug("[WEBVIEW] Loading pending URL: \(passageLogger.truncateUrl(pending, maxLength: 100))")
            initialURLToLoad = nil
            loadURL(pending)
        } else {
            passageLogger.warn("[WEBVIEW] No URL to load in viewDidLoad")
        }

        passageLogger.debug("[WEBVIEW] viewDidLoad completed")
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        passageLogger.debug("[WEBVIEW] ========== VIEW DID APPEAR ==========")

        closeButtonPressCount = 0
        passageLogger.debug("[WEBVIEW] Reset close button press counter")

        setupNotificationObservers()

        if uiWebView == nil || automationWebView == nil || uiWebView?.superview == nil || automationWebView?.superview == nil {
            passageLogger.debug("[WEBVIEW] WebViews not properly set up, initializing...")
            setupWebViews()

            if let pendingURL = initialURLToLoad {
                passageLogger.debug("[WEBVIEW] Loading pending URL after webview setup: \(passageLogger.truncateUrl(pendingURL, maxLength: 100))")
                initialURLToLoad = nil
                loadURL(pendingURL)
            }
        } else {
            passageLogger.debug("[WEBVIEW] WebViews already properly configured")
        }

        if uiWebView == nil {
            passageLogger.error("[WEBVIEW] UI WebView is nil!")
        } else if let url = uiWebView?.url {
            passageLogger.debug("[WEBVIEW] UI WebView URL: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
        }

        if let urlToLoad = initialURLToLoad {
            passageLogger.debug("[WEBVIEW] Loading deferred URL: \(passageLogger.truncateUrl(urlToLoad, maxLength: 100))")
            initialURLToLoad = nil
            loadURL(urlToLoad)
        }

        if !isShowingUIWebView {
            passageLogger.debug("[WEBVIEW] Resetting to UI webview on reappear")
            showUIWebView()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        passageLogger.debug("[WEBVIEW] ========== VIEW WILL DISAPPEAR ==========")
        passageLogger.debug("[WEBVIEW] View controller instance: \(String(format: "%p", unsafeBitCast(self, to: Int.self)))")

        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil

        NotificationCenter.default.removeObserver(self)
        passageLogger.debug("[WEBVIEW] Removed all notification observers")
    }

    deinit {
        passageLogger.debug("[WEBVIEW] ========== DEINIT ==========")
        passageLogger.debug("[WEBVIEW] View controller instance being deallocated: \(String(format: "%p", unsafeBitCast(self, to: Int.self)))")

        navigationTimeoutTimer?.invalidate()
        navigationTimeoutTimer = nil

        uiWebView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))
        automationWebView?.removeObserver(self, forKeyPath: #keyPath(WKWebView.url))

        NotificationCenter.default.removeObserver(self)
        passageLogger.debug("[WEBVIEW] Notification observers removed")
    }

    private func setupUI() {
        view.backgroundColor = UIColor.white
    }

    func setupNotificationObservers() {
        passageLogger.debug("[WEBVIEW] Setting up notification observers")

        NotificationCenter.default.removeObserver(self)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showUIWebViewNotification(_:)),
            name: .showUIWebView,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showAutomationWebViewNotification),
            name: .showAutomationWebView,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigateInAutomationNotification(_:)),
            name: .navigateInAutomation,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(navigateNotification(_:)),
            name: .navigate,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(injectScriptNotification(_:)),
            name: .injectScript,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(getPageDataNotification(_:)),
            name: .getPageData,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(collectPageDataNotification(_:)),
            name: .collectPageData,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(getCurrentUrlForBrowserStateNotification(_:)),
            name: .getCurrentUrlForBrowserState,
            object: nil
        )

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

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        passageLogger.debug("[WEBVIEW] ========== PRESENTATION CONTROLLER DID DISMISS ==========")

        resetURLState()

        if let delegate = delegate {
            passageLogger.debug("[WEBVIEW] Calling delegate.webViewModalDidClose()")
            delegate.webViewModalDidClose()
        } else {
            passageLogger.error("[WEBVIEW] ❌ No delegate to call webViewModalDidClose()!")
        }
    }

    // MARK: - Record Mode UI Support

    /// Update automation webview constraints for marginBottom (matches React Native SDK)
    private func updateAutomationWebViewConstraints() {
        guard let constraint = automationWebViewBottomConstraint else {
            passageLogger.debug("[WEBVIEW] No automation webview bottom constraint to update")
            return
        }

        passageLogger.debug("[WEBVIEW] Updating automation webview margin bottom to: \(marginBottom)")

        // Update constraint constant
        constraint.constant = -marginBottom

        // Animate the change
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.view.layoutIfNeeded()
        }
    }
}
#endif