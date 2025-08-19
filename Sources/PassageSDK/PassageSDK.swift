import Foundation
import UIKit
import WebKit

// MARK: - Public Types

public struct PassageConfig {
    public let baseUrl: String
    public let socketUrl: String
    public let socketNamespace: String
    public let debug: Bool
    
    public init(
        baseUrl: String? = nil,
        socketUrl: String? = nil,
        socketNamespace: String? = nil,
        debug: Bool = false
    ) {
        self.baseUrl = baseUrl ?? PassageConstants.Defaults.baseUrl
        self.socketUrl = socketUrl ?? PassageConstants.Defaults.socketUrl
        self.socketNamespace = socketNamespace ?? PassageConstants.Defaults.socketNamespace
        self.debug = debug
    }
}

public struct PassageHistoryItem {
    public let structuredData: Any?
    public let additionalData: [String: Any]
}

public struct PassageSuccessData {
    public let history: [PassageHistoryItem]
    public let connectionId: String
}

public struct PassageErrorData {
    public let error: String
    public let data: Any?
}

public enum PassagePresentationStyle {
    case modal
    case fullScreen
    
    var modalPresentationStyle: UIModalPresentationStyle {
        switch self {
        case .modal:
            return .pageSheet
        case .fullScreen:
            return .fullScreen
        }
    }
}

// MARK: - PassageSDK

public class PassageSDK: NSObject {
    // Singleton instance
    public static let shared = PassageSDK()
    
    // Configuration
    private var config: PassageConfig
    
    // WebView components
    private var webViewController: WebViewModalViewController?
    private var navigationCompletionHandler: ((Result<String, Error>) -> Void)?
    
    // Remote control
    private var remoteControl: RemoteControlManager?
    
    // Callbacks
    public var onSuccess: ((PassageSuccessData) -> Void)?
    public var onError: ((PassageErrorData) -> Void)?
    public var onClose: (() -> Void)?
    
    // MARK: - Initialization
    
    private override init() {
        self.config = PassageConfig()
        super.init()
        passageLogger.debug("PassageSDK initialized")
    }
    
    // MARK: - Public Methods
    
    public func configure(_ config: PassageConfig) {
        self.config = config
        
        // Configure logger
        passageLogger.configure(debug: config.debug)
        passageLogger.debugMethod("configure", params: [
            "baseUrl": config.baseUrl,
            "socketUrl": config.socketUrl,
            "socketNamespace": config.socketNamespace,
            "debug": config.debug
        ])
        
        // Initialize remote control if needed
        if remoteControl == nil {
            remoteControl = RemoteControlManager(config: config)
        } else {
            remoteControl?.updateConfig(config)
        }
    }
    
    public func open(
        token: String,
        presentationStyle: PassagePresentationStyle = .modal,
        from viewController: UIViewController? = nil,
        onSuccess: ((PassageSuccessData) -> Void)? = nil,
        onError: ((PassageErrorData) -> Void)? = nil,
        onClose: (() -> Void)? = nil
    ) {
        passageLogger.debugMethod("open", params: [
            "token": passageLogger.truncateData(token, maxLength: 20),
            "presentationStyle": presentationStyle
        ])
        
        // Store callbacks
        self.onSuccess = onSuccess
        self.onError = onError
        self.onClose = onClose
        
        // Build URL from token
        let url = buildUrlFromToken(token)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Get presenting view controller
            let presentingVC = viewController ?? self.topMostViewController()
            
            guard let presentingVC = presentingVC else {
                let error = PassageErrorData(error: "No view controller available", data: nil)
                passageLogger.error("No view controller available")
                self.onError?(error)
                return
            }
            
            // Create and configure the web view controller
            let webVC = WebViewModalViewController()
            // Ensure initial URL is set so the UI webview opens to connect page by default
            webVC.url = url
            webVC.delegate = self
            webVC.showGrabber = (presentationStyle == .modal)
            webVC.titleText = PassageConstants.Defaults.modalTitle
            
            // Set up message handling
            webVC.onMessage = { [weak self] message in
                self?.handleMessage(message)
            }
            
            webVC.onClose = { [weak self] in
                self?.handleClose()
            }
            
            // Create navigation controller
            let navController = UINavigationController(rootViewController: webVC)
            navController.modalPresentationStyle = presentationStyle.modalPresentationStyle
            
            // Enable pull-down dismissal
            navController.isModalInPresentation = false
            
            if #available(iOS 15.0, *) {
                if let sheet = navController.sheetPresentationController {
                    sheet.detents = [.large()]
                    sheet.prefersGrabberVisible = true // Always show grabber for pull-down
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = false
                }
            }
            
            // Set delegate to handle dismissal
            navController.presentationController?.delegate = webVC
            
            // Pre-load URL (will be actually loaded in viewDidAppear)
            webVC.loadURL(url)
            
            // Present the modal
            presentingVC.present(navController, animated: true) {
                // Initialize remote control if needed
                self.initializeRemoteControl(with: token)
            }
            
