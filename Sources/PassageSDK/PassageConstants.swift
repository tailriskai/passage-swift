import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Passage Constants
// These constants should be kept in sync with the web implementation

public enum PassageConstants {
    // Message types for WebView communication
    public enum MessageTypes {
        static let connectionSuccess = "CONNECTION_SUCCESS"
        static let connectionError = "CONNECTION_ERROR"
        static let message = "message"
        static let navigate = "navigate"
        static let close = "close"
        static let setTitle = "setTitle"
        static let backPressed = "backPressed"
        static let pageLoaded = "page_loaded"
        static let scriptInjection = "script_injection"
    }
    
    // Presentation styles
    public enum PresentationStyles {
        static let fullScreen = "fullScreen"
        static let pageSheet = "pageSheet"
        static let formSheet = "formSheet"
        static let automatic = "automatic"
    }
    
    // Event names for communication
    public enum EventNames {
        static let messageReceived = "messageReceived"
        static let modalClosed = "modalClosed"
        static let navigationFinished = "navigationFinished"
        static let connectionSuccess = "connectionSuccess"
        static let connectionError = "connectionError"
        static let buttonClicked = "buttonClicked"
        static let webViewSwitched = "webViewSwitched"
    }
    
    // WebView message handler names
    public enum MessageHandlers {
        static let passageWebView = "passageWebView"
        static let capacitorWebViewModal = "capacitorWebViewModal"
    }
    
    // WebView identifiers
    public enum WebViewTypes {
        static let ui = "ui"
        static let automation = "automation"
    }
    
    // Default values
    public enum Defaults {
        public static let modalTitle = ""
        public static let showGrabber = false
        public static let baseUrl = "https://ui.getpassage.ai"
        public static let socketUrl = "https://api.getpassage.ai"
        public static let socketNamespace = "/ws"
        public static let loggerEndpoint = "https://ui.getpassage.ai/api/logger"
        public static let agentName = "passage-swift"
    }
    
    // Error domains
    public enum ErrorDomains {
        static let passage = "PassageSDK"
    }
    
    // URL schemes for local content validation
    public enum URLSchemes {
        static let capacitor = "capacitor://"
        static let httpLocalhost = "http://localhost"
        static let httpLocal = "http://192.168"
    }
    
    // WebView configuration keys
    public enum WebViewConfigKeys {
        static let allowFileAccessFromFileURLs = "allowFileAccessFromFileURLs"
        static let allowUniversalAccessFromFileURLs = "allowUniversalAccessFromFileURLs"
    }
    
    // View colors (matching web app)
    public struct Colors {
        #if canImport(UIKit)
        static let webViewBackground = UIColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1.0) // #f5f5f5
        #endif
    }
    
    // Logging configuration
    public enum Logging {
        static let maxDataLength = 1000 // Maximum characters for logging data
        static let maxCookieLength = 200 // Maximum characters for cookie data
        static let maxHtmlLength = 500 // Maximum characters for HTML data
    }
    
    // Path constants
    public enum Paths {
        static let connect = "/connect"
        static let automationConfig = "/automation/configuration"
        static let automationCommandResult = "/automation/command-result"
    }
    
    // Socket configuration
    public enum Socket {
        static let timeout = 10000
        static let transports = ["websocket", "polling"]
    }
}