            self.webViewController = webVC
        }
    }
    
    public func close() {
        passageLogger.debugMethod("close")
        
        DispatchQueue.main.async { [weak self] in
            self?.webViewController?.dismiss(animated: true) {
                self?.cleanup()
            }
        }
    }
    
    // MARK: - Navigation Methods
    
    public func navigate(to url: String) {
        webViewController?.navigateTo(url)
    }
    
    public func goBack() {
        webViewController?.goBack()
    }
    
    public func goForward() {
        webViewController?.goForward()
    }
    
    // MARK: - Cookie Management
    
    public func getCookies(for url: String, completion: @escaping ([HTTPCookie]) -> Void) {
        guard let urlObj = URL(string: url) else {
            completion([])
            return
        }
        
        DispatchQueue.main.async {
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let filteredCookies = cookies.filter { cookie in
                    return self.cookieMatchesURL(cookie: cookie, url: urlObj)
                }
                completion(filteredCookies)
            }
        }
    }
    
    public func setCookie(_ cookie: HTTPCookie) {
        DispatchQueue.main.async {
            WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
        }
    }
    
    public func clearCookies(for url: String) {
        guard let urlObj = URL(string: url) else { return }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                let filteredCookies = cookies.filter { cookie in
                    return self.cookieMatchesURL(cookie: cookie, url: urlObj)
                }
                
                for cookie in filteredCookies {
                    WKWebsiteDataStore.default().httpCookieStore.delete(cookie)
                }
            }
        }
    }
    
    // MARK: - JavaScript Injection
    
    public func injectJavaScript(_ script: String, completion: @escaping (Any?, Error?) -> Void) {
        webViewController?.injectJavaScript(script, completion: completion)
    }
    
    // MARK: - Private Methods
    
    private func buildUrlFromToken(_ token: String) -> String {
        let baseUrl = config.baseUrl
        let url = URL(string: "\(baseUrl)\(PassageConstants.Paths.connect)")!
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "intentToken", value: token)]
        return components.url!.absoluteString
    }
    
    private func initializeRemoteControl(with token: String) {
        guard let remoteControl = remoteControl else { return }
        
        // Extract session ID from token
        passageLogger.updateIntentToken(token)
        
        // Connect remote control
        remoteControl.connect(
            intentToken: token,
            onSuccess: { [weak self] data in
                self?.onSuccess?(data)
            },
            onError: { [weak self] error in
                self?.onError?(error)
            }
        )
    }
    
    private func handleMessage(_ message: Any) {
        passageLogger.debug("Received message", context: "webview", metadata: [
            "message": passageLogger.truncateData(message, maxLength: 200)
        ])
        
        if let data = message as? [String: Any],
           let type = data["type"] as? String {
            
            passageLogger.debug("Message type: \(type), full data: \(data)")
            
            switch type {
            case PassageConstants.MessageTypes.connectionSuccess:
                handleConnectionSuccess(data)
            case PassageConstants.MessageTypes.connectionError:
                handleConnectionError(data)
            default:
                passageLogger.debug("Forwarding message to remote control: \(type)")
                // Forward other messages to remote control
                remoteControl?.handleWebViewMessage(data)
            }
        } else {
            passageLogger.warn("Received message in unexpected format: \(String(describing: message))")
        }
    }
    
    private func handleConnectionSuccess(_ data: [String: Any]) {
        let history = parseHistory(from: data["history"])
        let connectionId = data["connectionId"] as? String ?? ""
        
        let successData = PassageSuccessData(
            history: history,
            connectionId: connectionId
        )
        
        onSuccess?(successData)
        webViewController?.dismiss(animated: true) {
            self.cleanup()
        }
    }
    
    private func handleConnectionError(_ data: [String: Any]) {
        let error = data["error"] as? String ?? "Unknown error"
        let errorData = PassageErrorData(error: error, data: data)
        
        onError?(errorData)
        webViewController?.dismiss(animated: true) {
            self.cleanup()
        }
    }
    
    private func handleClose() {
        onClose?()
        cleanup()
    }
    
    private func parseHistory(from data: Any?) -> [PassageHistoryItem] {
        guard let historyArray = data as? [[String: Any]] else { return [] }
        
        return historyArray.map { item in
            let structuredData = item["structuredData"]
            var additionalData = item
            additionalData.removeValue(forKey: "structuredData")
            
            return PassageHistoryItem(
                structuredData: structuredData,
                additionalData: additionalData
            )
        }
    }
    
    private func cleanup() {
        webViewController = nil
        remoteControl?.disconnect()
        navigationCompletionHandler = nil
    }
    
    private func topMostViewController() -> UIViewController? {
        guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }),
              var topController = window.rootViewController else {
            return nil
        }
        
        while let presentedViewController = topController.presentedViewController {
            topController = presentedViewController
        }
        
        return topController
    }
    
    private func cookieMatchesURL(cookie: HTTPCookie, url: URL) -> Bool {
        guard let host = url.host else { return false }
        
        // Check domain
        let cookieDomain = cookie.domain.hasPrefix(".") ? cookie.domain : ".\(cookie.domain)"
        let hostWithDot = ".\(host)"
        
        if !hostWithDot.hasSuffix(cookieDomain) && host != cookie.domain {
            return false
        }
        
        // Check path
        let path = url.path.isEmpty ? "/" : url.path
        if !path.hasPrefix(cookie.path) {
            return false
        }
        
        // Check secure
        if cookie.isSecure && url.scheme != "https" {
            return false
        }
        
        return true
    }
}

// MARK: - WebViewModalDelegate
extension PassageSDK: WebViewModalDelegate {
    func webViewModalDidClose() {
        passageLogger.debug("WebViewModalDelegate: webViewModalDidClose called")
        handleClose()
    }
    
    func webViewModal(didNavigateTo url: URL) {
        passageLogger.debug("WebViewModalDelegate: didNavigateTo called with URL: \(passageLogger.truncateUrl(url.absoluteString, maxLength: 100))")
        
        // Call the navigation completion handler if it exists
        if let handler = navigationCompletionHandler {
            passageLogger.debug("WebViewModalDelegate: calling navigation completion handler")
            navigationCompletionHandler = nil
            handler(.success(url.absoluteString))
        }
    }
}
